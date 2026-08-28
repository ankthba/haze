//
//  WeatherModels.swift
//  Weather
//
//  Domain + wire models. Data is sourced from Open-Meteo, a free aggregator
//  that blends national weather models (ECMWF, GFS, ICON, etc.) — chosen for
//  accuracy and because it needs no API key.
//

import Foundation

// MARK: - Units

nonisolated enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var apiValue: String { self == .fahrenheit ? "fahrenheit" : "celsius" }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    var short: String { self == .fahrenheit ? "F" : "C" }
}

nonisolated enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
    case mph, kmh, ms
    var id: String { rawValue }
    var apiValue: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "kmh"
        case .ms: return "ms"
        }
    }
    var label: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        case .ms: return "m/s"
        }
    }
}

// MARK: - Place

nonisolated struct Place: Codable, Identifiable, Hashable {
    var id: String { "\(latitude.rounded(to: 3)),\(longitude.rounded(to: 3))" }
    let name: String
    let admin1: String?
    let country: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    var timezone: String?

    var subtitle: String {
        [admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var flag: String {
        guard let code = countryCode, code.count == 2 else { return "" }
        return code.uppercased().unicodeScalars.reduce("") { acc, scalar in
            acc + String(UnicodeScalar(127397 + scalar.value)!)
        }
    }
}

nonisolated private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

// MARK: - Bundle (decoded + transformed forecast)

nonisolated struct WeatherBundle: Codable {
    let place: Place
    let timezone: TimeZone
    let current: CurrentWeather
    let hourly: [HourPoint]
    let daily: [DayForecast]
    let airQuality: AirQuality?
    let fetchedAt: Date
    // Optional so cache entries written before these features decode cleanly.
    /// Next ~3 h of 15-minute precipitation, where the nowcast model covers.
    var minutely: [MinutePoint]?
    /// Yesterday's numbers for the comparison line.
    var yesterday: YesterdayComparison?
    /// Active NWS advisories (US), delivered with the extras.
    var alerts: [WeatherAlert]?

    /// Hours from "now" forward, for the scrolling hourly strip.
    var upcomingHours: [HourPoint] {
        let now = Date()
        let start = hourly.firstIndex { $0.date >= now.addingTimeInterval(-3600) } ?? 0
        return Array(hourly[start...].prefix(24))
    }

    var today: DayForecast? { daily.first }

    /// The forecast is shown the moment it lands; air quality, the nearest
    /// station's observation, and active alerts arrive on their own schedule
    /// and are folded in here, so a slow secondary service never holds up the
    /// screen.
    func applying(airQuality newAirQuality: AirQuality?,
                  observedCode: Int?,
                  alerts newAlerts: [WeatherAlert]?) -> WeatherBundle {
        var enriched = WeatherBundle(
            place: place,
            timezone: timezone,
            current: observedCode.map(current.withCode) ?? current,
            hourly: hourly,
            daily: daily,
            airQuality: newAirQuality ?? airQuality,
            fetchedAt: fetchedAt
        )
        enriched.minutely = minutely
        enriched.yesterday = yesterday
        enriched.alerts = newAlerts ?? alerts
        return enriched
    }

    /// All hourly points falling on the same calendar day as `date`, in the
    /// location's timezone. Empty for days outside the hourly forecast window.
    func hours(on date: Date) -> [HourPoint] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return hourly.filter { cal.isDate($0.date, inSameDayAs: date) }
    }
}

nonisolated struct CurrentWeather: Codable {
    let date: Date
    let temperature: Double
    let apparentTemperature: Double
    let code: Int
    let isDay: Bool
    let humidity: Double
    let precipitation: Double
    let cloudCover: Double
    let pressure: Double
    let windSpeed: Double
    let windGust: Double
    let windDirection: Double
    let uvIndex: Double?
    let visibility: Double?
    let dewPoint: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }

    /// The same reading with the condition code replaced — used when a station
    /// observation arrives after the forecast and overrides the modeled code.
    func withCode(_ newCode: Int) -> CurrentWeather {
        CurrentWeather(date: date, temperature: temperature,
                       apparentTemperature: apparentTemperature, code: newCode,
                       isDay: isDay, humidity: humidity, precipitation: precipitation,
                       cloudCover: cloudCover, pressure: pressure, windSpeed: windSpeed,
                       windGust: windGust, windDirection: windDirection,
                       uvIndex: uvIndex, visibility: visibility, dewPoint: dewPoint)
    }
}

