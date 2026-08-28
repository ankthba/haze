//
//  AnimatedSkyBackground.swift
//  Weather
//
//  A soft, quiet sky: a smooth vertical gradient whose palette shifts with the
//  weather condition and the time of day (night → dawn → day → dusk), plus one
//  gentle radial glow for depth. No particles — calm and editorial.
//

import SwiftUI

enum DayPhase {
    case night, dawn, day, dusk

    /// Derive the phase from the current moment relative to sunrise/sunset.
    static func current(now: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> DayPhase {
        guard let sunrise, let sunset else { return isDay ? .day : .night }
        let dawnStart = sunrise.addingTimeInterval(-60 * 60)
        let dawnEnd = sunrise.addingTimeInterval(75 * 60)
        let duskStart = sunset.addingTimeInterval(-75 * 60)
        let duskEnd = sunset.addingTimeInterval(50 * 60)

        if now < dawnStart || now > duskEnd { return .night }
        if now <= dawnEnd { return .dawn }
        if now >= duskStart { return .dusk }
        return .day
    }
}

/// The single source of truth for the sky gradient — a clear-sky palette per
/// time-of-day phase, nudged toward the weather's mood colour. Shared so the app
/// background and the widget snapshot produce the *same* colours.
enum SkyPalette {
    static func clearPalette(_ phase: DayPhase) -> [UInt] {
        switch phase {
        case .night: return [0x0A1230, 0x152149, 0x223560]
        case .dawn:  return [0xF3B58C, 0xDCA7BA, 0x96B8E2]
        case .day:   return [0x3D86E6, 0x68A4E8, 0xBCD7F1]
        case .dusk:  return [0x1E376B, 0x73557F, 0xE89A63]
        }
    }

    static func mood(_ kind: WeatherCondition.Kind) -> (UInt, Double) {
        switch kind {
        case .clear, .mainlyClear, .unknown:
            return (0x000000, 0)
        case .partlyCloudy:
            return (0x9AA6B4, 0.16)
        case .overcast, .fog:
            return (0x8C949D, 0.50)
        case .drizzle, .rain, .showers, .freezingRain:
            return (0x515E6B, 0.55)
        case .snow, .snowGrains, .snowShowers:
            return (0xB3BDC9, 0.40)
        case .thunderstorm, .thunderstormHail:
            return (0x2B3440, 0.72)
        }
    }

    /// Linear blend of two hex colours, returned as a hex value.
    static func mixHex(_ a: UInt, _ b: UInt, _ t: Double) -> UInt {
        let t = min(max(t, 0), 1)
        func chan(_ v: UInt, _ shift: UInt) -> Double { Double((v >> shift) & 0xFF) }
        let r = chan(a, 16) + (chan(b, 16) - chan(a, 16)) * t
        let g = chan(a, 8) + (chan(b, 8) - chan(a, 8)) * t
        let bl = chan(a, 0) + (chan(b, 0) - chan(a, 0)) * t
        return (UInt(r.rounded()) << 16) | (UInt(g.rounded()) << 8) | UInt(bl.rounded())
    }

    /// The full gradient (top → bottom) for a phase + condition, as hex stops.
    static func gradientHexes(phase: DayPhase, kind: WeatherCondition.Kind) -> [UInt] {
        let base = clearPalette(phase)
        let (moodColor, strength) = mood(kind)
        guard strength > 0 else { return base }
        return base.map { mixHex($0, moodColor, strength) }
    }
}

struct SkyBackground: View {
    let condition: WeatherCondition
    let now: Date
    let sunrise: Date?
    let sunset: Date?

    private var phase: DayPhase {
        DayPhase.current(now: now, sunrise: sunrise, sunset: sunset, isDay: condition.isDay)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradientStops,
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Soft sun/moon glow, gently diffused.
            glow
                .ignoresSafeArea()
                .blendMode(.screen)

            // Atmospheric haze drifting up from the horizon — a soft, misty
            // lightening that adds depth and a dreamy quality (on brand for Haze)
            // and keeps the lower sky from ever feeling heavy or hard-edged.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: hazeColor.opacity(hazeStrength * 0.5), location: 0.74),
                    .init(color: hazeColor.opacity(hazeStrength), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // The sky always carries a deepening scrim so white type reads
            // comfortably (this is the app's default look); the Increase
            // Contrast setting strengthens it further. Bottom-weighted: the
            // haze lightens the sky exactly where the day palette is already
            // palest, and a flat scrim left the caption text down there under
            // 2:1 contrast in daylight. The extra depth eases in below the
            // fold, so the upper sky keeps its airiness.
            LinearGradient(
                stops: scrimStops(base: UIPrefs.shared.increaseContrast ? 0.38 : 0.22,
                                  bottom: UIPrefs.shared.increaseContrast ? 0.55 : 0.40),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 1.1), value: condition.code)
    }

    private func scrimStops(base: Double, bottom: Double) -> [Gradient.Stop] {
        [
            .init(color: .black.opacity(base), location: 0),
            .init(color: .black.opacity(base), location: 0.45),
            .init(color: .black.opacity(base + (bottom - base) * 0.45), location: 0.72),
            .init(color: .black.opacity(bottom), location: 1),
        ]
    }

    // MARK: - Haze

    /// A soft, phase-tinted mist that pools toward the horizon.
    private var hazeColor: Color {
        switch phase {
        case .day:   return Color(hex: 0xEAF3FB)
        case .dawn:  return Color(hex: 0xF7DAC4)
        case .dusk:  return Color(hex: 0xF3C49C)
        case .night: return Color(hex: 0x9FB2D8)
        }
    }

    private var hazeStrength: Double {
        switch phase {
        case .day:          return 0.17
        case .dawn, .dusk:  return 0.15
        case .night:        return 0.07
        }
    }

    // MARK: - Gradient

    /// Clear-sky palette per phase (top → bottom), then nudged toward the
    /// weather's "mood" colour so conditions read without losing the time of day.
    private var gradientStops: [Color] {
        SkyPalette.gradientHexes(phase: phase, kind: condition.kind).map { Color(hex: $0) }
    }

    // MARK: - Glow

    private var glow: some View {
        let (color, center, opacity) = glowStyle
        return RadialGradient(
            colors: [color.opacity(opacity), .clear],
            center: center,
            startRadius: 0,
            endRadius: 560
        )
    }

    private var glowStyle: (Color, UnitPoint, Double) {
        // Dim the glow under heavy cloud/storm so it doesn't punch through.
        let damp: Double
        switch condition.kind {
        case .overcast, .fog, .thunderstorm, .thunderstormHail: damp = 0.35
        case .drizzle, .rain, .showers, .freezingRain, .snow, .snowGrains, .snowShowers: damp = 0.55
        default: damp = 1
        }
        switch phase {
        case .day:   return (Color(hex: 0xFFF3D2), .init(x: 0.80, y: 0.16), 0.32 * damp)
        case .dawn:  return (Color(hex: 0xFFD9B0), .init(x: 0.26, y: 0.20), 0.30 * damp)
        case .dusk:  return (Color(hex: 0xFF9E66), .init(x: 0.74, y: 0.30), 0.32 * damp)
        case .night: return (Color(hex: 0xC4D4F2), .init(x: 0.72, y: 0.18), 0.13 * damp)
        }
    }
}
