//
//  WidgetWeather.swift
//  WeatherWidget
//
//  Lets the widget fetch its own forecast so it refreshes on WidgetKit's schedule
//  even when the app isn't opened. Self-contained (a small Open-Meteo request +
//  the WMO/sky mappings) to keep the extension independent of the app target.
//

import Foundation
import WidgetKit

// MARK: - Location shared from the app (matches the app's copy in WidgetSharing)

nonisolated struct WidgetLocation: Codable {
    let latitude: Double
    let longitude: Double
    let name: String
    let timezone: String
    let temperatureUnit: String   // "celsius" | "fahrenheit"
    let windSpeedUnit: String
    let precipitationUnit: String
}

/// Units-only record, written by the app on every successful load — unlike the
/// device-location record, which only follows the device place. Matches the
/// app's copy in `Weather/Services/WidgetSharing.swift`.
nonisolated struct WidgetUnitPrefs: Codable {
    let temperatureUnit: String
    let windSpeedUnit: String
    let precipitationUnit: String
}

extension WeatherSnapshotStore {
    private static var locationKey: String { "weather_widget_location_v1" }
    private static var unitPrefsKey: String { "weather_widget_unit_prefs_v1" }

    static func readLocation() -> WidgetLocation? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: locationKey) else { return nil }
        return try? JSONDecoder().decode(WidgetLocation.self, from: data)
    }

    static func readUnitPrefs() -> WidgetUnitPrefs? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: unitPrefsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetUnitPrefs.self, from: data)
    }

    static func cache(_ snapshot: WeatherWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: "weather_widget_snapshot_v1")
    }
}

// MARK: - Fetcher

enum WidgetWeatherFetcher {
    /// Fetch a fresh snapshot for the saved location, or nil on any failure
    /// (caller falls back to the last cached snapshot).
    static func fetch(_ loc: WidgetLocation) async -> WeatherWidgetSnapshot? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(loc.latitude)),
            .init(name: "longitude", value: String(loc.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"),
            .init(name: "temperature_unit", value: loc.temperatureUnit),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7")
        ]
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return build(try JSONDecoder().decode(Response.self, from: data), loc: loc)
        } catch {
            return nil
        }
    }

    // MARK: Wire format

    private struct Response: Decodable {
        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily

        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let weather_code: [Int]
            let sunrise: [String]
            let sunset: [String]
        }
    }

    private static func build(_ r: Response, loc: WidgetLocation) -> WeatherWidgetSnapshot {
        let tz = TimeZone(identifier: r.timezone) ?? .current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = tz
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let hourFmt = DateFormatter()
        hourFmt.locale = Locale(identifier: "en_US_POSIX")
        hourFmt.timeZone = tz
        hourFmt.dateFormat = "h a"

        let now = Date()
        let isDay = r.current.is_day == 1
        let kind = WidgetConditions.kind(code: r.current.weather_code)

        let temperatureText = degree(r.current.temperature_2m)
        let high = degree(r.daily.temperature_2m_max.first ?? r.current.temperature_2m)
        let low = degree(r.daily.temperature_2m_min.first ?? r.current.temperature_2m)

        // Next six hourly slots from (roughly) now.
        var hours: [WeatherWidgetHour] = []
        for i in r.hourly.time.indices {
            guard let date = parser.date(from: r.hourly.time[i]),
                  date >= now.addingTimeInterval(-3600) else { continue }
            let code = r.hourly.weather_code[safe: i] ?? 0
            let dayHour = (r.hourly.is_day[safe: i] ?? 1) == 1
            hours.append(WeatherWidgetHour(
                time: hourFmt.string(from: date),
                symbol: WidgetConditions.symbol(code: code, isDay: dayHour),
                temp: degree(r.hourly.temperature_2m[safe: i] ?? 0)))
            if hours.count == 6 { break }
        }

        let sunrise = r.daily.sunrise.first.flatMap { parser.date(from: $0) }
        let sunset = r.daily.sunset.first.flatMap { parser.date(from: $0) }
        let phase = WidgetSky.phase(now: now, sunrise: sunrise, sunset: sunset, isDay: isDay)

        // Daily outlook for the large widget.
        let dayParser = DateFormatter()
        dayParser.locale = Locale(identifier: "en_US_POSIX")
        dayParser.timeZone = tz
        dayParser.dateFormat = "yyyy-MM-dd"
        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.timeZone = tz
        weekdayFmt.dateFormat = "EEE"

        var days: [WeatherWidgetDay] = []
        for i in r.daily.time.indices.prefix(6) {
            let name = i == 0 ? "Today"
                : dayParser.date(from: r.daily.time[i]).map { weekdayFmt.string(from: $0) } ?? "—"
            days.append(WeatherWidgetDay(
                name: name,
                symbol: WidgetConditions.symbol(code: r.daily.weather_code[safe: i] ?? 0, isDay: true),
                low: degree(r.daily.temperature_2m_min[safe: i] ?? 0),
                high: degree(r.daily.temperature_2m_max[safe: i] ?? 0)))
        }

        return WeatherWidgetSnapshot(
            locationName: loc.name,
            temperatureText: temperatureText,
            conditionSymbol: WidgetConditions.symbol(code: r.current.weather_code, isDay: isDay),
            conditionText: WidgetConditions.description(code: r.current.weather_code),
            highLowText: "H:\(high)  L:\(low)",
            highText: high,
            lowText: low,
            skyHexes: WidgetSky.gradientHexes(phase: phase, kind: kind),
            accentHex: WidgetConditions.accentHex(kind: kind, isDay: isDay),
            aqiText: nil,
            aqiAlert: false,
            hours: hours,
            days: days,
            updatedAt: now)
    }

    private static func degree(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - WMO conditions (mirror of the app's WeatherCondition)

enum WidgetConditions {
    enum Kind {
        case clear, mainlyClear, partlyCloudy, overcast, fog
        case drizzle, rain, freezingRain, snow, snowGrains, showers, snowShowers
        case thunderstorm, thunderstormHail, unknown
    }

    static func kind(code: Int) -> Kind {
        switch code {
        case 0: return .clear
        case 1: return .mainlyClear
        case 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55: return .drizzle
        case 56, 57: return .freezingRain
        case 61, 63, 65: return .rain
        case 66, 67: return .freezingRain
        case 71, 73, 75: return .snow
        case 77: return .snowGrains
        case 80, 81, 82: return .showers
        case 85, 86: return .snowShowers
        case 95: return .thunderstorm
        case 96, 99: return .thunderstormHail
        default: return .unknown
        }
    }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch kind(code: code) {
        case .clear:           return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear:     return isDay ? "sun.max.fill" : "moon.fill"
        case .partlyCloudy:    return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast:        return "cloud.fill"
        case .fog:             return isDay ? "sun.haze.fill" : "cloud.fog.fill"
        case .drizzle:         return "cloud.drizzle.fill"
        case .rain:            return "cloud.rain.fill"
        case .freezingRain:    return "cloud.sleet.fill"
        case .snow, .snowGrains: return "cloud.snow.fill"
        case .showers:         return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snowShowers:     return "cloud.snow.fill"
        case .thunderstorm:    return "cloud.bolt.rain.fill"
        case .thunderstormHail: return "cloud.bolt.fill"
        case .unknown:         return "cloud.fill"
        }
    }

    static func description(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45: return "Fog"
        case 48: return "Rime Fog"
        case 51: return "Light Drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80: return "Light Showers"
        case 81: return "Showers"
        case 82: return "Violent Showers"
        case 85: return "Snow Showers"
        case 86: return "Heavy Snow Showers"
        case 95: return "Thunderstorm"
        case 96: return "Thunderstorm, Hail"
        case 99: return "Severe Thunderstorm"
        default: return "—"
        }
    }

    static func accentHex(kind: Kind, isDay: Bool) -> UInt {
        switch kind {
        case .thunderstorm, .thunderstormHail: return 0xC9B6FF
        case .snow, .snowGrains, .snowShowers: return 0xCFE5FF
        case .clear, .mainlyClear:             return isDay ? 0xFFD66B : 0xBFD3FF
        case .rain, .drizzle, .showers, .freezingRain: return 0x8FD0FF
        default:                               return isDay ? 0xEAF2FF : 0xBFD3FF
        }
    }
}

