//
//  WeatherApp.swift
//  Weather
//
//  Created by Aniketh Bandlamudi on 6/4/26.
//

import SwiftUI

@main
struct WeatherApp: App {
    init() {
        AppSetup.prepare()
        // Background-task handlers must be registered before launch finishes.
        RainAlertsService.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
