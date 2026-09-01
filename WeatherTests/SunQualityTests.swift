//
//  SunQualityTests.swift
//  WeatherTests
//
//  The sunrise/sunset score is a forecast of a forecast: it reads cloud
//  layers that themselves move between model runs. So the thing worth
//  testing is not a particular number but the score's *steadiness*. A rating
//  that reads 99 and then 45 ten minutes later is useless however defensible
//  each number is on its own, and that is exactly what a product of four
//  steep ramps produced before these bounds existed.
//

import Testing
import Foundation
@testable import Haze_Weather

private let stz = TimeZone(identifier: "America/New_York")!

/// A bundle whose hours around an 8:04 PM sunset all carry the given sky.
private func skyBundle(high: Double, mid: Double, low: Double,
                       humidity: Double = 60, visibility: Double? = 24_000,
                       rain: Double = 0) -> (WeatherBundle, Date) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = stz
    let startOfDay = cal.startOfDay(for: Date())
    let event = startOfDay.addingTimeInterval(20 * 3600 + 4 * 60)

    let hours: [HourPoint] = (0..<24).map { hour in
        var point = HourPoint(date: startOfDay.addingTimeInterval(Double(hour) * 3600),
                              temperature: 70, apparentTemperature: 70, code: 2, isDay: true,
                              precipitationProbability: rain, precipitation: 0,
                              windSpeed: 5, windDirection: 315, humidity: humidity, uvIndex: 3)
        point.cloudCoverHigh = high
        point.cloudCoverMid = mid
        point.cloudCoverLow = low
        point.visibility = visibility
        return point
    }
    let day = DayForecast(date: startOfDay, code: 2, tempMax: 80, tempMin: 60,
                          apparentMax: 80, apparentMin: 60,
                          sunrise: startOfDay.addingTimeInterval(6 * 3600), sunset: event,
                          uvIndexMax: 5, precipitationSum: 0,
                          precipitationProbabilityMax: rain,
                          windSpeedMax: 10, windGustMax: 12, windDirectionDominant: 315)
    let bundle = WeatherBundle(
        place: Place(name: "Austin", admin1: "Texas", country: "United States",
                     countryCode: "US", latitude: 30.27, longitude: -97.74,
                     timezone: stz.identifier),
        timezone: stz,
        current: CurrentWeather(date: startOfDay, temperature: 70, apparentTemperature: 70,
                                code: 2, isDay: true, humidity: humidity, precipitation: 0,
                                cloudCover: 40, pressure: 1014, windSpeed: 5, windGust: 8,
                                windDirection: 315, uvIndex: 3, visibility: visibility,
                                dewPoint: 50),
        hourly: hours, daily: [day], airQuality: nil, fetchedAt: startOfDay)
    return (bundle, event)
}

private func score(high: Double, mid: Double, low: Double,
                   humidity: Double = 60, visibility: Double? = 24_000,
                   rain: Double = 0) -> Int {
    let (bundle, event) = skyBundle(high: high, mid: mid, low: low, humidity: humidity,
                                    visibility: visibility, rain: rain)
    return SunQuality.rate(kind: .sunset, at: event, in: bundle)?.score ?? -1
}

@Suite("Sunrise/sunset rating stability")
struct SunQualityStabilityTests {

    @Test("A one-point change in cloud cover never moves the score more than a few points")
    func continuousInCloudCover() {
        // The cliffs that used to live at deck 60-80 and low 15-40 made a
        // single percent worth tens of points. Only the deliberate low-cloud
        // veto at 80% is allowed to step, and only by a little.
        for mid in stride(from: 0.0, through: 100.0, by: 20) {
            for low in stride(from: 0.0, through: 100.0, by: 20) {
                for high in stride(from: 0.0, through: 99.0, by: 1) {
                    let jump = abs(score(high: high + 1, mid: mid, low: low)
                                   - score(high: high, mid: mid, low: low))
                    #expect(jump <= 5, "high \(high) to \(high + 1) at mid \(mid), low \(low)")
                }
            }
        }
        for high in stride(from: 0.0, through: 100.0, by: 20) {
            for mid in stride(from: 0.0, through: 100.0, by: 20) {
                for low in stride(from: 0.0, through: 99.0, by: 1) {
                    let jump = abs(score(high: high, mid: mid, low: low + 1)
                                   - score(high: high, mid: mid, low: low))
                    #expect(jump <= 10, "low \(low) to \(low + 1) at high \(high), mid \(mid)")
                }
            }
        }
    }

