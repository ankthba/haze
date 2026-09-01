//
//  DailyBriefTests.swift
//  WeatherTests
//
//  The composed prose. These assert *behaviour* (which facts appear, and that
//  false claims don't) rather than exact wording, so the copy can be edited
//  without the tests turning into a transcription exercise.
//

import Testing
import Foundation
@testable import Haze_Weather

private let tz = TimeZone(identifier: "America/New_York")!

/// A bundle built around a fixed "now", with knobs for the cases under test.
private func makeBundle(
    now: Date,
    temperature: Double = 70,
    code: Int = 2,
    isDay: Bool = true,
    high: Double = 80,
    low: Double = 60,
    hourlyTemps: [Double]? = nil,
    rainChances: [Double] = [],
    uvIndexes: [Double] = [],
    dewPoint: Double? = nil,
    snowfall: Double? = nil,
    yesterday: YesterdayComparison? = nil,
    windSpeed: Double = 5,
    windGust: Double = 8
) -> WeatherBundle {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let startOfDay = cal.startOfDay(for: now)

    // 24 hourly points across today.
    let hours: [HourPoint] = (0..<24).map { hour in
        let date = startOfDay.addingTimeInterval(Double(hour) * 3600)
        return HourPoint(
            date: date,
            temperature: hourlyTemps?[safeIndex: hour] ?? temperature,
            apparentTemperature: temperature,
            code: code,
            isDay: isDay,
            precipitationProbability: rainChances[safeIndex: hour] ?? 0,
            precipitation: 0,
            windSpeed: windSpeed,
            windDirection: 315,
            humidity: 60,
            uvIndex: uvIndexes[safeIndex: hour] ?? 0)
    }

    var today = DayForecast(
        date: startOfDay, code: code, tempMax: high, tempMin: low,
        apparentMax: high, apparentMin: low,
        sunrise: startOfDay.addingTimeInterval(6 * 3600),
        sunset: startOfDay.addingTimeInterval(20 * 3600),
        uvIndexMax: uvIndexes.max() ?? 3,
        precipitationSum: 0,
        precipitationProbabilityMax: rainChances.max() ?? 0,
        windSpeedMax: windSpeed, windGustMax: windGust, windDirectionDominant: 315)
    today.snowfallSum = snowfall

    var bundle = WeatherBundle(
        place: Place(name: "Fairfax", admin1: "Virginia", country: "United States",
                     countryCode: "US", latitude: 38.85, longitude: -77.3, timezone: tz.identifier),
        timezone: tz,
        current: CurrentWeather(
            date: now, temperature: temperature, apparentTemperature: temperature,
            code: code, isDay: isDay, humidity: 60, precipitation: 0, cloudCover: 40,
            pressure: 1014, windSpeed: windSpeed, windGust: windGust, windDirection: 315,
            uvIndex: uvIndexes.max() ?? 3, visibility: 16000, dewPoint: dewPoint),
        hourly: hours,
        daily: [today],
        airQuality: nil,
        fetchedAt: now)
    bundle.yesterday = yesterday
    return bundle
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func todayAt(_ hour: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let midnight = cal.startOfDay(for: Date())
    return midnight.addingTimeInterval(Double(hour) * 3600)
}

@Suite("Daily brief")
struct DailyBriefTests {
    @Test("Never promises a high that has already happened")
    func eveningDoesNotPromisePastHigh() {
        // 9 PM, 70° now, high was 84° at 3 PM; the remaining hours are cooler.
        var temps = Array(repeating: 70.0, count: 24)
        temps[15] = 84
        for hour in 21..<24 { temps[hour] = 68 }
        let now = todayAt(21)
        let text = DailyBrief.compose(bundle: makeBundle(now: now, temperature: 70,
                                                         high: 84, hourlyTemps: temps),
                                      nowcast: nil, now: now)
        #expect(!text.contains("heading for"))
    }

    @Test("Mentions the high while it is genuinely still ahead")
    func morningPromisesHigh() {
        var temps = Array(repeating: 62.0, count: 24)
        temps[15] = 84
        let now = todayAt(9)
        let text = DailyBrief.compose(bundle: makeBundle(now: now, temperature: 62,
                                                         high: 84, hourlyTemps: temps),
                                      nowcast: nil, now: now)
        #expect(text.contains("heading for"))
        #expect(text.contains("84°"))
    }

    @Test("Imminent rain outranks the hourly outlook")
    func nowcastWins() {
        let now = todayAt(13)
        let nowcast = RainNowcast(phase: .starting(now.addingTimeInterval(2400)))
        let text = DailyBrief.compose(bundle: makeBundle(now: now), nowcast: nowcast, now: now)
        #expect(text.lowercased().contains("rain"))
    }

    @Test("The yesterday line reports the direction of the change")
    func yesterdayComparison() {
        let now = todayAt(13)
        let warmer = DailyBrief.compose(
            bundle: makeBundle(now: now, temperature: 75,
                               yesterday: YesterdayComparison(high: 70, low: 55, sameHourTemperature: 66)),
            nowcast: nil, now: now)
        #expect(warmer.contains("warmer"))

        let cooler = DailyBrief.compose(
            bundle: makeBundle(now: now, temperature: 60,
                               yesterday: YesterdayComparison(high: 80, low: 60, sameHourTemperature: 72)),
            nowcast: nil, now: now)
        #expect(cooler.contains("cooler"))
    }

    @Test("A degree or two apart reads as 'about the same'")
    func yesterdayNearlyIdentical() {
        let now = todayAt(13)
        let text = DailyBrief.compose(
            bundle: makeBundle(now: now, temperature: 71,
                               yesterday: YesterdayComparison(high: 72, low: 55, sameHourTemperature: 70)),
            nowcast: nil, now: now)
        #expect(text.contains("about the same") || text.contains("About the same"))
    }

    @Test("Snow totals appear in the user's unit when there's snow")
    func snowSentence() {
        let now = todayAt(9)
        let imperial = DailyBrief.compose(
            bundle: makeBundle(now: now, code: 73, snowfall: 3.4),
            nowcast: nil, usesFahrenheit: true, now: now)
        #expect(imperial.contains("in"))
        #expect(imperial.lowercased().contains("snow"))

        let metric = DailyBrief.compose(
            bundle: makeBundle(now: now, code: 73, snowfall: 8),
            nowcast: nil, usesFahrenheit: false, now: now)
        #expect(metric.contains("cm"))
    }

    @Test("No snow, no snow sentence")
    func noSnowNoSentence() {
        let now = todayAt(9)
        let text = DailyBrief.compose(bundle: makeBundle(now: now, snowfall: 0),
                                      nowcast: nil, now: now)
        #expect(!text.lowercased().contains("snow totals"))
    }

    @Test("A strong UV stretch is called out with its window")
    func uvWindow() {
        var uv = Array(repeating: 0.0, count: 24)
        for hour in 11...15 { uv[hour] = 9 }
        let now = todayAt(9)
        let text = DailyBrief.compose(bundle: makeBundle(now: now, uvIndexes: uv),
                                      nowcast: nil, now: now)
        #expect(text.contains("UV"))
    }

    @Test("Muggy only above the dew-point threshold, per unit")
    func muggyThreshold() {
        let now = todayAt(13)
        let muggy = DailyBrief.compose(
            bundle: makeBundle(now: now, dewPoint: 72), nowcast: nil,
            usesFahrenheit: true, now: now)
        #expect(muggy.lowercased().contains("muggy"))

        let dry = DailyBrief.compose(
            bundle: makeBundle(now: now, dewPoint: 45), nowcast: nil,
            usesFahrenheit: true, now: now)
        #expect(!dry.lowercased().contains("muggy"))
    }

    @Test("The brief stays short, three sentences at most")
    func restraint() {
        var uv = Array(repeating: 0.0, count: 24)
        for hour in 11...15 { uv[hour] = 10 }
        let now = todayAt(9)
        // Everything at once: snow, UV, wind, mugginess, a yesterday delta.
        let text = DailyBrief.compose(
            bundle: makeBundle(now: now, code: 73, uvIndexes: uv, dewPoint: 72,
                               snowfall: 4,
                               yesterday: YesterdayComparison(high: 40, low: 20, sameHourTemperature: 40),
                               windSpeed: 10, windGust: 40),
            nowcast: nil, now: now)
        // Sentence boundaries are ". " (or the final "."), so a decimal like
        // "4.0 in" doesn't count as two sentences.
        let sentences = text.components(separatedBy: ". ").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(sentences.count <= 3)
    }

    @Test("Always produces something to read")
    func neverEmpty() {
        let now = todayAt(13)
        #expect(!DailyBrief.compose(bundle: makeBundle(now: now), nowcast: nil, now: now).isEmpty)
    }
}
