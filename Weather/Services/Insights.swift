//
//  Insights.swift
//  Weather
//
//  Composed, human sentences derived from the forecast: the nowcast line
//  ("Rain starting around 3:40") and the daily brief, the app's editorial
//  voice doing actual work. Pure functions over the bundle; no networking,
//  no AI, just careful templating.
//
//  Every sentence is written in both registers (see `Voice`). Which facts
//  appear, in what order, and under what thresholds is identical either way;
//  only the wording moves.
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
    func sentence(timezone: TimeZone, voice: Voice = .editorial) -> String {
        switch phase {
        case .starting(let start):
            let at = Fmt.time(start, timezone: timezone)
            return voice.pick("Rain starting around \(at)",
                              whimsy: "Rain turning up around \(at)")
        case .startingAndEnding(let start, let end):
            let from = Fmt.time(start, timezone: timezone)
            let to = Fmt.time(end, timezone: timezone)
            return voice.pick("Rain from about \(from) to \(to)",
                              whimsy: "Rain dropping by from about \(from) to \(to)")
        case .easing(let end):
            let at = Fmt.time(end, timezone: timezone)
            return voice.pick("Rain easing around \(at)",
                              whimsy: "Rain letting up around \(at)")
        case .persisting:
            return voice.pick("Rain continuing for the next few hours",
                              whimsy: "Rain settling in for a few hours")
        }
    }

    /// `wetThreshold` is in the bundle's own precipitation unit: a trace in
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

/// Two or three composed sentences describing the day ahead, the magazine's
/// standfirst. Restraint is the design: each sentence earns its place or is
/// dropped. Whimsy mode warms the wording, never the restraint.
enum DailyBrief {
    /// `usesFahrenheit` picks the dew-point comfort threshold and snow-unit
    /// label; the bundle's numbers arrive in the user's own units.
    static func compose(bundle: WeatherBundle,
                        nowcast: RainNowcast?,
                        usesFahrenheit: Bool = true,
                        voice: Voice = .editorial,
                        now: Date = Date()) -> String {
        let tz = bundle.timezone

        // Candidates in priority order; the brief takes the first three that
        // apply. Restraint is the design: a standfirst, not a bulletin.
        let candidates: [String?] = [
            skySentence(bundle: bundle, nowcast: nowcast, now: now, timezone: tz, voice: voice),
            snowSentence(bundle: bundle, usesFahrenheit: usesFahrenheit, voice: voice),
            uvSentence(bundle: bundle, now: now, timezone: tz, voice: voice),
            windSentence(bundle: bundle, now: now, voice: voice),
            muggySentence(bundle: bundle, usesFahrenheit: usesFahrenheit, voice: voice),
            yesterdaySentence(bundle: bundle, voice: voice),
            weekendSentence(bundle: bundle, now: now, timezone: tz, voice: voice),
        ]
        return candidates.compactMap { $0 }.prefix(3).joined(separator: " ")
    }

    // MARK: New-depth sentences

    /// "Snow totals near 3 in by tonight."
    private static func snowSentence(bundle: WeatherBundle, usesFahrenheit: Bool,
                                     voice: Voice) -> String? {
        guard let snow = bundle.today?.snowfallSum, snow > 0.2 else { return nil }
        let amount = usesFahrenheit
            ? String(format: "%.1f in", snow)
            : String(format: "%.0f cm", snow)
        return voice.pick("Snow totals near \(amount) by tonight.",
                          whimsy: "About \(amount) of snow piling up by tonight.")
    }

    /// "UV runs very high from 11 AM to 3 PM."
    private static func uvSentence(bundle: WeatherBundle, now: Date, timezone: TimeZone,
                                   voice: Voice) -> String? {
        let strong = bundle.hourly.filter {
            Fmt.isToday($0.date, timezone: timezone) && $0.uvIndex >= 8
        }
        guard let first = strong.first, let last = strong.last,
              last.date > now else { return nil }
        let from = Fmt.hour(first.date, timezone: timezone)
        let to = Fmt.hour(last.date, timezone: timezone)
        return voice.pick("UV runs very high from \(from) to \(to).",
                          whimsy: "The sun is out in force from \(from) to \(to), so find some shade.")
    }