// MARK: - Sky palette (mirror of the app's SkyPalette / DayPhase)

enum WidgetSky {
    enum Phase { case night, dawn, day, dusk }

    static func phase(now: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> Phase {
        guard let sunrise, let sunset else { return isDay ? .day : .night }
        let dawnStart = sunrise.addingTimeInterval(-3600)
        let dawnEnd = sunrise.addingTimeInterval(75 * 60)
        let duskStart = sunset.addingTimeInterval(-75 * 60)
        let duskEnd = sunset.addingTimeInterval(50 * 60)
        if now < dawnStart || now > duskEnd { return .night }
        if now <= dawnEnd { return .dawn }
        if now >= duskStart { return .dusk }
        return .day
    }

    static func gradientHexes(phase: Phase, kind: WidgetConditions.Kind) -> [UInt] {
        let base = clearPalette(phase)
        let (moodColor, strength) = mood(kind)
        guard strength > 0 else { return base }
        return base.map { mixHex($0, moodColor, strength) }
    }

    private static func clearPalette(_ phase: Phase) -> [UInt] {
        switch phase {
        case .night: return [0x0A1230, 0x152149, 0x223560]
        case .dawn:  return [0xF3B58C, 0xDCA7BA, 0x96B8E2]
        case .day:   return [0x3D86E6, 0x68A4E8, 0xBCD7F1]
        case .dusk:  return [0x1E376B, 0x73557F, 0xE89A63]
        }
    }

    private static func mood(_ kind: WidgetConditions.Kind) -> (UInt, Double) {
        switch kind {
        case .clear, .mainlyClear, .unknown:           return (0x000000, 0)
        case .partlyCloudy:                            return (0x9AA6B4, 0.16)
        case .overcast, .fog:                          return (0x8C949D, 0.50)
        case .drizzle, .rain, .showers, .freezingRain: return (0x515E6B, 0.55)
        case .snow, .snowGrains, .snowShowers:         return (0xB3BDC9, 0.40)
        case .thunderstorm, .thunderstormHail:         return (0x2B3440, 0.72)
        }
    }

    private static func mixHex(_ a: UInt, _ b: UInt, _ t: Double) -> UInt {
        let t = min(max(t, 0), 1)
        func chan(_ v: UInt, _ shift: UInt) -> Double { Double((v >> shift) & 0xFF) }
        let r = chan(a, 16) + (chan(b, 16) - chan(a, 16)) * t
        let g = chan(a, 8) + (chan(b, 8) - chan(a, 8)) * t
        let bl = chan(a, 0) + (chan(b, 0) - chan(a, 0)) * t
        return (UInt(r.rounded()) << 16) | (UInt(g.rounded()) << 8) | UInt(bl.rounded())
    }
}
