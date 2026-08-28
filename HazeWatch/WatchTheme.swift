//
//  WatchTheme.swift
//  HazeWatch
//
//  The app's editorial voice on the wrist: EB Garamond (lining figures) for
//  text, Instrument Serif for the display temperature — registered in-process
//  the same way the widget does it, since the Info.plist is auto-generated.
//

import SwiftUI
import CoreText

enum WatchFonts {
    static func register() {
        for name in ["EBGaramondLF-Regular", "EBGaramondLF-Italic",
                     "InstrumentSerif-Regular"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// EB Garamond (lining figures), falling back to the system serif.
    static func watchSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "EBGaramondLF-Italic" : "EBGaramondLF-Regular", size: size)
    }

    /// Instrument Serif — display temperatures only, matching the phone's hero.
    static func watchDisplaySerif(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }
}
