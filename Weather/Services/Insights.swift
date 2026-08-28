//
//  Insights.swift
//  Weather
//
//  Composed, human sentences derived from the forecast — the nowcast line
//  ("Rain starting around 3:40") and the daily brief, the app's editorial
//  voice doing actual work. Pure functions over the bundle; no networking,
//  no AI, just careful templating.
//

import Foundation

// MARK: - Rain nowcast (15-minute resolution)

struct RainNowcast {
    enum Phase {
        case starting(Date)              // dry now, rain begins
        case startingAndEnding(Date, Date)
        case easing(Date)                // wet now, rain ends
        case persisting                  // wet now, wet through the window
    }
    let phase: Phase

    /// The under-hero sentence. Uses the location's clock.
    func sentence(timezone: TimeZone) -> String {
        switch phase {
        case .starting(let start):
            return "Rain starting around \(Fmt.time(start, timezone: timezone))"
        case .startingAndEnding(let start, let end):
            return "Rain from about \(Fmt.time(start, timezone: timezone)) to \(Fmt.time(end, timezone: timezone))"
        case .easing(let end):
            return "Rain easing around \(Fmt.time(end, timezone: timezone))"
        case .persisting:
            return "Rain continuing for the next few hours"
        }
    }

    /// `wetThreshold` is in the bundle's own precipitation unit — a trace in
    /// millimetres is a different number than a trace in inches, so the caller
    /// (who knows the unit) supplies it.
    static func compute(minutely: [MinutePoint]?,
                        now: Date = Date(),
                        wetThreshold: Double) -> RainNowcast? {
        guard let minutely, !minutely.isEmpty else { return nil }
        // Steps cover [date, date+15min); keep the one in progress and later.
        let steps = minutely.filter { $0.date.addingTimeInterval(15 * 60) > now }
        guard steps.count >= 2 else { return nil }

        let wet = steps.map { $0.precipitation >= wetThreshold }
        let firstWet = wet.firstIndex(of: true)

        if wet[0] {
            // Raining now: find where it stops (and stays stopped).
            if let end = lastingTransition(in: wet, to: false) {
                return RainNowcast(phase: .easing(steps[end].date))
            }
            return RainNowcast(phase: .persisting)
        }
        guard let start = firstWet else { return nil }   // dry throughout
        let startDate = steps[start].date
        // Does it also end inside the window?
        let after = Array(wet[start...])
        if let endOffset = lastingTransition(in: after, to: false), start + endOffset < steps.count {
            return RainNowcast(phase: .startingAndEnding(startDate, steps[start + endOffset].date))
        }
        return RainNowcast(phase: .starting(startDate))
    }

    /// Index of the first flip to `target` that then *holds* for the rest of
    /// the window (a single dry step inside a shower isn't "easing").
    private static func lastingTransition(in states: [Bool], to target: Bool) -> Int? {
        for i in states.indices.dropFirst() where states[i] == target {
            if states[i...].allSatisfy({ $0 == target }) { return i }
        }
        return nil
    }
}

// MARK: - Daily brief

/// Two–three composed sentences describing the day ahead — the magazine's
/// standfirst. Restraint is the design: each sentence earns its place or is
/// dropped.
enum DailyBrief {
    /// `usesFahrenheit` picks the dew-point comfort threshold and snow-unit
    /// label — the bundle's numbers arrive in the user's own units.
    static func compose(bundle: WeatherBundle,
                        nowcast: RainNowcast?,
                        usesFahrenheit: Bool = true,
                        now: Date = Date()) -> String {
        let tz = bundle.timezone

        // Candidates in priority order; the brief takes the first three that
        // apply. Restraint is the design — a standfirst, not a bulletin.
        let candidates: [String?] = [
            skySentence(bundle: bundle, nowcast: nowcast, now: now, timezone: tz),
            snowSentence(bundle: bundle, usesFahrenheit: usesFahrenheit),
            uvSentence(bundle: bundle, now: now, timezone: tz),
            windSentence(bundle: bundle, now: now),
            muggySentence(bundle: bundle, usesFahrenheit: usesFahrenheit),
            yesterdaySentence(bundle: bundle),
            weekendSentence(bundle: bundle, now: now, timezone: tz),
        ]
        return candidates.compactMap { $0 }.prefix(3).joined(separator: " ")
    }

