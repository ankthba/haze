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

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var apiValue: String { self == .fahrenheit ? "fahrenheit" : "celsius" }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    var short: String { self == .fahrenheit ? "F" : "C" }
}

enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
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

struct Place: Codable, Identifiable, Hashable {
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

private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

// MARK: - Bundle (decoded + transformed forecast)

struct WeatherBundle {
    let place: Place
    let timezone: TimeZone
    let current: CurrentWeather
    let hourly: [HourPoint]
    let daily: [DayForecast]
    let airQuality: AirQuality?
    let fetchedAt: Date

    /// Hours from "now" forward, for the scrolling hourly strip.
    var upcomingHours: [HourPoint] {
        let now = Date()
        let start = hourly.firstIndex { $0.date >= now.addingTimeInterval(-3600) } ?? 0
        return Array(hourly[start...].prefix(24))
    }

    var today: DayForecast? { daily.first }

    /// All hourly points falling on the same calendar day as `date`, in the
    /// location's timezone. Empty for days outside the hourly forecast window.
    func hours(on date: Date) -> [HourPoint] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return hourly.filter { cal.isDate($0.date, inSameDayAs: date) }
    }
}

struct CurrentWeather {
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
}

struct HourPoint: Identifiable {
    let id = UUID()
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

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }
}

struct DayForecast: Identifiable {
    let id = UUID()
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

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: true) }
}

struct AirQuality {
    let usAQI: Int
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
    let no2: Double?

    var category: AQICategory { AQICategory(aqi: usAQI) }
}

enum AQICategory: String {
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
