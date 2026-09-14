//
//  WeatherNextQuotaTests.swift
//  WeatherTests
//
//  On 2026-09-08 Google's hourly quota ran dry mid-afternoon and every load
//  after it paid a round trip to be told 429 again, then fell to classic Haze
//  for the day. The quota ledger is what stops that, so these tests pin its
//  arithmetic (a daily block ends at the next midnight in Los Angeles, a
//  per-minute one a minute on, anything unrecognised five minutes on), its
//  memory (a block outlives the process and is never shortened by a sooner
//  one recorded later) and the sentence the footer prints for it. The store
//  is a throwaway UserDefaults suite, wiped before every test; the suite runs
//  serialized because that store is a static the tests swap in.
//

import Testing
import Foundation
@testable import Haze_Weather

private func utc(_ stamp: String) -> Date {
    ISO8601DateFormatter().date(from: stamp)!
}

/// 14:00 PDT on 8 September 2026, the afternoon the hourly quota ran out.
private let afternoon = utc("2026-09-08T21:00:00Z")
/// The midnight that follows it in Los Angeles (PDT is UTC-7).
private let nextMidnight = utc("2026-09-09T07:00:00Z")
/// 23:30 PDT the same evening, already the 9th in UTC.
private let lateEvening = utc("2026-09-09T06:30:00Z")

/// Google's message for the limit that actually tripped, verbatim shape.
private let hourlyDailyMessage = "Quota exceeded for quota metric 'Forecast Hours Usage' and limit 'Forecast Hours Usage per day' of service 'weather.googleapis.com' for consumer 'project_number:123'."
private let perMinuteMessage = "Quota exceeded for quota metric 'Requests' and limit 'Requests per minute' of service 'weather.googleapis.com' for consumer 'project_number:123'."

@Suite("WeatherNext quota ledger", .serialized)
struct WeatherNextQuotaTests {
    private static let suiteName = "WeatherNextQuotaTests"

    init() {
        let store = UserDefaults(suiteName: Self.suiteName)!
        store.removePersistentDomain(forName: Self.suiteName)
        WeatherNextQuota.store = store
    }

    // MARK: Recording

