//
//  Haptics.swift
//  Weather
//
//  Tiny imperative wrapper around UIFeedbackGenerator so any tap, selection, or
//  completion across the app can fire a quick, consistent piece of haptic feedback.
//

import UIKit

enum Haptics {
    /// Master switch, driven by the Settings toggle (persisted by the view model).
    static var isEnabled = true

    /// A light tap — the default for taps that open or commit something.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// The subtle tick used while moving through discrete values (pickers, scrubbing).
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A success notification thump, e.g. after a refresh lands.
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Choreographed patterns (onboarding)

    /// A rising three-beat swell — soft, medium, full — like a curtain lifting.
    static func crescendo() {
        guard isEnabled else { return }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            try? await Task.sleep(for: .milliseconds(140))
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.75)
            try? await Task.sleep(for: .milliseconds(160))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
        }
    }

    /// A gentle double-tap flourish, like rain's first two drops.
    static func flourish() {
        guard isEnabled else { return }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
            try? await Task.sleep(for: .milliseconds(110))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        }
    }

    /// The settling thump that closes the onboarding — firm, then an echo.
    static func arrival() {
        guard isEnabled else { return }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
            try? await Task.sleep(for: .milliseconds(220))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
        }
    }
}
