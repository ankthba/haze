//
//  AppSetup.swift
//  Weather
//
//  Launch-time setup shared by the iPhone and Mac apps: the bundled serif
//  faces, and a URL cache big enough to hold a radar timeline.
//

import Foundation
import CoreText

enum AppSetup {
    static func prepare() {
        registerFonts()
        enlargeURLCache()
    }

    /// The default URL cache is a few megabytes, far too small to hold a radar
    /// timeline, so every session re-downloaded tiles it had already seen. With
    /// room to keep them, reopening the radar draws from disk instead of the
    /// network. Cache freshness still follows the servers' own headers.
    private static func enlargeURLCache() {
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
    }

    /// Register the bundled serif faces so `Font.custom` can find them
    /// (the Info.plist is auto-generated, so we register at runtime instead).
    private static func registerFonts() {
        for name in ["EBGaramondLF-Regular", "EBGaramondLF-Italic",
                     "EBGaramondLF-Medium", "EBGaramondLF-SemiBold",
                     "InstrumentSerif-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