/// Hours and days are identified by their own timestamp rather than a fresh
/// UUID: a refresh then re-renders the rows that actually changed instead of
/// rebuilding every one of them.
nonisolated struct HourPoint: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let temperature: Double
    let apparentTemperature: Double
    let code: Int
    let isDay: Bool
    let precipitationProbability: Double
    let precipitation: Double
    let windSpeed: Double
    let windDirection: Double
    let humidity: Double
    let uvIndex: Double
    // Optional (and `var`) so cache entries from before these fields decode.
    /// Layered cloud cover (%) for the sunrise/sunset quality model.
    var cloudCoverLow: Double?
    var cloudCoverMid: Double?
    var cloudCoverHigh: Double?
    /// Metres; same source as the current-conditions visibility.
    var visibility: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }
}

nonisolated struct DayForecast: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let code: Int
    let tempMax: Double
    let tempMin: Double
    let apparentMax: Double
    let apparentMin: Double
    let sunrise: Date?
    let sunset: Date?
    let uvIndexMax: Double
    let precipitationSum: Double
    let precipitationProbabilityMax: Double
    let windSpeedMax: Double
    let windGustMax: Double
    let windDirectionDominant: Double
    /// Optional (and `var`) so cache entries from before this field decode.
    /// Centimetres in metric mode, inches in imperial.
    var snowfallSum: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: true) }
}

/// One 15-minute precipitation step from the nowcast model — the resolution
/// behind "rain starting around 3:40".
nonisolated struct MinutePoint: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    /// Precipitation over the step, in the request's precipitation unit.
    let precipitation: Double
}

/// Yesterday's reading, kept only as the few numbers the comparison line needs.
nonisolated struct YesterdayComparison: Codable {
    let high: Double
    let low: Double
    /// Yesterday's temperature at (roughly) the current hour, for
    /// "4° warmer than this time yesterday".
    let sameHourTemperature: Double?
}

/// An active advisory from the National Weather Service (US only).
nonisolated struct WeatherAlert: Codable, Identifiable, Equatable {
    let id: String
    let event: String          // "Tornado Warning"
    let headline: String?
    let severity: String       // Extreme | Severe | Moderate | Minor | Unknown
    let details: String
    let instruction: String?
    let ends: Date?
    let source: String         // "NWS Norman OK"

    /// Warnings and watches outrank advisories visually.
    var isUrgent: Bool {
        severity == "Extreme" || severity == "Severe"
    }
}

nonisolated struct AirQuality: Codable {
    let usAQI: Int
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
    let no2: Double?

    var category: AQICategory { AQICategory(aqi: usAQI) }
}

nonisolated enum AQICategory: String {
    case good = "Good"
    case moderate = "Moderate"
    case sensitive = "Unhealthy for Sensitive Groups"
    case unhealthy = "Unhealthy"
    case veryUnhealthy = "Very Unhealthy"
    case hazardous = "Hazardous"

    init(aqi: Int) {
        switch aqi {
        case ..<51: self = .good
        case 51..<101: self = .moderate
        case 101..<151: self = .sensitive
        case 151..<201: self = .unhealthy
        case 201..<301: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    var short: String {
        switch self {
        case .sensitive: return "Sensitive"
        case .veryUnhealthy: return "Very Bad"
        default: return rawValue
        }
    }
}
