//
//  VoiceTests.swift
//  WeatherTests
//
//  Whimsy mode is a wording change, and nothing else. These tests hold that
//  line: the same bundle put through both registers has to keep the same
//  facts, the same restraint, and the same sentence budget, while actually
//  reading differently. They assert *properties* of the two voices rather
//  than exact copy, so the sentences stay editable.
//

import Testing
import Foundation
@testable import Haze_Weather

private let tz = TimeZone(identifier: "America/New_York")!

private func todayAt(_ hour: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.startOfDay(for: Date()).addingTimeInterval(Double(hour) * 3600)
}

/// A bundle with enough going on that most sentence branches have something
/// to say: a warm afternoon still climbing, wind, mugginess, a UV stretch.
/// `hourly` and `daily` are immutable on the bundle, so the knobs the tests
/// need are parameters rather than after-the-fact mutation.
private func busyBundle(now: Date,
                        code: Int = 2,
                        isDay: Bool = true,
                        peakHour: Int? = 16,
                        snowfall: Double? = nil) -> WeatherBundle {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let startOfDay = cal.startOfDay(for: now)

    var temps = Array(repeating: 62.0, count: 24)
    if let peakHour { temps[peakHour] = 84 }
    var uv = Array(repeating: 0.0, count: 24)
    for hour in 11...15 { uv[hour] = 9 }

    let hours: [HourPoint] = (0..<24).map { hour in
        HourPoint(date: startOfDay.addingTimeInterval(Double(hour) * 3600),
                  temperature: temps[hour], apparentTemperature: temps[hour],
                  code: code, isDay: isDay,
                  precipitationProbability: 0, precipitation: 0,
                  windSpeed: 8, windDirection: 315, humidity: 70,
                  uvIndex: uv[hour])
    }

    var today = DayForecast(
        date: startOfDay, code: code, tempMax: 84, tempMin: 60,
        apparentMax: 84, apparentMin: 60,
        sunrise: startOfDay.addingTimeInterval(6 * 3600),
        sunset: startOfDay.addingTimeInterval(20 * 3600),
        uvIndexMax: 9, precipitationSum: 0, precipitationProbabilityMax: 0,
        windSpeedMax: 30, windGustMax: 40, windDirectionDominant: 315)
    today.snowfallSum = snowfall

    var bundle = WeatherBundle(
        place: Place(name: "Fairfax", admin1: "Virginia", country: "United States",
                     countryCode: "US", latitude: 38.85, longitude: -77.3,
                     timezone: tz.identifier),
        timezone: tz,
        current: CurrentWeather(
            date: now, temperature: 62, apparentTemperature: 62,
            code: code, isDay: isDay, humidity: 70, precipitation: 0, cloudCover: 40,
            pressure: 1014, windSpeed: 8, windGust: 40, windDirection: 315,
            uvIndex: 9, visibility: 16000, dewPoint: 72),
        hourly: hours, daily: [today], airQuality: nil, fetchedAt: now)
    bundle.yesterday = YesterdayComparison(high: 70, low: 55, sameHourTemperature: 55)
    return bundle
}

/// Sentence count the way the brief itself is bounded: ". " boundaries, so a
/// decimal inside "4.0 in" doesn't read as two.
private func sentenceCount(_ text: String) -> Int {
    text.components(separatedBy: ". ")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .count
}

private func rating(score: Int, cloudLow: Double = 20, rainRisk: Int = 0,
                    clarity: Int = 75) -> SunQuality.Rating {
    SunQuality.Rating(score: score, canvas: 80, horizon: 80, clarity: clarity,
                      rainRisk: rainRisk, cloudHigh: 40, cloudMid: 20,
                      cloudLow: cloudLow, humidity: 60, visibility: 20_000)
}

// MARK: - The daily brief

@Suite("Whimsy mode: the daily brief")
struct WhimsyBriefTests {
    @Test("The two voices genuinely read differently")
    func voicesDiffer() {
        let now = todayAt(9)
        let bundle = busyBundle(now: now)
        let straight = DailyBrief.compose(bundle: bundle, nowcast: nil,
                                          voice: .editorial, now: now)
        let playful = DailyBrief.compose(bundle: bundle, nowcast: nil,
                                         voice: .whimsical, now: now)
        #expect(!straight.isEmpty)
        #expect(straight != playful)
    }

    @Test("Whimsy keeps the numbers and the timings")
    func factsSurvive() {
        let now = todayAt(9)
        let playful = DailyBrief.compose(bundle: busyBundle(now: now), nowcast: nil,
                                         voice: .whimsical, now: now)
        #expect(playful.contains("84°"))
    }

    @Test("Whimsy keeps the three-sentence budget")
    func restraintHolds() {
        let now = todayAt(9)
        let playful = DailyBrief.compose(bundle: busyBundle(now: now), nowcast: nil,
                                         voice: .whimsical, now: now)
        #expect(sentenceCount(playful) <= 3)
    }

    @Test("Snow, UV and mugginess each stay one sentence in whimsy")
    func oneSentencePerFact() {
        // Everything at once, both voices: whichever three facts win, neither
        // register may spend more sentences on them than the other.
        let now = todayAt(9)
        let bundle = busyBundle(now: now, code: 73, snowfall: 4)
        let straight = DailyBrief.compose(bundle: bundle, nowcast: nil,
                                          usesFahrenheit: true, voice: .editorial, now: now)
        let playful = DailyBrief.compose(bundle: bundle, nowcast: nil,
                                         usesFahrenheit: true, voice: .whimsical, now: now)
        #expect(sentenceCount(playful) <= 3)
        #expect(sentenceCount(playful) == sentenceCount(straight))
    }

