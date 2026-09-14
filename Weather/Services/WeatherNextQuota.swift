//
//  WeatherNextQuota.swift
//  Weather
//
//  Google meters the Weather API per endpoint and per day, and the hours
//  endpoint caps a page at 24 records, so one 240 h refresh spends ten hourly
//  calls where current, days and history spend one each. Because the bundle
//  cache is keyed by units, every unit flip used to refetch all of it, and on
//  2026-09-08 the hourly metric ran dry mid-afternoon: from then on every load
//  paid a round trip to Google to be told 429 RESOURCE_EXHAUSTED for the
//  "Forecast Hours Usage per day" limit, and dropped the whole source to
//  classic Haze for the rest of the day.
//
//  This records each endpoint's 429 with the moment its quota comes back
//  (Google's daily quotas reset at midnight Pacific, the per-minute ones a
//  minute on) and answers "may I call?" from UserDefaults, so a blocked
//  endpoint is skipped without a network round trip and the block survives a
//  relaunch. The service treats a block as that endpoint's failure carrying
//  `reason(for:until:now:)`, which is how the notice under the footer can say
//  which quota is gone and when Google is back.
//

import Foundation

nonisolated enum WeatherNextQuota {
    /// One per Google endpoint, because Google meters them separately: the
    /// hourly quota is the one that runs out, and current and days can keep
    /// serving while it does.
    enum Endpoint: String, CaseIterable, Codable {
        case currentConditions, hours, days, history

        /// How the notice names the endpoint's data, in words a user reads.
        var phrase: String {
            switch self {
            case .currentConditions: return "current conditions"
            case .hours: return "hourly forecasts"
            case .days: return "daily forecasts"
            case .history: return "past hours"
            }
        }
    }

    /// Persisted rather than held in memory because the quota outlives the
    /// process: a relaunch inside the block must not spend a round trip to be
    /// told no again. Injectable so tests can point it at a throwaway suite.
    nonisolated(unsafe) static var store: UserDefaults = .standard

    /// Google's daily quotas reset on Pacific time regardless of the project's
    /// or the user's zone.
    static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .current

    /// Nil when calls may proceed. A stored date already in the past is a
    /// finished block and is removed on the way out.
    static func blockedUntil(_ endpoint: Endpoint, now: Date = Date()) -> Date? {
        let key = key(endpoint)
        guard let until = store.object(forKey: key) as? Date else { return nil }
        guard until > now else {
            store.removeObject(forKey: key)
            return nil
        }
        return until
    }

    /// Google's message names the limit that tripped ("... per day", "... per
    /// minute"); anything else gets a short pause so a burst of retries cannot
    /// hammer a limit we did not recognise. A later block already on file is
    /// kept: a per-minute answer arriving under a daily block must not open
    /// the endpoint again a minute later.
    static func recordExhausted(_ endpoint: Endpoint, message: String?, now: Date = Date()) {
        let text = message?.lowercased() ?? ""
        let until: Date
        if text.contains("per day") {
            until = resetsAt(now: now)
        } else if text.contains("per minute") {
            until = now.addingTimeInterval(60)
        } else {
            until = now.addingTimeInterval(300)
        }
        if let existing = blockedUntil(endpoint, now: now), existing > until { return }
        store.set(until, forKey: key(endpoint))
    }

    /// A 2xx proves the quota is back (or was never the problem), so any block
    /// on file is stale.
    static func clear(_ endpoint: Endpoint) {
        store.removeObject(forKey: key(endpoint))
    }

    /// A full sentence for the notice. A block ending on a Pacific midnight is
    /// a daily one and says so; anything shorter just says how long.
    static func reason(for endpoint: Endpoint, until: Date, now: Date = Date()) -> String {
        let remaining = max(0, until.timeIntervalSince(now))
        if endsAtPacificMidnight(until) {
            return "Google's daily quota for \(endpoint.phrase) is used up until midnight Pacific (\(approximate(remaining)))."
        }
        return "Google's quota for \(endpoint.phrase) is used up for \(approximate(remaining))."
    }

    /// The next midnight in America/Los_Angeles after `now`, on a Gregorian
    /// calendar so a DST day is still one calendar day, not 24 h.
    static func resetsAt(now: Date) -> Date {
        let calendar = pacificCalendar
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    // MARK: Helpers

    private static var pacificCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    private static func key(_ endpoint: Endpoint) -> String {
        "weathernext_quota_\(endpoint.rawValue)"
    }

    /// Whole seconds round-trip UserDefaults exactly, so a daily block still
    /// sits on the midnight it was given; the tolerance guards the comparison,
    /// not the storage.
    private static func endsAtPacificMidnight(_ date: Date) -> Bool {
        abs(date.timeIntervalSince(pacificCalendar.startOfDay(for: date))) < 1
    }

    /// "about 6 h" or "about 40 min": hours once there is at least one, and
    /// never "about 0 min", because a block that is still on file is still
    /// a block.
    private static func approximate(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 {
            return "about \(Int((seconds / 3600).rounded())) h"
        }
        return "about \(max(1, Int((seconds / 60).rounded()))) min"
    }
}