    // MARK: New-depth sentences

    /// "Snow totals near 3 in by tonight."
    private static func snowSentence(bundle: WeatherBundle, usesFahrenheit: Bool) -> String? {
        guard let snow = bundle.today?.snowfallSum, snow > 0.2 else { return nil }
        let amount = usesFahrenheit
            ? String(format: "%.1f in", snow)
            : String(format: "%.0f cm", snow)
        return "Snow totals near \(amount) by tonight."
    }

    /// "UV runs very high from 11 AM to 3 PM."
    private static func uvSentence(bundle: WeatherBundle, now: Date, timezone: TimeZone) -> String? {
        let strong = bundle.hourly.filter {
            Fmt.isToday($0.date, timezone: timezone) && $0.uvIndex >= 8
        }
        guard let first = strong.first, let last = strong.last,
              last.date > now else { return nil }
        return "UV runs very high from \(Fmt.hour(first.date, timezone: timezone)) to \(Fmt.hour(last.date, timezone: timezone))."
    }

    /// "Muggy tonight — dew point near 70°."
    private static func muggySentence(bundle: WeatherBundle, usesFahrenheit: Bool) -> String? {
        guard let dew = bundle.current.dewPoint else { return nil }
        let threshold: Double = usesFahrenheit ? 67 : 19.5
        guard dew >= threshold else { return nil }
        return "Muggy out, dew point near \(Fmt.tempDegree(dew))."
    }

    /// Friday's look ahead: "Saturday is the better half of the weekend."
    private static func weekendSentence(bundle: WeatherBundle, now: Date, timezone: TimeZone) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let weekday = cal.component(.weekday, from: now)
        guard weekday == 5 || weekday == 6 else { return nil }   // Thu or Fri

