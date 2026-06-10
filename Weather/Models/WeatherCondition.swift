//
//  WeatherCondition.swift
//  Weather
//
//  Interpretation of WMO weather interpretation codes (Open-Meteo `weather_code`)
//  into human descriptions, SF Symbols, and the visual identity used to drive
//  the dynamic sky.
//

import SwiftUI

struct WeatherCondition: Equatable {
    let code: Int
    let isDay: Bool

    enum Kind {
        case clear, mainlyClear, partlyCloudy, overcast, fog
        case drizzle, rain, freezingRain, snow, snowGrains, showers, snowShowers
        case thunderstorm, thunderstormHail
        case unknown
    }

    var kind: Kind {
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

    var description: String {
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

    /// Multicolor SF Symbol that renders beautifully with `.symbolRenderingMode(.multicolor)`.
    var symbolName: String {
        switch kind {
        case .clear:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mainlyClear:
            return isDay ? "sun.max.fill" : "moon.fill"
        case .partlyCloudy:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast:
            return "cloud.fill"
        case .fog:
            return isDay ? "sun.haze.fill" : "cloud.fog.fill"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .rain:
            return "cloud.rain.fill"
        case .freezingRain:
            return "cloud.sleet.fill"
        case .snow, .snowGrains:
            return "cloud.snow.fill"
        case .showers:
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snowShowers:
            return "cloud.snow.fill"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        case .thunderstormHail:
            return "cloud.bolt.fill"
        case .unknown:
            return "cloud.fill"
        }
    }

    var isPrecipitating: Bool {
        switch kind {
        case .drizzle, .rain, .freezingRain, .snow, .snowGrains,
             .showers, .snowShowers, .thunderstorm, .thunderstormHail:
            return true
        default:
            return false
        }
    }

    var isSnowy: Bool {
        switch kind {
        case .snow, .snowGrains, .snowShowers: return true
        default: return false
        }
    }

    var isStormy: Bool {
        kind == .thunderstorm || kind == .thunderstormHail
    }

    // MARK: - Sky palette

    /// Top-to-bottom gradient stops for the animated sky background.
    var skyColors: [Color] {
        func hex(_ v: UInt) -> Color { Color(hex: v) }

        if isDay {
            switch kind {
            case .clear, .mainlyClear:
                return [hex(0x2C6BD6), hex(0x4F95E8), hex(0x8FC2F2)]
            case .partlyCloudy:
                return [hex(0x3A6FB0), hex(0x5E92C8), hex(0x9DBBD6)]
            case .overcast, .fog:
                return [hex(0x5A6B7A), hex(0x7C8A98), hex(0xA7B2BC)]
            case .drizzle, .rain, .showers, .freezingRain:
                return [hex(0x36495C), hex(0x4E657B), hex(0x73879A)]
            case .snow, .snowGrains, .snowShowers:
                return [hex(0x6E7C8C), hex(0x90A0B0), hex(0xC3CDD8)]
            case .thunderstorm, .thunderstormHail:
                return [hex(0x232A38), hex(0x39435A), hex(0x5A6479)]
            case .unknown:
                return [hex(0x3A6FB0), hex(0x5E92C8), hex(0x9DBBD6)]
            }
        } else {
            switch kind {
            case .clear, .mainlyClear:
                return [hex(0x070B1E), hex(0x111A3A), hex(0x24345E)]
            case .partlyCloudy:
                return [hex(0x0A1024), hex(0x182241), hex(0x2C3C60)]
            case .overcast, .fog:
                return [hex(0x14181F), hex(0x232A35), hex(0x39434F)]
            case .drizzle, .rain, .showers, .freezingRain:
                return [hex(0x0A1018), hex(0x161E2A), hex(0x28323F)]
            case .snow, .snowGrains, .snowShowers:
                return [hex(0x161B24), hex(0x2A3340), hex(0x434F5E)]
            case .thunderstorm, .thunderstormHail:
                return [hex(0x05070D), hex(0x10131F), hex(0x222838)]
            case .unknown:
                return [hex(0x0A1024), hex(0x182241), hex(0x2C3C60)]
            }
        }
    }

    /// Accent used for highlights, charts, and glass tints.
    var accent: Color {
        if isStormy { return Color(hex: 0xC9B6FF) }
        if isSnowy { return Color(hex: 0xCFE5FF) }
        switch kind {
        case .clear, .mainlyClear:
            return isDay ? Color(hex: 0xFFD66B) : Color(hex: 0xBFD3FF)
        case .rain, .drizzle, .showers, .freezingRain:
            return Color(hex: 0x8FD0FF)
        default:
            return isDay ? Color(hex: 0xEAF2FF) : Color(hex: 0xBFD3FF)
        }
    }
}

// MARK: - Color hex helper

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
