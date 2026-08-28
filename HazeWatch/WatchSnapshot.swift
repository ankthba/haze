//
//  WatchSnapshot.swift
//  HazeWatch
//
//  The watch's copy of the shared snapshot, plus its own minimal fetch. Field
//  names and the App Group key match the phone's `WidgetSharing.swift` and the
//  widget's `WidgetSnapshot.swift` byte for byte — that duplication is the
//  project's convention for keeping targets independent.
//

import Foundation

nonisolated struct WatchHour: Codable, Hashable {
    let time: String
    let symbol: String
    let temp: String
}

nonisolated struct WatchDay: Codable, Hashable {
    let name: String
    let symbol: String
    let low: String
    let high: String
}

nonisolated struct WatchSnapshot: Codable, Hashable {
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
    let hours: [WatchHour]
    let days: [WatchDay]?
    let updatedAt: Date

    static let placeholder = WatchSnapshot(
        locationName: "Haze",
        temperatureText: "—°",
        conditionSymbol: "cloud.sun.fill",
        conditionText: "Loading",
        highLowText: "",
        highText: "—°",
        lowText: "—°",
        skyHexes: [0x3D86E6, 0x68A4E8, 0xBCD7F1],
        accentHex: 0xFFD66B,
        aqiText: nil,
        aqiAlert: false,
        hours: [],
        days: nil,
        updatedAt: .distantPast)
}

nonisolated struct WatchLocation: Codable {
    let latitude: Double
    let longitude: Double
    let name: String
    let timezone: String
    let temperatureUnit: String
    let windSpeedUnit: String
    let precipitationUnit: String
}