        let weekend = bundle.daily.filter {
            let d = cal.component(.weekday, from: $0.date)
            return (d == 7 || d == 1) && $0.date > now            // Sat/Sun ahead
        }
        guard weekend.count >= 2 else { return nil }
        let saturday = weekend[0], sunday = weekend[1]
        // "Better" = meaningfully drier; temperature breaks a tie.
        let rainGap = saturday.precipitationProbabilityMax - sunday.precipitationProbabilityMax
        if abs(rainGap) >= 25 {
            let (nicer, wetter) = rainGap < 0 ? (saturday, sunday) : (sunday, saturday)
            return "\(Fmt.fullWeekday(nicer.date, timezone: timezone)) is the better half of the weekend, with \(Fmt.percent(wetter.precipitationProbabilityMax)) rain odds \(wetter.date == saturday.date ? "Saturday" : "Sunday")."
        }
        if max(saturday.precipitationProbabilityMax, sunday.precipitationProbabilityMax) < 30 {
            return "The weekend looks dry on both sides."
        }
        return nil
    }

    // The day's arc: current sky, where it's heading, and rain timing.
    private static func skySentence(bundle: WeatherBundle,
                                    nowcast: RainNowcast?,
                                    now: Date,
                                    timezone: TimeZone) -> String? {
        let condition = bundle.current.condition
        let opening = openingPhrase(for: condition)

        // Imminent rain outranks the hourly outlook.
        if let nowcast {
            switch nowcast.phase {
            case .starting(let start):
                return "\(opening), with rain arriving around \(Fmt.time(start, timezone: timezone))."
            case .startingAndEnding(let start, let end):
                return "\(opening); a spell of rain runs from about \(Fmt.time(start, timezone: timezone)) to \(Fmt.time(end, timezone: timezone))."
            case .easing(let end):
                return "\(opening), easing around \(Fmt.time(end, timezone: timezone))."
            case .persisting:
                return "\(opening), and it stays wet through the next few hours."
            }
        }

        // Otherwise: the first likely-rain hour left today, if any.
        let todays = bundle.hourly.filter {
            Fmt.isToday($0.date, timezone: timezone) && $0.date > now
        }
        if let firstRain = todays.first(where: { $0.precipitationProbability >= 55 }) {
            return "\(opening); rain becomes likely near \(Fmt.hour(firstRain.date, timezone: timezone))."
        }
        if let peak = todays.map(\.precipitationProbability).max(), peak >= 35 {
            return "\(opening), with a passing chance of rain later."
        }
        // A dry day: mention the high only while the peak is genuinely still
        // ahead — the warmest *remaining* hour must actually reach it, or an
        // evening brief claims 84° is coming at 10 PM.
        if let today = bundle.today,
           bundle.current.temperature < today.tempMax - 2,
           let peakHour = todays.max(by: { $0.temperature < $1.temperature }),
           peakHour.temperature >= today.tempMax - 1 {
            return "\(opening), heading for \(Fmt.tempDegree(today.tempMax)) by \(Fmt.hour(peakHour.date, timezone: timezone))."
        }
        return "\(opening) through the rest of the day."
    }

    private static func openingPhrase(for condition: WeatherCondition) -> String {
        let base: String
        switch condition.kind {
        case .clear:            base = condition.isDay ? "Clear and bright" : "A clear night"
        case .mainlyClear:      base = condition.isDay ? "Mostly clear" : "A mostly clear night"
        case .partlyCloudy:     base = "Sun through drifting cloud"
        case .overcast:         base = "A gray, covered sky"
        case .fog:              base = "Low fog for now"
        case .drizzle:          base = "A fine drizzle"
        case .rain, .showers:   base = "Rain over the city"
        case .freezingRain:     base = "Freezing rain, take care"
        case .snow, .snowGrains, .snowShowers: base = "Snow falling"
        case .thunderstorm, .thunderstormHail: base = "Thunderstorms nearby"
        case .unknown:          base = "A quiet sky"
        }
        return base
    }

    private static func windSentence(bundle: WeatherBundle, now: Date) -> String? {
        // Only when wind is actually a character in today's story.
        let gust = bundle.current.windGust
        let speed = bundle.current.windSpeed
        guard let today = bundle.today else { return nil }
        if gust >= max(2 * speed, 25), gust >= 25 {
            return "Gusts to \(Fmt.speed(gust)) out of the \(compassPhrase(bundle.current.windDirection))."
        }
        if today.windSpeedMax >= 20, speed < today.windSpeedMax * 0.6 {
            return "Wind builds from the \(compassPhrase(today.windDirectionDominant)) later."
        }
        return nil
    }

    private static func yesterdaySentence(bundle: WeatherBundle) -> String? {
        guard let yesterday = bundle.yesterday else { return nil }
        // Prefer the like-for-like hour; fall back to highs.
        if let then = yesterday.sameHourTemperature {
            let delta = Int((bundle.current.temperature - then).rounded())
            guard abs(delta) >= 2 else {
                return "About the same as this time yesterday."
            }
            return "\(degreeWord(abs(delta))) \(delta > 0 ? "warmer" : "cooler") than this time yesterday."
        }
        let delta = Int(((bundle.today?.tempMax ?? bundle.current.temperature) - yesterday.high).rounded())
        guard abs(delta) >= 3 else { return nil }
        return "\(degreeWord(abs(delta))) \(delta > 0 ? "warmer" : "cooler") than yesterday at its peak."
    }

    /// "Four degrees", "Eleven degrees", "15 degrees" — words while they read
    /// gracefully, numerals once they stop.
    private static func degreeWord(_ n: Int) -> String {
        let words = [1: "One", 2: "Two", 3: "Three", 4: "Four", 5: "Five",
                     6: "Six", 7: "Seven", 8: "Eight", 9: "Nine", 10: "Ten",
                     11: "Eleven", 12: "Twelve"]
        let lead = words[n] ?? String(n)
        return "\(lead) degree\(n == 1 ? "" : "s")"
    }

    private static func compassPhrase(_ degrees: Double) -> String {
        switch Fmt.windDirectionLabel(degrees) {
        case "N", "NNE", "NNW": "north"
        case "NE", "ENE": "northeast"
        case "E", "ESE": "east"
        case "SE", "SSE": "southeast"
        case "S", "SSW": "south"
        case "SW", "WSW": "southwest"
        case "W", "WNW": "west"
        default: "northwest"
        }
    }
}
