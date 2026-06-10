//
//  Haptics.swift
//  Weather
//
//  Tiny imperative wrapper around UIFeedbackGenerator so any tap, selection, or
//  completion across the app can fire a quick, consistent piece of haptic feedback.
//

import UIKit

enum Haptics {
    /// A light tap — the default for taps that open or commit something.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// The subtle tick used while moving through discrete values (pickers, scrubbing).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A success notification thump, e.g. after a refresh lands.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
