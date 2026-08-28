//
//  RainActivity.swift
//  Weather
//
//  Live Activity for an imminent rain window: started while the app is open
//  and rain is due within the nowcast horizon, updated on each refresh, ended
//  when the window passes.
//
//  The app owns every string and colour in the activity — it has the timezone,
//  the user's clock format and the sky palette; the widget only draws. The
//  attributes struct is mirrored in `WeatherWidget/RainLiveActivity.swift` —
//  keep the two byte-identical, ActivityKit matches them by name and coding.
//

import Foundation
import ActivityKit

nonisolated struct RainActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Short and human: "Rain in 25 minutes", "Rain until 5:10".
        let headline: String
        /// One quiet supporting line, or empty.
        let detail: String
        /// One value per 15-minute step for the next three hours, normalised
        /// 0…1 — the shape of the shower.
        let intensities: [Double]
        /// Four labels spread across that window ("Now", "4 PM", "5 PM", "6 PM"),
        /// formatted in the place's own timezone and the user's clock style.
        let axisLabels: [String]
        /// Where in the window the rain starts, 0…1, for the marker line.
        let startFraction: Double?
        /// The app's own sky gradient for this place and hour.
        let skyHexes: [UInt]
        /// Used only for the compact Dynamic Island slot.
        let beginsAt: Date?
    }
    let placeName: String
}

@MainActor
enum RainActivityManager {
    private static var activity: Activity<RainActivityAttributes>?
    /// The place the tracked activity was started for — its placeName is
    /// frozen in the attributes, so state from any other place must never
    /// touch it (a browsed city's rain under the home city's name).
    private static var activityPlaceID: String?

    static func sync(nowcast: RainNowcast?, bundle: WeatherBundle, usesInches: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Live Activities outlive the process: after a relaunch the static is
        // nil while the old activity may still sit on the Lock Screen. Adopt
        // the survivor (and end any extras) instead of requesting a duplicate
        // that could never be ended.
        if activity == nil {
            let survivors = Activity<RainActivityAttributes>.activities
            activity = survivors.first {
                $0.activityState == .active || $0.activityState == .stale
            }
            if activity != nil { activityPlaceID = bundle.place.id }
            for extra in survivors where extra.id != activity?.id {
                Task { await extra.end(nil, dismissalPolicy: .immediate) }
            }
        }

        // A bundle for a different (browsed) place neither updates nor ends
        // the home activity; its own staleDate retires it if needed.
        if activity != nil, activityPlaceID != bundle.place.id { return }

        guard let nowcast else {
            end()
            return
        }

        let state = contentState(for: nowcast, bundle: bundle, usesInches: usesInches)
        let stale = (state.beginsAt ?? Date()).addingTimeInterval(3 * 3600)

        if let activity {
            Task { await activity.update(.init(state: state, staleDate: stale)) }
            return
        }

        // Only *start* for a window with a moment worth waiting for.
        guard state.startFraction != nil || state.beginsAt != nil else { return }
        activity = try? Activity.request(
            attributes: RainActivityAttributes(placeName: bundle.place.name),
            content: .init(state: state, staleDate: stale))
        activityPlaceID = activity != nil ? bundle.place.id : nil
    }

    static func end() {
        guard let current = activity else { return }
        activity = nil
        activityPlaceID = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Composing the state

    private static func contentState(for nowcast: RainNowcast,
                                     bundle: WeatherBundle,
                                     usesInches: Bool) -> RainActivityAttributes.ContentState {
        let tz = bundle.timezone
        let now = Date()

        let steps = (bundle.minutely ?? [])
            .filter { $0.date.addingTimeInterval(15 * 60) > now }
            .prefix(12)
        // Normalised against steady rain rather than the window's own peak, so
        // a drizzle reads as a drizzle instead of being stretched to full
        // height. (Steady ≈ 2.5 mm/h — 0.6 mm per 15-minute step.)
        let steady = usesInches ? 0.025 : 0.6
        let intensities = steps.map { min($0.precipitation / steady, 1) }

        let begins: Date?
        let headline: String
        switch nowcast.phase {
        case .starting(let start):
            begins = start
            headline = Self.arrival(start, timezone: tz)
        case .startingAndEnding(let start, let end):
            begins = start
            headline = "Rain \(Fmt.time(start, timezone: tz)) – \(Fmt.time(end, timezone: tz))"
        case .easing(let end):
            begins = nil
            headline = "Rain easing by \(Fmt.time(end, timezone: tz))"
        case .persisting:
            begins = nil
            headline = "Rain for the next few hours"
        }

        // Where the rain lands inside the three-hour window, so the drawing can
        // mark it in the right place instead of guessing.
        let startFraction: Double? = begins.flatMap { start in
            guard let first = steps.first?.date else { return nil }
            let span: TimeInterval = 3 * 3600
            let offset = start.timeIntervalSince(first)
            return offset >= 0 && offset <= span ? offset / span : nil
        }

        // A quiet second line: when it's worst, if there's a clear peak.
        var detail = ""
        if let peak = steps.max(by: { $0.precipitation < $1.precipitation }),
           peak.precipitation > steady * 0.75 {
            detail = "Heaviest near \(Fmt.time(peak.date, timezone: tz))"
        }

        let phase = DayPhase.current(now: bundle.current.date,
                                     sunrise: bundle.today?.sunrise,
                                     sunset: bundle.today?.sunset,
                                     isDay: bundle.current.isDay)

        return .init(headline: headline,
                     detail: detail,
                     intensities: Array(intensities),
                     axisLabels: axisLabels(from: steps.first?.date ?? now, timezone: tz),
                     startFraction: startFraction,
                     skyHexes: SkyPalette.gradientHexes(phase: phase,
                                                        kind: bundle.current.condition.kind),
                     beginsAt: begins)
    }

    /// "Rain in 25 minutes" while that reads naturally; a clock time once it's
    /// far enough out that minutes stop being useful.
    private static func arrival(_ start: Date, timezone: TimeZone) -> String {
        let minutes = Int((start.timeIntervalSinceNow / 60).rounded())
        if minutes <= 5 { return "Rain starting now" }
        if minutes < 60 { return "Rain in \(minutes) minutes" }
        return "Rain at \(Fmt.time(start, timezone: timezone))"
    }

    private static func axisLabels(from start: Date, timezone: TimeZone) -> [String] {
        ["Now"] + (1...3).map { hour in
            Fmt.hour(start.addingTimeInterval(Double(hour) * 3600), timezone: timezone)
        }
    }
}