nonisolated enum WatchSnapshotStore {
    static let appGroup = "group.com.aniketh.Weather"
    private static let snapshotKey = "weather_widget_snapshot_v1"
    private static let locationKey = "weather_widget_location_v1"

    /// What the phone last published. Fresh enough to trust for a glance.
    static func readShared() -> WatchSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.updatedAt) < 60 * 60
        else { return nil }
        return snapshot
    }

    static func readLocation() -> WatchLocation? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: locationKey) else { return nil }
        return try? JSONDecoder().decode(WatchLocation.self, from: data)
    }

    static func cache(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: snapshotKey)
    }

    /// NBM answers, element-optional because Open-Meteo returns null where the
    /// blend has no value and a null must fall back to best-match, not zero.
    private struct NBMWire: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]?
        }
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
        }
        let hourly: Hourly
        let daily: Daily
    }

    /// NBM temperature overlay for US locations — the calibrated blend the NWS
    /// forecast tracks; Open-Meteo's default best_match is raw GFS in the US
    /// and runs hot on daily highs. Nil outside likely coverage or on failure.
    private static func fetchNBM(_ loc: WatchLocation) async -> NBMWire? {
        guard (23.0...51.0).contains(loc.latitude),
              ((-127.0)...(-65.0)).contains(loc.longitude) else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(loc.latitude)),
            .init(name: "longitude", value: String(loc.longitude)),
            .init(name: "models", value: "ncep_nbm_conus"),
            .init(name: "hourly", value: "temperature_2m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: loc.temperatureUnit),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "2"),
        ]
        guard let url = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(NBMWire.self, from: data)
    }

    /// One small Open-Meteo request for the phone's location — the same
    /// single-location shape the widget uses, so watch usage can't multiply
    /// into rate-limit territory.
    static func fetchOwn() async -> WatchSnapshot? {
        guard let loc = readLocation() else { return nil }
        // NBM temperatures ride alongside for US locations, matching the phone
        // app's overlay (best_match is raw GFS there and runs hot on highs).
        async let overlay = fetchNBM(loc)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(loc.latitude)),
            .init(name: "longitude", value: String(loc.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            .init(name: "temperature_unit", value: loc.temperatureUnit),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "2"),
        ]
        guard let url = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }

        struct Wire: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
            }
            // `var` fields are the ones the NBM overlay may splice into.
            struct Hourly: Decodable {
                let time: [String]
                var temperature_2m: [Double]
                let weather_code: [Int]
                let is_day: [Int]
            }
            struct Daily: Decodable {
                let time: [String]
                var temperature_2m_max: [Double]
                var temperature_2m_min: [Double]
                let weather_code: [Int]
            }
            let timezone: String
            let current: Current
            // `var`: the NBM overlay splices into these.
            var hourly: Hourly
            var daily: Daily
        }
        guard var wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }

        // Splice NBM values in by matching wall-clock stamps; null elements
        // and unmatched stamps keep the best-match value.
        if let nbm = await overlay {
            var hourIndex: [String: Int] = [:]
            for (i, t) in wire.hourly.time.enumerated() where hourIndex[t] == nil { hourIndex[t] = i }
            if let temps = nbm.hourly.temperature_2m {
                for (j, t) in nbm.hourly.time.enumerated() {
                    guard j < temps.count, let v = temps[j], let i = hourIndex[t],
                          wire.hourly.temperature_2m.indices.contains(i) else { continue }
                    wire.hourly.temperature_2m[i] = v
                }
            }
            var dayIndex: [String: Int] = [:]
            for (i, t) in wire.daily.time.enumerated() where dayIndex[t] == nil { dayIndex[t] = i }
            for (j, t) in nbm.daily.time.enumerated() {
                guard let i = dayIndex[t] else { continue }
                if let maxs = nbm.daily.temperature_2m_max, j < maxs.count, let v = maxs[j],
                   wire.daily.temperature_2m_max.indices.contains(i) {
                    wire.daily.temperature_2m_max[i] = v
                }
                if let mins = nbm.daily.temperature_2m_min, j < mins.count, let v = mins[j],
                   wire.daily.temperature_2m_min.indices.contains(i) {
                    wire.daily.temperature_2m_min[i] = v
                }
            }
        }

        let tz = TimeZone(identifier: wire.timezone) ?? .current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = tz
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let hourLabel = DateFormatter()
        hourLabel.locale = Locale(identifier: "en_US_POSIX")
        hourLabel.timeZone = tz
        hourLabel.dateFormat = "h a"

        func degree(_ v: Double) -> String { "\(Int(v.rounded()))°" }

        let now = Date()
        var hours: [WatchHour] = []
        for i in wire.hourly.time.indices {
            guard let date = parser.date(from: wire.hourly.time[i]),
                  date >= now.addingTimeInterval(-3600) else { continue }
            hours.append(WatchHour(
                time: hourLabel.string(from: date),
                symbol: WatchConditions.symbol(code: wire.hourly.weather_code[safe: i] ?? 0,
                                               isDay: (wire.hourly.is_day[safe: i] ?? 1) == 1),
                temp: degree(wire.hourly.temperature_2m[safe: i] ?? 0)))
            if hours.count == 6 { break }
        }

        let isDay = wire.current.is_day == 1
        let high = degree(wire.daily.temperature_2m_max.first ?? wire.current.temperature_2m)
        let low = degree(wire.daily.temperature_2m_min.first ?? wire.current.temperature_2m)

        let snapshot = WatchSnapshot(
            locationName: loc.name,
            temperatureText: degree(wire.current.temperature_2m),
            conditionSymbol: WatchConditions.symbol(code: wire.current.weather_code, isDay: isDay),
            conditionText: WatchConditions.description(code: wire.current.weather_code),
            highLowText: "H:\(high)  L:\(low)",
            highText: high,
            lowText: low,
            skyHexes: isDay ? [0x3D86E6, 0x68A4E8, 0xBCD7F1] : [0x0A1230, 0x152149, 0x223560],
            accentHex: isDay ? 0xFFD66B : 0xBFD3FF,
            aqiText: nil,
            aqiAlert: false,
            hours: hours,
            days: nil,
            updatedAt: now)
        cache(snapshot)
        return snapshot
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The WMO mapping, trimmed to what a watch face needs.
nonisolated enum WatchConditions {
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1:       isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2:          isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:          "cloud.fill"
        case 45, 48:     isDay ? "sun.haze.fill" : "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63, 65: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81, 82: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95:         "cloud.bolt.rain.fill"
        case 96, 99:     "cloud.bolt.fill"
        default:         "cloud.fill"
        }
    }

    static func description(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mainly Clear"
        case 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57, 66, 67: "Freezing Rain"
        case 61: "Light Rain"
        case 63: "Rain"
        case 65: "Heavy Rain"
        case 71, 73, 75: "Snow"
        case 77: "Snow Grains"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow Showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm, Hail"
        default: "—"
        }
    }
}
