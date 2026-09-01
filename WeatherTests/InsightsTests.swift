//
//  InsightsTests.swift
//  WeatherTests
//
//  The pure logic the app leans on hardest: rain-window detection, the brief's
//  sentence branches, moon phase, and the local-time parsing that everything
//  downstream depends on. No network, no UI, just the functions that would
//  otherwise rot silently.
//

import Testing
import Foundation
@testable import Haze_Weather

// MARK: - Helpers

private let tz = TimeZone(identifier: "America/New_York")!

private func minutes(_ pattern: [Double], from start: Date) -> [MinutePoint] {
    pattern.enumerated().map { index, precip in
        MinutePoint(date: start.addingTimeInterval(Double(index) * 15 * 60),
                    precipitation: precip)
    }
}

// MARK: - RainNowcast

@Suite("Rain nowcast")
struct RainNowcastTests {
    private let wet = 0.12

    @Test("Dry throughout produces no nowcast")
    func dryWindow() {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0, 0, 0, 0, 0], from: now),
                                         now: now, wetThreshold: wet)
        #expect(result == nil)
    }

    @Test("Rain beginning later is reported as starting")
    func startingLater() throws {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0, 0, 0.5, 0.5, 0.5], from: now),
                                         now: now, wetThreshold: wet)
        let phase = try #require(result?.phase)
        guard case .starting(let start) = phase else {
            Issue.record("expected .starting, got \(phase)")
            return
        }
        // Third step = 30 minutes out.
        #expect(abs(start.timeIntervalSince(now) - 1800) < 1)
    }

    @Test("A shower that starts and stops inside the window reports both ends")
    func startsAndEnds() throws {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0, 0.4, 0.4, 0, 0], from: now),
                                         now: now, wetThreshold: wet)
        let phase = try #require(result?.phase)
        guard case .startingAndEnding(let start, let end) = phase else {
            Issue.record("expected .startingAndEnding, got \(phase)")
            return
        }
        #expect(abs(start.timeIntervalSince(now) - 900) < 1)    // step 1
        #expect(abs(end.timeIntervalSince(now) - 2700) < 1)     // step 3
    }

    @Test("Raining now with a clear tail reports easing")
    func easing() throws {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0.5, 0.5, 0, 0, 0], from: now),
                                         now: now, wetThreshold: wet)
        let phase = try #require(result?.phase)
        guard case .easing(let end) = phase else {
            Issue.record("expected .easing, got \(phase)")
            return
        }
        #expect(abs(end.timeIntervalSince(now) - 1800) < 1)
    }

    @Test("Rain throughout reports persisting")
    func persisting() throws {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0.4, 0.4, 0.4, 0.4], from: now),
                                         now: now, wetThreshold: wet)
        let phase = try #require(result?.phase)
        guard case .persisting = phase else {
            Issue.record("expected .persisting, got \(phase)")
            return
        }
    }

    @Test("A single dry step inside a shower is not 'easing'")
    func flickerIsNotEasing() throws {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0.4, 0, 0.4, 0.4], from: now),
                                         now: now, wetThreshold: wet)
        let phase = try #require(result?.phase)
        guard case .persisting = phase else {
            Issue.record("a momentary gap should still read as persisting, got \(phase)")
            return
        }
    }

    @Test("Amounts under the threshold count as dry")
    func traceIsDry() {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0, 0.01, 0.02, 0.01], from: now),
                                         now: now, wetThreshold: wet)
        #expect(result == nil)
    }

    @Test("Steps already past are ignored")
    func pastStepsIgnored() {
        let now = Date()
        // Two steps that ended before now, then dry.
        let stale = minutes([0.9, 0.9, 0, 0], from: now.addingTimeInterval(-3600))
        let result = RainNowcast.compute(minutely: stale, now: now, wetThreshold: wet)
        #expect(result == nil)
    }

    @Test("Too few remaining steps yields nothing")
    func notEnoughSteps() {
        let now = Date()
        let result = RainNowcast.compute(minutely: minutes([0.4], from: now),
                                         now: now, wetThreshold: wet)
        #expect(result == nil)
    }
}

// MARK: - MoonPhase

@Suite("Moon phase")
struct MoonPhaseTests {
    /// 2000-01-06 18:14 UTC is the reference new moon.
    private let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    @Test("The reference epoch is a new moon")
    func referenceIsNew() {
        let phase = MoonPhase.current(on: referenceNewMoon)
        #expect(phase.fraction < 0.01 || phase.fraction > 0.99)
        #expect(phase.name == "New Moon")
        #expect(phase.illumination < 0.01)
    }

    @Test("Half a synodic month later is full")
    func halfCycleIsFull() {
        let half = referenceNewMoon.addingTimeInterval(29.530588 * 86_400 / 2)
        let phase = MoonPhase.current(on: half)
        #expect(phase.name == "Full Moon")
        #expect(phase.illumination > 0.99)
    }

