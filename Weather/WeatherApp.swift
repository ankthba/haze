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
    init() { Self.registerFonts() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Register the bundled Instrument Serif faces so `Font.custom` can find them
    /// (the Info.plist is auto-generated, so we register at runtime instead).
    private static func registerFonts() {
        for name in ["InstrumentSerif-Regular", "InstrumentSerif-Italic"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
