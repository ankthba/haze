//
//  Formatters.swift
//  Weather
//
//  Display formatting that honors each location's own timezone.
//

import Foundation

enum Fmt {
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

    static func pressure(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    static func precip(_ value: Double, unit: TemperatureUnit) -> String {
        unit == .fahrenheit
            ? String(format: "%.2f in", value)
            : String(format: "%.1f mm", value)
    }

    static func hour(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("ha")
        return f.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    static func time(_ date: Date, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = .current
        f.timeStyle = .short
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