    @Test("Both voices always produce something to read")
    func neverEmpty() {
        let now = todayAt(13)
        for voice in [Voice.editorial, .whimsical] {
            #expect(!DailyBrief.compose(bundle: busyBundle(now: now), nowcast: nil,
                                        voice: voice, now: now).isEmpty)
        }
    }

    @Test("An evening brief never promises a past high, in either voice")
    func noPastHighInEitherVoice() {
        // 9 PM with the day's peak long gone: the guard is shared logic, so
        // whimsy must not talk its way around it.
        let now = todayAt(21)
        let bundle = busyBundle(now: now, isDay: false, peakHour: nil)
        for voice in [Voice.editorial, .whimsical] {
            let text = DailyBrief.compose(bundle: bundle, nowcast: nil,
                                          voice: voice, now: now)
            #expect(!text.contains("84°"))
        }
    }
}

// MARK: - The nowcast line

@Suite("Whimsy mode: the nowcast line")
struct WhimsyNowcastTests {
    @Test("Every phase says something in both voices, and says the time")
    func everyPhaseReads() {
        let now = todayAt(13)
        let start = now.addingTimeInterval(2400)
        let end = now.addingTimeInterval(6000)
        let phases: [RainNowcast.Phase] = [
            .starting(start), .startingAndEnding(start, end), .easing(end), .persisting,
        ]
        for phase in phases {
            let nowcast = RainNowcast(phase: phase)
            let straight = nowcast.sentence(timezone: tz, voice: .editorial)
            let playful = nowcast.sentence(timezone: tz, voice: .whimsical)
            #expect(!straight.isEmpty)
            #expect(!playful.isEmpty)
            #expect(straight != playful)
            #expect(playful.lowercased().contains("rain"))
        }
    }

    @Test("Whimsy keeps the clock time it was given")
    func keepsTheTime() {
        let now = todayAt(13)
        let start = now.addingTimeInterval(2400)
        let stamp = Fmt.time(start, timezone: tz)
        #expect(RainNowcast(phase: .starting(start))
            .sentence(timezone: tz, voice: .whimsical).contains(stamp))
    }
}

// MARK: - Sunrise and sunset

@Suite("Whimsy mode: the sun verdicts")
struct WhimsySunTests {
    @Test("Every tier has both a straight and a playful blurb")
    func blurbsDiffer() {
        for tier in [SunQuality.Tier.poor, .fair, .good, .great, .spectacular] {
            #expect(!tier.blurb(.editorial).isEmpty)
            #expect(!tier.blurb(.whimsical).isEmpty)
            #expect(tier.blurb(.editorial) != tier.blurb(.whimsical))
        }
    }

    @Test("Every signature has both registers")
    func signaturesDiffer() {
        let cases = [rating(score: 10, rainRisk: 80),      // rain likely
                     rating(score: 20, cloudLow: 70),      // walled horizon
                     rating(score: 40, clarity: 40),       // hazy air
                     rating(score: 70)]                    // well-set clouds
        for r in cases {
            #expect(!r.signature(.editorial).isEmpty)
            #expect(r.signature(.editorial) != r.signature(.whimsical))
        }
    }

    @Test("The narrative differs by voice but keeps the event time")
    func narrativeDiffers() {
        let at = todayAt(20)
        let stamp = Fmt.time(at, timezone: tz)
        for score in [10, 35, 55, 75, 95] {
            for kind in [SunEvent.Kind.sunrise, .sunset] {
                let r = rating(score: score)
                let straight = SunQuality.narrative(kind: kind, rating: r, eventDate: at,
                                                    timezone: tz, voice: .editorial)
                let playful = SunQuality.narrative(kind: kind, rating: r, eventDate: at,
                                                   timezone: tz, voice: .whimsical)
                #expect(!straight.isEmpty)
                #expect(!playful.isEmpty)
                #expect(straight != playful)
                // Timing advice only appears from Good upward; when it does,
                // whimsy has to carry the same clock time.
                if straight.contains(stamp) { #expect(playful.contains(stamp)) }
            }
        }
    }

    @Test("Whimsy never lengthens a verdict past the editorial one")
    func narrativeStaysShort() {
        let at = todayAt(20)
        for score in [10, 35, 55, 75, 95] {
            let r = rating(score: score)
            let straight = SunQuality.narrative(kind: .sunset, rating: r, eventDate: at,
                                                timezone: tz, voice: .editorial)
            let playful = SunQuality.narrative(kind: .sunset, rating: r, eventDate: at,
                                               timezone: tz, voice: .whimsical)
            #expect(sentenceCount(playful) <= sentenceCount(straight))
        }
    }
}

// MARK: - The setting itself

@Suite("Whimsy mode: the setting")
struct WhimsySettingTests {
    @Test("The voice follows the stored flag, and defaults to editorial")
    func readsDefaults() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: Voice.defaultsKey) as? Bool
        defer {
            if let original { defaults.set(original, forKey: Voice.defaultsKey) }
            else { defaults.removeObject(forKey: Voice.defaultsKey) }
        }

        defaults.removeObject(forKey: Voice.defaultsKey)
        #expect(Voice.current == .editorial)

        defaults.set(true, forKey: Voice.defaultsKey)
        #expect(Voice.current == .whimsical)

        defaults.set(false, forKey: Voice.defaultsKey)
        #expect(Voice.current == .editorial)
    }

    @Test("The specimens shown in Settings and onboarding differ")
    func specimensDiffer() {
        #expect(Voice.editorial.specimen != Voice.whimsical.specimen)
        #expect(Voice.editorial.notificationSpecimen != Voice.whimsical.notificationSpecimen)
    }

    @Test("The voice is carried between devices")
    func syncedThroughiCloud() {
        #expect(CloudSync.mirroredSettings.contains(Voice.defaultsKey))
    }
}
