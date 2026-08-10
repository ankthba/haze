//
//  Formatters.swift
//  Weather
//
//  Display formatting that honors each location's own timezone.
//

import Foundation

/// User-selectable clock style; `.system` follows the device's locale setting.
enum TimeFormat: String, CaseIterable {
    case system
    case twelveHour
    case twentyFourHour
}

/// Rain amounts: `.auto` follows the temperature unit (°F → inches, °C → mm).
enum PrecipUnit: String, CaseIterable {
    case auto, inch, mm

    /// The Open-Meteo API value, given the current temperature unit.
    func apiValue(temperatureUnit: TemperatureUnit) -> String {
        switch self {
        case .auto: temperatureUnit == .fahrenheit ? "inch" : "mm"
        case .inch: "inch"
        case .mm:   "mm"
        }
    }
}

/// Barometric pressure display unit (data always arrives as hPa).
enum PressureUnit: String, CaseIterable {
    case hPa, inHg

    var label: String {
        switch self {
        case .hPa: "hPa"
        case .inHg: "inHg"
        }
    }
}

enum Fmt {
    /// Set from Settings (persisted by the view model); formatters consult them.
    static var timeFormat: TimeFormat = .system
    static var precipUnit: PrecipUnit = .auto
    static var pressureUnit: PressureUnit = .hPa

    /// Rounded integer temperature, no degree symbol (the UI adds a styled one).
    static func temp(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func tempDegree(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func speed(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// Data arrives as hPa; converted for display when the user prefers inHg.
    static func pressure(_ value: Double) -> String {
        switch pressureUnit {
        case .hPa:  String(format: "%.0f", value)
        case .inHg: String(format: "%.2f", value * 0.02953)
        }
    }

    static func precip(_ value: Double, unit: TemperatureUnit) -> String {
        precipUnit.apiValue(temperatureUnit: unit) == "inch"
            ? String(format: "%.2f in", value)
            : String(format: "%.1f mm", value)
    }

    static func hour(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        switch timeFormat {
        case .system:         f.setLocalizedDateFormatFromTemplate("ha")
        case .twelveHour:     f.dateFormat = "ha"
        case .twentyFourHour: f.dateFormat = "HH"
        }
        return f.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    static func time(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        switch timeFormat {
        case .system:         f.timeStyle = .short
        case .twelveHour:     f.dateFormat = "h:mm a"
        case .twentyFourHour: f.dateFormat = "HH:mm"
        }
        return f.string(from: date)
    }

    static func weekday(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func fullWeekday(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Masthead date line, e.g. "Thursday, June 4".
    static func longDate(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: date)
    }

    static func isToday(_ date: Date, timezone: TimeZone) -> Bool {
        var cal = Calendar.current
        cal.timeZone = timezone
        return cal.isDateInToday(date)
    }

    /// "Updated 3:42 PM" style stamp.
    static func updatedStamp(_ date: Date, timezone: TimeZone) -> String {
        "Updated \(time(date, timezone: timezone))"
    }

    static func windDirectionLabel(_ degrees: Double) -> String {
        let dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees / 22.5).rounded()) % 16
        return dirs[(index + 16) % 16]
    }

    static func uvLabel(_ value: Double) -> String {
        switch value {
        case ..<3: return "Low"
        case 3..<6: return "Moderate"
        case 6..<8: return "High"
        case 8..<11: return "Very High"
        default: return "Extreme"
        }
    }
}
