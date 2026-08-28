//
//  AppShortcuts.swift
//  Weather
//
//  Siri / Shortcuts / Spotlight entry points. The check-weather intent answers
//  from the published snapshot — display-ready strings, no network, so Siri
//  replies instantly even offline.
//

import AppIntents
import Foundation

struct CheckWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Check the Weather"
    static let description = IntentDescription(
        "Speaks the current conditions from Haze's latest forecast.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = WeatherSnapshotStore.read() else {
            return .result(dialog: "Open Haze once to load a forecast first.")
        }
        var line = "It's \(snapshot.temperatureText) and \(snapshot.conditionText.lowercased()) in \(snapshot.locationName)."
        if !snapshot.highLowText.isEmpty {
            line += " Today runs \(snapshot.lowText) to \(snapshot.highText)."
        }
        return .result(dialog: "\(line)")
    }
}

struct OpenRadarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the Radar"
    static let description = IntentDescription("Opens Haze straight to the precipitation radar.")
    static let openAppWhenRun = true

    /// The app can't be deep-linked synchronously from here; leave a note the
    /// root view acts on the moment the scene is active.
    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        return .result()
    }

    static let pendingKey = "pending_open_radar"
}

struct HazeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckWeatherIntent(),
            phrases: [
                "Check the weather in \(.applicationName)",
                "What's the weather in \(.applicationName)",
            ],
            shortTitle: "Check Weather",
            systemImageName: "cloud.sun")
        AppShortcut(
            intent: OpenRadarIntent(),
            phrases: [
                "Open the radar in \(.applicationName)",
                "Show me the \(.applicationName) radar",
            ],
            shortTitle: "Radar",
            systemImageName: "dot.radiowaves.left.and.right")
    }
}
