//
//  Voice.swift
//  Weather
//
//  The register the app writes in. Every composed sentence (the daily brief,
//  the nowcast line, the sunrise and sunset verdicts, the notifications) is
//  written twice: once measured, once warm. The setting picks which set of
//  words the templates reach for. The facts, the numbers, and the timings are
//  identical in both, and so is the ordering logic that decides which
//  sentences earn their place.
//
//  The whimsical register is warm and charming: the sky gets a little
//  personality ("Snow taking its time", "Fog keeping the view to itself",
//  "the rain is in no hurry to leave"). The trick is that whimsy is SHORT.
//  Character comes from one well-chosen phrase, not from stacked adjectives
//  and similes, because three sentences of ornament in a row read as purple
//  rather than playful. Sarcasm and jokes at the reader's expense belong to
//  neither voice.
//
//  Safety copy is deliberately exempt. A tornado advisory reads the same way
//  whichever voice is chosen.
//

import Foundation

nonisolated enum Voice {
    /// The magazine standfirst: measured, unhurried, quietly precise.
    case editorial
    /// Whimsy mode: the same forecast, with a bit more charm in the telling.
    case whimsical

    /// Where the setting lives. Read straight from defaults rather than from
    /// the view model, so a background refresh rebuilding tomorrow's digest
    /// speaks in whatever voice the app itself is showing.
    static let defaultsKey = "whimsy_mode"

    static var current: Voice {
        UserDefaults.standard.bool(forKey: Self.defaultsKey) ? .whimsical : .editorial
    }

    /// The shape every piece of copy in the app takes: both registers written
    /// side by side at the point of use, so a sentence can never be edited in
    /// one voice and forgotten in the other.
    func pick(_ straight: @autoclosure () -> String,
              whimsy: @autoclosure () -> String) -> String {
        self == .whimsical ? whimsy() : straight()
    }

    // MARK: - Specimens

    /// The sample line under the Settings toggle and on the onboarding page,
    /// so the choice is made by reading it rather than by guessing.
    var specimen: String {
        pick("Sun through drifting cloud, heading for 72° by 4 PM.",
             whimsy: "Clouds wandering past the sun, working up to 72° by 4 PM.")
    }

    /// The rain alert as it actually arrives, title then body, since the
    /// setting reaches the notifications too.
    var notificationSpecimen: String {
        pick("Rain on the way. Starting around 3:40 near Austin.",
             whimsy: "Rain's about to turn up. It arrives around 3:40 near Austin, so take an umbrella.")
    }
}