    @Test("Crossing the muggy threshold no longer steps the score")
    func continuousInHumidity() {
        // This was a hard `if humidity > 85` cap that knocked ~28 points off
        // in a single percent, so an evening forecast wobbling around 85%
        // flipped tiers on every refresh.
        for humidity in stride(from: 0.0, through: 99.0, by: 1) {
            let jump = abs(score(high: 45, mid: 20, low: 10, humidity: humidity + 1)
                           - score(high: 45, mid: 20, low: 10, humidity: humidity))
            #expect(jump <= 6, "humidity \(humidity) to \(humidity + 1)")
        }
    }

    @Test("An ordinary model-run nudge does not collapse the score")
    func boundedUnderForecastNoise() {
        // High and mid cloud move together between runs; 15 points each is
        // routine. Before the ramps were eased this pair read 91 then 35,
        // which is the "it was 99, now it's 45" the ratings were accused of.
        let calm = score(high: 45, mid: 20, low: 10)
        let nudged = score(high: 60, mid: 35, low: 25)
        #expect(abs(calm - nudged) <= 30, "\(calm) then \(nudged)")
        // And the verdict should not fall more than one tier.
        let tiers: [SunQuality.Tier] = [.poor, .fair, .good, .great, .spectacular]
        let a = tiers.firstIndex(of: SunQuality.Tier(score: calm))!
        let b = tiers.firstIndex(of: SunQuality.Tier(score: nudged))!
        #expect(abs(a - b) <= 1)
    }

    @Test("More low cloud never improves the outlook")
    func lowCloudIsMonotonic() {
        var previous = 101
        for low in stride(from: 0.0, through: 100.0, by: 5) {
            let current = score(high: 40, mid: 20, low: low)
            #expect(current <= previous, "low \(low) scored \(current) after \(previous)")
            previous = current
        }
    }

    @Test("The hard vetoes still bite")
    func vetoesHold() {
        #expect(score(high: 40, mid: 20, low: 85) <= 18)      // closed low deck
        #expect(score(high: 40, mid: 20, low: 10, rain: 85) <= 25)   // probable rain
    }

    @Test("The scale still spans its full range")
    func stillOpinionated() {
        // Easing the ramps must not flatten every sky into the middle.
        #expect(score(high: 45, mid: 25, low: 5) >= 85)       // the ideal evening
        #expect(score(high: 0, mid: 0, low: 0) < 70)          // clear is pleasant, not top
        #expect(score(high: 100, mid: 100, low: 95) < 25)     // a closed lid
    }
}

// MARK: - The night-before heads-up

@Suite("Night-before sunrise heads-up")
@MainActor
struct SunriseEveningTests {
    /// Save and restore every default this suite touches, so running it does
    /// not rewrite the simulator's real settings for the next test.
    private func withDefaults(_ body: () -> Void) {
        let d = UserDefaults.standard
        let keys = ["sunrise_evening_enabled", "sunrise_evening_minutes_from_midnight",
                    "sunrise_alert_enabled", "sunrise_alert_gate"]
        let saved = keys.map { ($0, d.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
        }
        body()
    }

    @Test("Off by default, and it hangs off the sunrise alert switch")
    func defaultsOff() {
        withDefaults {
            UserDefaults.standard.removeObject(forKey: "sunrise_evening_enabled")
            #expect(NotificationPlanner.sunriseEveningEnabled == false)
        }
    }

    @Test("Defaults to nine in the evening, and remembers a new time")
    func timeDefaultAndRoundTrip() {
        withDefaults {
            UserDefaults.standard.removeObject(forKey: "sunrise_evening_minutes_from_midnight")
            #expect(NotificationPlanner.sunriseEveningMinutes == 21 * 60)
            NotificationPlanner.sunriseEveningMinutes = 20 * 60 + 30
            #expect(NotificationPlanner.sunriseEveningMinutes == 20 * 60 + 30)
        }
    }

    @Test("It uses the sunrise alert's own quality bar")
    func sharesTheGate() {
        withDefaults {
            NotificationPlanner.sunriseAlertGate = .great
            #expect(NotificationPlanner.sunriseAlertGate.minScore == 65)
            NotificationPlanner.sunriseAlertGate = .any
            #expect(NotificationPlanner.sunriseAlertGate.minScore == 0)
        }
    }
}
