//
//  UIPrefs.swift
//  Weather
//
//  Accessibility & appearance preferences, persisted and observable. Reads of
//  `UIPrefs.shared` inside a view body register Observation dependencies, so a
//  toggle in Settings re-renders exactly the views that consult the preference
//  (including `Font.serif`, which consults `boldText` while resolving a face).
//
//  Each preference is the OR of two sources: the in-app toggle and the
//  system-wide accessibility setting. A user who has Reduce Motion or Bold Text
//  on for the whole device gets it here without hunting for our duplicate
//  switch; the in-app toggles remain as app-only overrides.
//

import Foundation
import Observation
import UIKit

@Observable
final class UIPrefs {
    static let shared = UIPrefs()

    static let boldTextKey = "ui_bold_text"
    static let increaseContrastKey = "ui_increase_contrast"
    static let reduceTransparencyKey = "ui_reduce_transparency"
    static let reduceMotionKey = "ui_reduce_motion"

    /// Serif faces step up one weight everywhere (regular → medium, medium →
    /// semibold), mirroring the system's Bold Text accessibility setting.
    var boldText: Bool { boldTextOverride || systemBoldText }

    /// The sky always carries a base deepening scrim; this setting strengthens
    /// it further for a higher text-contrast ratio.
    var increaseContrast: Bool { increaseContrastOverride || systemIncreaseContrast }

    /// Frosted surfaces become near-opaque instead of airy glass.
    var reduceTransparency: Bool { reduceTransparencyOverride || systemReduceTransparency }

    /// Suppresses decorative motion: radar opens paused, pulsing icons hold still.
    var reduceMotion: Bool { reduceMotionOverride || systemReduceMotion }

    // MARK: - In-app overrides (persisted; what the Settings toggles bind to)

    var boldTextOverride: Bool {
        didSet { UserDefaults.standard.set(boldTextOverride, forKey: Self.boldTextKey) }
    }
    var increaseContrastOverride: Bool {
        didSet { UserDefaults.standard.set(increaseContrastOverride, forKey: Self.increaseContrastKey) }
    }
    var reduceTransparencyOverride: Bool {
        didSet { UserDefaults.standard.set(reduceTransparencyOverride, forKey: Self.reduceTransparencyKey) }
    }
    var reduceMotionOverride: Bool {
        didSet { UserDefaults.standard.set(reduceMotionOverride, forKey: Self.reduceMotionKey) }
    }

    // MARK: - System accessibility mirrors (tracked, refreshed on change)

    private(set) var systemBoldText: Bool
    private(set) var systemIncreaseContrast: Bool
    private(set) var systemReduceTransparency: Bool
    private(set) var systemReduceMotion: Bool

    private init() {
        let d = UserDefaults.standard
        boldTextOverride = d.bool(forKey: Self.boldTextKey)
        increaseContrastOverride = d.bool(forKey: Self.increaseContrastKey)
        reduceTransparencyOverride = d.bool(forKey: Self.reduceTransparencyKey)
        reduceMotionOverride = d.bool(forKey: Self.reduceMotionKey)

        systemBoldText = UIAccessibility.isBoldTextEnabled
        systemIncreaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
        systemReduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        systemReduceMotion = UIAccessibility.isReduceMotionEnabled

        // Re-mirror live when the user flips a setting in the system Settings
        // app; views re-render because the mirrors are tracked properties.
        let pairs: [(Notification.Name, @MainActor (UIPrefs) -> Void)] = [
            (UIAccessibility.boldTextStatusDidChangeNotification,
             { $0.systemBoldText = UIAccessibility.isBoldTextEnabled }),
            (UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
             { $0.systemIncreaseContrast = UIAccessibility.isDarkerSystemColorsEnabled }),
            (UIAccessibility.reduceTransparencyStatusDidChangeNotification,
             { $0.systemReduceTransparency = UIAccessibility.isReduceTransparencyEnabled }),
            (UIAccessibility.reduceMotionStatusDidChangeNotification,
             { $0.systemReduceMotion = UIAccessibility.isReduceMotionEnabled }),
        ]
        for (name, apply) in pairs {
            NotificationCenter.default.addObserver(forName: name, object: nil,
                                                   queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { apply(self) }
            }
        }
    }
}