    @Test("A quarter in is the first quarter, half lit")
    func quarterCycle() {
        let quarter = referenceNewMoon.addingTimeInterval(29.530588 * 86_400 / 4)
        let phase = MoonPhase.current(on: quarter)
        #expect(phase.name == "First Quarter")
        #expect(abs(phase.illumination - 0.5) < 0.02)
    }

    @Test("Dates before the epoch still yield a valid fraction")
    func beforeEpoch() {
        let phase = MoonPhase.current(on: referenceNewMoon.addingTimeInterval(-100 * 86_400))
        #expect(phase.fraction >= 0 && phase.fraction < 1)
        #expect(!phase.symbolName.isEmpty)
    }

    @Test("Every phase name maps to a moonphase symbol")
    func symbolsExist() {
        for step in 0..<40 {
            let date = referenceNewMoon.addingTimeInterval(Double(step) * 0.75 * 86_400)
            #expect(MoonPhase.current(on: date).symbolName.hasPrefix("moonphase."))
        }
    }
}

// MARK: - GoldenHour

@Suite("Golden hour")
struct GoldenHourTests {
    @Test("Evening window is the hour before sunset")
    func eveningWindow() throws {
        let sunset = Date()
        let window = try #require(GoldenHour.evening(sunset: sunset))
        #expect(window.upperBound == sunset)
        #expect(abs(window.lowerBound.timeIntervalSince(sunset) + 3600) < 1)
    }

    @Test("No sunset means no window")
    func missingSunset() {
        #expect(GoldenHour.evening(sunset: nil) == nil)
        #expect(GoldenHour.morning(sunrise: nil) == nil)
    }
}

// MARK: - LocalTimeParser

@Suite("Local time parsing")
struct LocalTimeParserTests {
    @Test("Hourly wall-clock strings anchor to the location's zone")
    func parsesDateTime() throws {
        let parser = LocalTimeParser(timezone: tz)
        let date = try #require(parser.date(from: "2026-06-04T15:00"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        #expect(cal.component(.hour, from: date) == 15)
        #expect(cal.component(.day, from: date) == 4)
    }

    @Test("Date-only strings (daily rows) parse too")
    func parsesDateOnly() throws {
        let parser = LocalTimeParser(timezone: tz)
        let date = try #require(parser.date(from: "2026-06-04"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        #expect(cal.component(.day, from: date) == 4)
    }

    @Test("Empty and malformed strings return nil, never a wrong date")
    func rejectsGarbage() {
        let parser = LocalTimeParser(timezone: tz)
        #expect(parser.date(from: "") == nil)
        #expect(parser.date(from: "not a date") == nil)
    }

    @Test("Across the spring-forward gap, hours stay one real hour apart")
    func dstTransition() throws {
        // US DST 2026 begins 2026-03-08; 02:00 local does not exist.
        let parser = LocalTimeParser(timezone: tz)
        let before = try #require(parser.date(from: "2026-03-08T01:00"))
        let after = try #require(parser.date(from: "2026-03-08T03:00"))
        // 01:00 EST -> 03:00 EDT is one real hour.
        #expect(abs(after.timeIntervalSince(before) - 3600) < 1)
    }
}

// MARK: - AQI

@Suite("Air quality categories")
struct AQICategoryTests {
    @Test("Breakpoints land in the right category",
          arguments: [(0, AQICategory.good), (50, .good), (51, .moderate), (100, .moderate),
                      (101, .sensitive), (150, .sensitive), (151, .unhealthy), (200, .unhealthy),
                      (201, .veryUnhealthy), (300, .veryUnhealthy), (301, .hazardous)])
    func breakpoints(value: Int, expected: AQICategory) {
        #expect(AQICategory(aqi: value) == expected)
    }
}

// MARK: - Formatters

@Suite("Formatting")
struct FormatterTests {
    @Test("Wind bearings map to compass labels")
    func windLabels() {
        #expect(Fmt.windDirectionLabel(0) == "N")
        #expect(Fmt.windDirectionLabel(90) == "E")
        #expect(Fmt.windDirectionLabel(180) == "S")
        #expect(Fmt.windDirectionLabel(270) == "W")
        #expect(Fmt.windDirectionLabel(360) == "N")
    }

    @Test("Visibility follows the temperature unit and caps politely")
    func visibility() {
        #expect(Fmt.visibility(16_100, unit: .fahrenheit) == "10+ mi")
        #expect(Fmt.visibility(1609.344, unit: .fahrenheit) == "1.0 mi")
        #expect(Fmt.visibility(20_000, unit: .celsius) == "16+ km")
        #expect(Fmt.visibility(5_000, unit: .celsius) == "5.0 km")
    }

    @Test("UV labels follow the standard bands")
    func uvLabels() {
        #expect(Fmt.uvLabel(1) == "Low")
        #expect(Fmt.uvLabel(4) == "Moderate")
        #expect(Fmt.uvLabel(7) == "High")
        #expect(Fmt.uvLabel(9) == "Very High")
        #expect(Fmt.uvLabel(12) == "Extreme")
    }
}
