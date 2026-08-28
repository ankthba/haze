//
//  WidgetSnapshot.swift
//  WeatherWidget
//
//  The widget's own copy of the shared snapshot read from the App Group. Must
//  stay byte-compatible (Codable keys, App Group id, key) with the app's
//  `Weather/Services/WidgetSharing.swift`. Read-only here.
//

import Foundation
import SwiftUI

nonisolated struct WeatherWidgetHour: Codable, Hashable {
    let time: String
    let symbol: String
    let temp: String
}

nonisolated struct WeatherWidgetDay: Codable, Hashable {
    let name: String
    let symbol: String
    let low: String
    let high: String
}

nonisolated struct WeatherWidgetSnapshot: Codable, Hashable {
    let locationName: String
    let temperatureText: String
    let conditionSymbol: String
    let conditionText: String
    let highLowText: String
    let highText: String
    let lowText: String
    let skyHexes: [UInt]
    let accentHex: UInt
    let aqiText: String?
    let aqiAlert: Bool
    let hours: [WeatherWidgetHour]
    /// Optional so snapshots cached before this field existed still decode.
    let days: [WeatherWidgetDay]?
    let updatedAt: Date

    static let placeholder = WeatherWidgetSnapshot(
        locationName: "Fairfax",
        temperatureText: "81°",
        conditionSymbol: "cloud.sun.fill",
        conditionText: "Partly Cloudy",
        highLowText: "H:88°  L:67°",
        highText: "88°",
        lowText: "67°",
        skyHexes: [0x3A6FB0, 0x5E92C8, 0x9DBBD6],
        accentHex: 0xFFD66B,
        aqiText: "Air quality alert",
        aqiAlert: true,
        hours: [
            .init(time: "11 AM", symbol: "sun.max.fill", temp: "81°"),
            .init(time: "12 PM", symbol: "cloud.sun.fill", temp: "83°"),
            .init(time: "1 PM", symbol: "cloud.sun.fill", temp: "84°"),
            .init(time: "2 PM", symbol: "cloud.fill", temp: "84°"),
            .init(time: "3 PM", symbol: "cloud.sun.fill", temp: "83°"),
            .init(time: "4 PM", symbol: "sun.max.fill", temp: "82°")
        ],
        days: [
            .init(name: "Today", symbol: "cloud.sun.fill", low: "67°", high: "88°"),
            .init(name: "Tue", symbol: "sun.max.fill", low: "70°", high: "90°"),
            .init(name: "Wed", symbol: "cloud.bolt.rain.fill", low: "68°", high: "84°"),
            .init(name: "Thu", symbol: "cloud.rain.fill", low: "65°", high: "79°"),
            .init(name: "Fri", symbol: "cloud.sun.fill", low: "66°", high: "83°")
        ],
        updatedAt: .now)
}

nonisolated enum WeatherSnapshotStore {
    static let appGroup = "group.com.aniketh.Weather"
    static let widgetKind = "WeatherWidget"
    private static let key = "weather_widget_snapshot_v1"

    static func read() -> WeatherWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data)
    }
}

// MARK: - Color hex helper (mirrors the app's)

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
