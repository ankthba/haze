//
//  Astronomy.swift
//  Weather
//
//  Locally computed sky facts — moon phase and golden hour. No network:
//  the moon doesn't need an API.
//

import Foundation

// MARK: - Moon

nonisolated struct MoonPhase {
    /// 0 = new, 0.5 = full, approaching 1 = back to new.
    let fraction: Double

    /// Fraction of the disc lit, 0…1.
    var illumination: Double {
        (1 - cos(2 * .pi * fraction)) / 2
    }

    var name: String {
        switch fraction {
        case ..<0.033, 0.967...: "New Moon"
        case ..<0.217:           "Waxing Crescent"
        case ..<0.283:           "First Quarter"
        case ..<0.467:           "Waxing Gibbous"
        case ..<0.533:           "Full Moon"
        case ..<0.717:           "Waning Gibbous"
        case ..<0.783:           "Last Quarter"
        default:                 "Waning Crescent"
        }
    }

    /// SF Symbol matching the phase (northern-hemisphere orientation).
    var symbolName: String {
        switch fraction {
        case ..<0.033, 0.967...: "moonphase.new.moon"
        case ..<0.217:           "moonphase.waxing.crescent"
        case ..<0.283:           "moonphase.first.quarter"
        case ..<0.467:           "moonphase.waxing.gibbous"
        case ..<0.533:           "moonphase.full.moon"
        case ..<0.717:           "moonphase.waning.gibbous"
        case ..<0.783:           "moonphase.last.quarter"
        default:                 "moonphase.waning.crescent"
        }
    }

    /// Mean-cycle computation from a reference new moon (2000-01-06 18:14 UTC).
    /// The mean synodic month drifts under ±0.6 days from the true phase —
    /// well inside what a phase *name* and glyph can resolve.
    static func current(on date: Date = Date()) -> MoonPhase {
        let reference: TimeInterval = 947_182_440   // 2000-01-06 18:14 UTC
        let synodicMonth = 29.530588 * 86_400
        let elapsed = date.timeIntervalSince1970 - reference
        let fraction = (elapsed / synodicMonth).truncatingRemainder(dividingBy: 1)
        return MoonPhase(fraction: fraction < 0 ? fraction + 1 : fraction)
    }
}

// MARK: - Golden hour

nonisolated enum GoldenHour {
    /// The evening window: the soft hour before sunset. (The morning twin runs
    /// from sunrise; the card shows the evening one, which is the one people
    /// plan around.)
    static func evening(sunset: Date?) -> ClosedRange<Date>? {
        guard let sunset else { return nil }
        return sunset.addingTimeInterval(-3600)...sunset
    }

    static func morning(sunrise: Date?) -> ClosedRange<Date>? {
        guard let sunrise else { return nil }
        return sunrise...sunrise.addingTimeInterval(3600)
    }
}