    /// "Muggy out, dew point near 70°."
    private static func muggySentence(bundle: WeatherBundle, usesFahrenheit: Bool,
                                      voice: Voice) -> String? {
        guard let dew = bundle.current.dewPoint else { return nil }
        let threshold: Double = usesFahrenheit ? 67 : 19.5
        guard dew >= threshold else { return nil }
        return voice.pick("Muggy out, dew point near \(Fmt.tempDegree(dew)).",
                          whimsy: "Soupy air out there, dew point near \(Fmt.tempDegree(dew)).")
    }

    /// Friday's look ahead: "Saturday is the better half of the weekend."
    private static func weekendSentence(bundle: WeatherBundle, now: Date, timezone: TimeZone,
                                        voice: Voice) -> String? {
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
            let good = Fmt.fullWeekday(nicer.date, timezone: timezone)
            let odds = Fmt.percent(wetter.precipitationProbabilityMax)
            let bad = wetter.date == saturday.date ? "Saturday" : "Sunday"
            return voice.pick("\(good) is the better half of the weekend, with \(odds) rain odds \(bad).",
                              whimsy: "\(good) is the friendlier half of the weekend, with \(odds) rain odds \(bad).")
        }
        if max(saturday.precipitationProbabilityMax, sunday.precipitationProbabilityMax) < 30 {
            return voice.pick("The weekend looks dry on both sides.",
                              whimsy: "Both halves of the weekend look dry, so go make plans.")
        }
        return nil
    }

    // The day's arc: current sky, where it's heading, and rain timing.
    private static func skySentence(bundle: WeatherBundle,
                                    nowcast: RainNowcast?,
                                    now: Date,
                                    timezone: TimeZone,
                                    voice: Voice) -> String? {
        let condition = bundle.current.condition
        let opening = openingPhrase(for: condition, voice: voice)

        // Imminent rain outranks the hourly outlook.
        if let nowcast {
            switch nowcast.phase {
            case .starting(let start):
                let at = Fmt.time(start, timezone: timezone)
                return voice.pick("\(opening), with rain arriving around \(at).",
                                  whimsy: "\(opening), and rain turns up around \(at).")
            case .startingAndEnding(let start, let end):
                let from = Fmt.time(start, timezone: timezone)
                let to = Fmt.time(end, timezone: timezone)
                return voice.pick("\(opening); a spell of rain runs from about \(from) to \(to).",
                                  whimsy: "\(opening), then rain drops by from about \(from) to \(to).")
            case .easing(let end):
                let at = Fmt.time(end, timezone: timezone)
                return voice.pick("\(opening), easing around \(at).",
                                  whimsy: "\(opening), letting up around \(at).")
            case .persisting:
                return voice.pick("\(opening), and it stays wet through the next few hours.",
                                  whimsy: "\(opening), and the rain is in no hurry to leave.")
            }
        }

        // Otherwise: the first likely-rain hour left today, if any.
        let todays = bundle.hourly.filter {
            Fmt.isToday($0.date, timezone: timezone) && $0.date > now
        }
        if let firstRain = todays.first(where: { $0.precipitationProbability >= 55 }) {
            let near = Fmt.hour(firstRain.date, timezone: timezone)
            return voice.pick("\(opening); rain becomes likely near \(near).",
                              whimsy: "\(opening), and rain looks likely to wander in near \(near).")
        }
        if let peak = todays.map(\.precipitationProbability).max(), peak >= 35 {
            return voice.pick("\(opening), with a passing chance of rain later.",
                              whimsy: "\(opening), with a stray shower wandering through later.")
        }
        // A dry day: mention the high only while the peak is genuinely still
        // ahead. The warmest *remaining* hour must actually reach it, or an
        // evening brief claims 84° is coming at 10 PM.
        if let today = bundle.today,
           bundle.current.temperature < today.tempMax - 2,
           let peakHour = todays.max(by: { $0.temperature < $1.temperature }),
           peakHour.temperature >= today.tempMax - 1 {
            let high = Fmt.tempDegree(today.tempMax)
            let by = Fmt.hour(peakHour.date, timezone: timezone)
            return voice.pick("\(opening), heading for \(high) by \(by).",
                              whimsy: "\(opening), working up to \(high) by \(by).")
        }
        return voice.pick("\(opening) through the rest of the day.",
                          whimsy: "\(opening), and that's the whole plan for the day.")
    }

    private static func openingPhrase(for condition: WeatherCondition, voice: Voice) -> String {
        switch condition.kind {
        case .clear:
            return condition.isDay
                ? voice.pick("Clear and bright", whimsy: "Blue all the way up")
                : voice.pick("A clear night", whimsy: "A sky full of stars")
        case .mainlyClear:
            return condition.isDay
                ? voice.pick("Mostly clear", whimsy: "Blue, with a stray cloud or two")
                : voice.pick("A mostly clear night", whimsy: "A clear night, one or two clouds out late")
        case .partlyCloudy:
            return voice.pick("Sun through drifting cloud",
                              whimsy: "Clouds wandering past the sun")
        case .overcast:
            return voice.pick("A gray, covered sky",
                              whimsy: "A gray blanket over everything")
        case .fog:
            return voice.pick("Low fog for now", whimsy: "Fog keeping the view to itself")
        case .drizzle:
            return voice.pick("A fine drizzle", whimsy: "A shy little drizzle")
        case .rain, .showers:
            return voice.pick("Rain over the city", whimsy: "Rain drumming on everything")
        case .freezingRain:
            return voice.pick("Freezing rain, take care",
                              whimsy: "Freezing rain, so mind your step")
        case .snow, .snowGrains, .snowShowers:
            return voice.pick("Snow falling", whimsy: "Snow taking its time")
        case .thunderstorm, .thunderstormHail:
            return voice.pick("Thunderstorms nearby", whimsy: "Thunder grumbling nearby")
        case .unknown:
            return voice.pick("A quiet sky", whimsy: "A sky keeping its secrets")
        }
    }

    private static func windSentence(bundle: WeatherBundle, now: Date, voice: Voice) -> String? {
        // Only when wind is actually a character in today's story.
        let gust = bundle.current.windGust
        let speed = bundle.current.windSpeed
        guard let today = bundle.today else { return nil }
        if gust >= max(2 * speed, 25), gust >= 25 {
            let from = compassPhrase(bundle.current.windDirection)
            return voice.pick("Gusts to \(Fmt.speed(gust)) out of the \(from).",
                              whimsy: "Gusts to \(Fmt.speed(gust)) out of the \(from), enough to rearrange your hair.")
        }
        if today.windSpeedMax >= 20, speed < today.windSpeedMax * 0.6 {
            let from = compassPhrase(today.windDirectionDominant)
            return voice.pick("Wind builds from the \(from) later.",
                              whimsy: "The wind finds its feet from the \(from) later.")
        }
        return nil
    }

    private static func yesterdaySentence(bundle: WeatherBundle, voice: Voice) -> String? {
        guard let yesterday = bundle.yesterday else { return nil }
        // Prefer the like-for-like hour; fall back to highs.
        if let then = yesterday.sameHourTemperature {
            let delta = Int((bundle.current.temperature - then).rounded())
            guard abs(delta) >= 2 else {
                return voice.pick("About the same as this time yesterday.",
                                  whimsy: "Yesterday all over again.")
            }
            let gap = "\(degreeWord(abs(delta))) \(delta > 0 ? "warmer" : "cooler")"
            return voice.pick("\(gap) than this time yesterday.",
                              whimsy: "\(gap) than yesterday managed at this hour.")
        }
        let delta = Int(((bundle.today?.tempMax ?? bundle.current.temperature) - yesterday.high).rounded())
        guard abs(delta) >= 3 else { return nil }
        let gap = "\(degreeWord(abs(delta))) \(delta > 0 ? "warmer" : "cooler")"
        return voice.pick("\(gap) than yesterday at its peak.",
                          whimsy: "\(gap) than yesterday's best effort.")
    }

    /// "Four degrees", "Eleven degrees", "15 degrees": words while they read
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