    @Test("A daily limit blocks the endpoint until the next midnight in Los Angeles, and only that endpoint")
    func perDayBlocksUntilPacificMidnight() {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nextMidnight)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == WeatherNextQuota.resetsAt(now: afternoon))
        // Google meters the endpoints apart: current and days keep serving.
        #expect(WeatherNextQuota.blockedUntil(.currentConditions, now: afternoon) == nil)
        #expect(WeatherNextQuota.blockedUntil(.days, now: afternoon) == nil)
        #expect(WeatherNextQuota.blockedUntil(.history, now: afternoon) == nil)
    }

    @Test("resetsAt is the next 00:00 Pacific however late the evening, and a DST day is a calendar day")
    func resetsAt() {
        #expect(WeatherNextQuota.resetsAt(now: afternoon) == nextMidnight)
        // 23:30 PDT has half an hour to go, not a day and a half; UTC is
        // already on the 9th and must not pull the answer to the 10th.
        #expect(WeatherNextQuota.resetsAt(now: lateEvening) == nextMidnight)
        // Exactly midnight belongs to the new day: its reset is the one after.
        #expect(WeatherNextQuota.resetsAt(now: nextMidnight) == utc("2026-09-10T07:00:00Z"))
        // 1 November 2026, the night the clocks fall back, is 25 hours long
        // and ends on a PST midnight (08:00Z).
        #expect(WeatherNextQuota.resetsAt(now: utc("2026-11-01T07:00:00Z")) == utc("2026-11-02T08:00:00Z"))
        // 8 March 2026 springs forward and is 23 hours long.
        #expect(WeatherNextQuota.resetsAt(now: utc("2026-03-08T08:00:00Z")) == utc("2026-03-09T07:00:00Z"))
    }

    @Test("A daily block recorded at 23:30 ends thirty minutes later, on the midnight")
    func lateEveningDailyBlock() {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: lateEvening)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: lateEvening) == nextMidnight)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: nextMidnight) == nil)
    }

    @Test("A per-minute limit blocks for a minute, anything unrecognised for five")
    func shortBlocks() {
        WeatherNextQuota.recordExhausted(.days, message: perMinuteMessage, now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.days, now: afternoon) == afternoon.addingTimeInterval(60))

        WeatherNextQuota.recordExhausted(.history, message: "Resource has been exhausted (e.g. check quota).", now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.history, now: afternoon) == afternoon.addingTimeInterval(300))

        // No body at all is the same short pause.
        WeatherNextQuota.recordExhausted(.currentConditions, message: nil, now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.currentConditions, now: afternoon) == afternoon.addingTimeInterval(300))
    }

    @Test("The limit's name is matched whatever its case")
    func caseInsensitive() {
        WeatherNextQuota.recordExhausted(.hours, message: "LIMIT 'FORECAST HOURS USAGE PER DAY'", now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nextMidnight)
        WeatherNextQuota.recordExhausted(.days, message: "Requests Per Minute", now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.days, now: afternoon) == afternoon.addingTimeInterval(60))
    }

    @Test("A later block on file is not shortened by a sooner one, and a sooner one is extended by a later")
    func laterBlockWins() {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: afternoon)
        // A per-minute answer arriving under the daily block must not open
        // the endpoint again a minute later.
        WeatherNextQuota.recordExhausted(.hours, message: perMinuteMessage, now: afternoon.addingTimeInterval(5))
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nextMidnight)

        WeatherNextQuota.recordExhausted(.days, message: perMinuteMessage, now: afternoon)
        WeatherNextQuota.recordExhausted(.days, message: hourlyDailyMessage, now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.days, now: afternoon) == nextMidnight)
    }

    // MARK: Expiry and clearing

    @Test("Once the block has passed the endpoint is open, and the stale entry is gone for good")
    func expiry() {
        WeatherNextQuota.recordExhausted(.hours, message: perMinuteMessage, now: afternoon)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon.addingTimeInterval(59)) != nil)
        // The end instant itself is open: the block is `until > now`.
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon.addingTimeInterval(60)) == nil)
        // The finished block was removed on the way out, so asking about an
        // earlier instant no longer finds it either.
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nil)
    }

    @Test("A 2xx clears the endpoint's block and nothing else")
    func clear() {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: afternoon)
        WeatherNextQuota.recordExhausted(.days, message: hourlyDailyMessage, now: afternoon)
        WeatherNextQuota.clear(.hours)
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nil)
        #expect(WeatherNextQuota.blockedUntil(.days, now: afternoon) == nextMidnight)
        // Clearing an endpoint that was never blocked is harmless.
        WeatherNextQuota.clear(.history)
        #expect(WeatherNextQuota.blockedUntil(.history, now: afternoon) == nil)
    }

    @Test("The block survives a relaunch: a fresh view of the same suite reads it back")
    func persistence() {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: afternoon)
        // A new UserDefaults object over the same domain is what the next
        // process sees; nothing is held in the enum itself.
        WeatherNextQuota.store = UserDefaults(suiteName: Self.suiteName)!
        #expect(WeatherNextQuota.blockedUntil(.hours, now: afternoon) == nextMidnight)
    }

    // MARK: The reason sentence

    @Test("A daily block's reason names the data, midnight Pacific and the time left")
    func dailyReason() {
        #expect(WeatherNextQuota.reason(for: .hours, until: nextMidnight, now: afternoon)
                == "Google's daily quota for hourly forecasts is used up until midnight Pacific (about 10 h).")
        // Under an hour to go it counts minutes, never "about 0 h".
        #expect(WeatherNextQuota.reason(for: .hours, until: nextMidnight, now: lateEvening)
                == "Google's daily quota for hourly forecasts is used up until midnight Pacific (about 30 min).")
        #expect(WeatherNextQuota.reason(for: .days, until: nextMidnight, now: afternoon)
                == "Google's daily quota for daily forecasts is used up until midnight Pacific (about 10 h).")
    }

    @Test("A short block's reason says how long, in each endpoint's own words")
    func shortReason() {
        #expect(WeatherNextQuota.reason(for: .days, until: afternoon.addingTimeInterval(60), now: afternoon)
                == "Google's quota for daily forecasts is used up for about 1 min.")
        #expect(WeatherNextQuota.reason(for: .history, until: afternoon.addingTimeInterval(300), now: afternoon)
                == "Google's quota for past hours is used up for about 5 min.")
        #expect(WeatherNextQuota.reason(for: .currentConditions, until: afternoon.addingTimeInterval(7200), now: afternoon)
                == "Google's quota for current conditions is used up for about 2 h.")
        // A block still on file is still a block, so it never rounds to nothing.
        #expect(WeatherNextQuota.reason(for: .hours, until: afternoon.addingTimeInterval(1), now: afternoon)
                .hasSuffix("about 1 min."))
    }

    @Test("The reason describes the block that was recorded")
    func recordedBlockReadsBack() throws {
        WeatherNextQuota.recordExhausted(.hours, message: hourlyDailyMessage, now: afternoon)
        let until = try #require(WeatherNextQuota.blockedUntil(.hours, now: afternoon))
        let text = WeatherNextQuota.reason(for: .hours, until: until, now: afternoon)
        #expect(text.contains("midnight Pacific"))
        #expect(text.contains("hourly forecasts"))

        WeatherNextQuota.recordExhausted(.days, message: perMinuteMessage, now: afternoon)
        let soon = try #require(WeatherNextQuota.blockedUntil(.days, now: afternoon))
        #expect(WeatherNextQuota.reason(for: .days, until: soon, now: afternoon) == "Google's quota for daily forecasts is used up for about 1 min.")
    }

    @Test("Every reason is one finished sentence naming its endpoint, because the footer prints it as is")
    func reasonsAreSentences() {
        #expect(WeatherNextQuota.Endpoint.allCases.count == 4)
        for endpoint in WeatherNextQuota.Endpoint.allCases {
            for until in [nextMidnight, afternoon.addingTimeInterval(60), afternoon.addingTimeInterval(300)] {
                let text = WeatherNextQuota.reason(for: endpoint, until: until, now: afternoon)
                #expect(text.hasPrefix("Google's"), "\(text)")
                #expect(text.hasSuffix("."), "\(text)")
                #expect(!text.contains("\n"), "\(text)")
                #expect(text.contains(endpoint.phrase), "\(text)")
            }
        }
    }
}
