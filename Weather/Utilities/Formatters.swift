//
//  Formatters.swift
//  Weather
//
//  Display formatting that honors each location's own timezone.
//

import Foundation

/// User-selectable clock style; `.system` follows the device's locale setting.
nonisolated enum TimeFormat: String, CaseIterable {
    case system
    case twelveHour
    case twentyFourHour
}

/// Rain amounts: `.auto` follows the temperature unit (°F → inches, °C → mm).
nonisolated enum PrecipUnit: String, CaseIterable, Codable {
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
nonisolated enum PressureUnit: String, CaseIterable {
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

    /// Visibility arrives from the API in metres; shown as miles alongside °F,
    /// kilometres alongside °C.
    static func visibility(_ meters: Double, unit: TemperatureUnit) -> String {
        if unit == .fahrenheit {
            let miles = meters / 1609.344
            return miles >= 10 ? "10+ mi" : String(format: "%.1f mi", miles)
        }
        let km = meters / 1000
        return km >= 16 ? "16+ km" : String(format: "%.1f km", km)
    }

    static func precip(_ value: Double, unit: TemperatureUnit) -> String {
        precipUnit.apiValue(temperatureUnit: unit) == "inch"
            ? String(format: "%.2f in", value)
            : String(format: "%.1f mm", value)
    }

    /// Building a `DateFormatter` costs far more than using one, and these are
    /// called per row of every hourly strip, daily list and chart — so each
    /// distinct (style, timezone, clock setting, locale) is built once and kept.
    private static var formatters: [String: DateFormatter] = [:]
    private static var calendars: [String: Calendar] = [:]

    /// The device's 24-Hour Time toggle changes `hourCycle` but *not* the
    /// locale identifier, and a built formatter never re-resolves it — so it's
    /// part of the key, and the whole cache also flushes on any locale-prefs
    /// change (calendar, first weekday, …) as a catch-all.
    private static let localeChangeObserver: Void = {
        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                formatters.removeAll()
                calendars.removeAll()
            }
        }
    }()

    private static func formatter(_ style: String,
                                  timezone: TimeZone,
                                  configure: (DateFormatter) -> Void) -> DateFormatter {
        _ = localeChangeObserver
        let locale = Locale.current
        let key = "\(style)|\(timezone.identifier)|\(timeFormat.rawValue)|\(locale.identifier)|\(locale.hourCycle)"
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.timeZone = timezone
        f.locale = locale
        configure(f)
        formatters[key] = f
        return f
    }

    private static func calendar(_ timezone: TimeZone) -> Calendar {
        let key = "\(timezone.identifier)|\(Locale.current.identifier)"
        if let cached = calendars[key] { return cached }
        var cal = Calendar.current
        cal.timeZone = timezone
        calendars[key] = cal
        return cal
    }

    static func hour(_ date: Date, timezone: TimeZone) -> String {
        let f = formatter("hour", timezone: timezone) { f in
            switch timeFormat {
            case .system:         f.setLocalizedDateFormatFromTemplate("ha")
            case .twelveHour:     f.dateFormat = "ha"
            case .twentyFourHour: f.dateFormat = "HH"
            }
        }
        return f.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    static func time(_ date: Date, timezone: TimeZone) -> String {
        let f = formatter("time", timezone: timezone) { f in
            switch timeFormat {
            case .system:         f.timeStyle = .short
            case .twelveHour:     f.dateFormat = "h:mm a"
            case .twentyFourHour: f.dateFormat = "HH:mm"
            }
        }
        return f.string(from: date)
    }

    static func weekday(_ date: Date, timezone: TimeZone) -> String {
        formatter("weekday", timezone: timezone) { $0.dateFormat = "EEE" }
            .string(from: date)
    }

    static func fullWeekday(_ date: Date, timezone: TimeZone) -> String {
        formatter("fullWeekday", timezone: timezone) { $0.dateFormat = "EEEE" }
            .string(from: date)
    }

    /// Masthead date line, e.g. "Thursday, June 4".
    static func longDate(_ date: Date, timezone: TimeZone) -> String {
        formatter("longDate", timezone: timezone) { $0.setLocalizedDateFormatFromTemplate("EEEEMMMMd") }
            .string(from: date)
    }

    static func isToday(_ date: Date, timezone: TimeZone) -> Bool {
        calendar(timezone).isDateInToday(date)
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
