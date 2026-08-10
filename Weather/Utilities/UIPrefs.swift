//
//  UIPrefs.swift
//  Weather
//
//  Accessibility & appearance preferences, persisted and observable. Reads of
//  `UIPrefs.shared` inside a view body register Observation dependencies, so a
//  toggle in Settings re-renders exactly the views that consult the preference
//  (including `Font.serif`, which consults `boldText` while resolving a face).
//

import Foundation
import Observation

@Observable
final class UIPrefs {
    static let shared = UIPrefs()

    static let boldTextKey = "ui_bold_text"
    static let increaseContrastKey = "ui_increase_contrast"
    static let reduceTransparencyKey = "ui_reduce_transparency"
    static let reduceMotionKey = "ui_reduce_motion"

    /// Serif faces step up one weight everywhere (regular → medium, medium →
    /// semibold), mirroring the system's Bold Text accessibility setting.
    var boldText: Bool {
        didSet { UserDefaults.standard.set(boldText, forKey: Self.boldTextKey) }
    }

    /// The sky always carries a base deepening scrim; this setting strengthens
    /// it further for a higher text-contrast ratio.
    var increaseContrast: Bool {
        didSet { UserDefaults.standard.set(increaseContrast, forKey: Self.increaseContrastKey) }
    }

    /// Frosted surfaces become near-opaque instead of airy glass.
    var reduceTransparency: Bool {
        didSet { UserDefaults.standard.set(reduceTransparency, forKey: Self.reduceTransparencyKey) }
    }

    /// Suppresses decorative motion: radar opens paused, pulsing icons hold still.
    var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: Self.reduceMotionKey) }
    }

    private init() {
        let d = UserDefaults.standard
        boldText = d.bool(forKey: Self.boldTextKey)
        increaseContrast = d.bool(forKey: Self.increaseContrastKey)
        reduceTransparency = d.bool(forKey: Self.reduceTransparencyKey)
        reduceMotion = d.bool(forKey: Self.reduceMotionKey)
    }
}
