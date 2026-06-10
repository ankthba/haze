//
//  WidgetSharing.swift
//  Weather
//
//  A tiny, dependency-free snapshot the app writes into a shared App Group
//  container after every successful forecast load. The home-screen widget reads
//  the same snapshot to render without doing its own networking. The widget
//  target compiles its own identical copy of `WeatherWidgetSnapshot` /
//  `WeatherSnapshotStore` — keep the two in sync.
//

import Foundation
import WidgetKit

/// One forecast hour, pre-formatted so the widget stays purely presentational.
struct WeatherWidgetHour: Codable, Hashable {
    let time: String      // "11 AM"
    let symbol: String    // SF Symbol name
    let temp: String      // "78°"
}

/// Everything the widget needs to draw, baked into display-ready values.
struct WeatherWidgetSnapshot: Codable, Hashable {
    let locationName: String
    let temperatureText: String   // "81°"
    let conditionSymbol: String
    let conditionText: String     // "Partly Cloudy"
    let highLowText: String       // "H:88°  L:67°"
    let highText: String          // "88°"
    let lowText: String           // "67°"
    let skyHexes: [UInt]          // sky gradient stops (top → bottom)
    let accentHex: UInt
    let aqiText: String?          // "Air quality alert" / "Air quality · Good"
    let aqiAlert: Bool
    let hours: [WeatherWidgetHour]
    let updatedAt: Date

    /// Shown in the widget gallery / before any real data has been written.
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
        updatedAt: .now)
}

/// The location + unit preferences the widget needs to fetch on its own. Mirrors
/// the widget's copy in `WidgetWeather.swift` — keep the two in sync.
struct WidgetLocation: Codable {
    let latitude: Double
    let longitude: Double
    let name: String
    let timezone: String
    let temperatureUnit: String
    let windSpeedUnit: String
    let precipitationUnit: String
}

/// Reads/writes the snapshot in the shared App Group container.
enum WeatherSnapshotStore {
    static let appGroup = "group.com.aniketh.Weather"
    static let widgetKind = "WeatherWidget"
    private static let key = "weather_widget_snapshot_v1"
    private static let locationKey = "weather_widget_location_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func write(_ snapshot: WeatherWidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> WeatherWidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data)
    }

    static func writeLocation(_ location: WidgetLocation) {
        guard let defaults, let data = try? JSONEncoder().encode(location) else { return }
        defaults.set(data, forKey: locationKey)
    }
}

// MARK: - Building a snapshot from live data (app side only)

extension WeatherWidgetSnapshot {
    /// Bake a display-ready snapshot from a freshly loaded bundle, then hand it
    /// to the store and nudge WidgetKit to refresh.
    static func publish(from bundle: WeatherBundle,
                        temperatureUnit: TemperatureUnit,
                        speedUnit: SpeedUnit) {
        WeatherSnapshotStore.write(make(from: bundle))
        WeatherSnapshotStore.writeLocation(WidgetLocation(
            latitude: bundle.place.latitude,
            longitude: bundle.place.longitude,
            name: bundle.place.name,
            timezone: bundle.timezone.identifier,
            temperatureUnit: temperatureUnit.apiValue,
            windSpeedUnit: speedUnit.apiValue,
            precipitationUnit: temperatureUnit == .fahrenheit ? "inch" : "mm"))
        WidgetCenter.shared.reloadTimelines(ofKind: WeatherSnapshotStore.widgetKind)
    }

    static func make(from bundle: WeatherBundle) -> WeatherWidgetSnapshot {
        let tz = bundle.timezone
        let current = bundle.current
        let condition = current.condition

        let hours = bundle.upcomingHours.prefix(6).map { h in
            WeatherWidgetHour(time: Fmt.hour(h.date, timezone: tz),
                              symbol: h.condition.symbolName,
                              temp: Fmt.tempDegree(h.temperature))
        }

        let high = bundle.today.map { Fmt.tempDegree($0.tempMax) } ?? "—"
        let low = bundle.today.map { Fmt.tempDegree($0.tempMin) } ?? "—"
        let highLow = bundle.today == nil ? "" : "H:\(high)  L:\(low)"

        // Use the exact same time-of-day + condition gradient the app shows, so the
        // widget matches the background at dawn/day/dusk/night.
        let phase = DayPhase.current(now: current.date,
                                     sunrise: bundle.today?.sunrise,
                                     sunset: bundle.today?.sunset,
                                     isDay: condition.isDay)
        let skyHexes = SkyPalette.gradientHexes(phase: phase, kind: condition.kind)

        let aqiText: String?
        let aqiAlert: Bool
        if let aq = bundle.airQuality {
            if aq.usAQI > 100 {
                aqiText = "Air quality alert"
                aqiAlert = true
            } else {
                aqiText = "Air quality · \(aq.category.short)"
                aqiAlert = false
            }
        } else {
            aqiText = nil
            aqiAlert = false
        }

        return WeatherWidgetSnapshot(
            locationName: bundle.place.name,
            temperatureText: Fmt.tempDegree(current.temperature),
            conditionSymbol: condition.symbolName,
            conditionText: condition.description,
            highLowText: highLow,
            highText: high,
            lowText: low,
            skyHexes: skyHexes,
            accentHex: condition.accentHex,
            aqiText: aqiText,
            aqiAlert: aqiAlert,
            hours: Array(hours),
            updatedAt: bundle.fetchedAt)
    }
}

/// Bridges the app's `Color`-based palette into plain hex values for the snapshot.
private extension WeatherCondition {
    var accentHex: UInt {
        if isStormy { return 0xC9B6FF }
        if isSnowy { return 0xCFE5FF }
        switch kind {
        case .clear, .mainlyClear:                     return isDay ? 0xFFD66B : 0xBFD3FF
        case .rain, .drizzle, .showers, .freezingRain: return 0x8FD0FF
        default:                                       return isDay ? 0xEAF2FF : 0xBFD3FF
        }
    }
}
