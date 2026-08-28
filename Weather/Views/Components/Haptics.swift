//
//  Haptics.swift
//  Weather
//
//  Tiny imperative wrapper around UIFeedbackGenerator so any tap, selection, or
//  completion across the app can fire a quick, consistent piece of haptic feedback.
//

import UIKit
import SwiftUI

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

    /// The faintest tick, for content gliding under the finger — soft and low
    /// intensity so a fast scroll reads as a texture, not a drumroll.
    static func scrollTick() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
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

// MARK: - Scroll ticks

/// A soft haptic tick each time another column passes under the finger while a
/// horizontal strip scrolls — the paper texture of flipping through hours.
private struct ScrollTickHaptics: ViewModifier {
    /// Distance between ticks: one column width including spacing.
    let stride: CGFloat
    @State private var tick = 0

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { old, new in
            guard stride > 0, old != new else { return }
            // Rubber-banding at the leading edge oscillates around zero; ticks
            // only count inside real content so the bounce stays silent.
            guard new > 0, old > 0 else { tick = 0; return }
            let newTick = Int((new / stride).rounded(.down))
            guard newTick != tick else { return }
            tick = newTick
            Haptics.scrollTick()
        }
    }
}

extension View {
    /// Ticks softly every `stride` points of horizontal scroll.
    func scrollTickHaptics(every stride: CGFloat) -> some View {
        modifier(ScrollTickHaptics(stride: stride))
    }
}
