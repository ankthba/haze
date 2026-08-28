//
//  WeatherApp.swift
//  Weather
//
//  Created by Aniketh Bandlamudi on 6/4/26.
//

import SwiftUI
import CoreText

@main
struct WeatherApp: App {
    init() {
        Self.registerFonts()
        Self.enlargeURLCache()
        // Background-task handlers must be registered before launch finishes.
        RainAlertsService.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// The default URL cache is a few megabytes — far too small to hold a radar
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
