//
//  SunQuality.swift
//  Weather
//
//  Predicts how good a sunrise or sunset will look, from the forecast the app
//  already holds, with no extra network. The physics in brief: high and mid
//  clouds are the canvas the low sun paints from below; low clouds are a wall
//  between you and the horizon; haze mutes the palette; rain means no show.
//
//  Scores are 0–100 and deliberately opinionated: a clear sky earns a middling
//  score (pleasant, but nothing to catch fire), a broken deck of high cloud
//  over a clean horizon earns the top of the scale.
//

import Foundation

// MARK: - One rated event

nonisolated struct SunEvent: Identifiable {
    enum Kind: String {
        case sunrise = "Sunrise"
        case sunset = "Sunset"

        var symbolName: String {
            self == .sunrise ? "sunrise.fill" : "sunset.fill"
        }
    }

    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    let kind: Kind
    let date: Date
    /// nil when the forecast hours around the event carry no layered cloud
    /// data (a cached bundle from before the field existed, or the far end of
    /// the window).
    let rating: SunQuality.Rating?
}

// MARK: - The model

nonisolated enum SunQuality {

    struct Rating {
        /// 0–100.
        let score: Int
        /// The ingredients, each 0–100, for the breakdown UI.
        let canvas: Int      // high/mid cloud in the sweet spot
        let horizon: Int     // freedom from low cloud
        let clarity: Int     // visibility + dryness of the air
        let rainRisk: Int    // precipitation probability, as sampled
        /// Sampled inputs, kept for display.
        let cloudHigh: Double
        let cloudMid: Double
        let cloudLow: Double
        let humidity: Double
        /// Metres, when the model provides it.
        let visibility: Double?

        var tier: Tier { Tier(score: score) }

        /// Two or three words naming the sky's defining feature, the reason
        /// behind the score, for list rows. Checked worst-news-first.
        func signature(_ voice: Voice = .editorial) -> String {
            let deck = min(cloudHigh + cloudMid * 0.5, 100)
            if rainRisk >= 50 { return voice.pick("rain likely", whimsy: "rain has other plans") }
            if cloudLow >= 60 { return voice.pick("walled horizon", whimsy: "clouds in the doorway") }
            if deck > 78 { return voice.pick("heavy sheet", whimsy: "one big gray lid") }
            if clarity < 55 { return voice.pick("hazy air", whimsy: "a hazy hush") }
            if deck < 12 { return voice.pick("bare sky", whimsy: "nothing to light up") }
            if canvas >= 80 { return voice.pick("well-set clouds", whimsy: "clouds set just so") }
            return voice.pick("mixed sky", whimsy: "a little of everything")
        }
    }

    enum Tier: String {
        case poor = "Poor"
        case fair = "Fair"
        case good = "Good"
        case great = "Great"
        case spectacular = "Spectacular"

        init(score: Int) {
            switch score {
            case ..<25: self = .poor
            case ..<45: self = .fair
            case ..<65: self = .good
            case ..<85: self = .great
            default:    self = .spectacular
            }
        }

        /// One line of expectation-setting under the score.
        func blurb(_ voice: Voice = .editorial) -> String {
            switch self {
            case .poor:
                return voice.pick("Cloud or rain will likely smother the color.",
                                  whimsy: "Cloud and rain are keeping this one to themselves.")
            case .fair:
                return voice.pick("A quiet sky, soft light, little drama.",
                                  whimsy: "A soft, quiet sky. Pretty, in a small way.")
            case .good:
                return voice.pick("Some color is likely along the horizon.",
                                  whimsy: "A little color should turn up along the horizon.")
            case .great:
                return voice.pick("Clouds are set up to catch real color.",
                                  whimsy: "The clouds are lined up and waiting for the light.")
            case .spectacular:
                return voice.pick("A painted sky is on the cards. Go look.",
                                  whimsy: "The sky is going all out. Go and see.")
            }
        }
    }

    /// The bar an event must clear before its alert fires. Stored by raw
    /// value; scores line up with the Tier boundaries.
    enum AlertGate: String, CaseIterable, Identifiable {
        case any, good, great

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any:   return "Every day"
            case .good:  return "Good or better"
            case .great: return "Great or better"
            }
        }

        var minScore: Int {
            switch self {
            case .any:   return 0
            case .good:  return 45
            case .great: return 65
            }
        }
    }

    // MARK: Event list

    /// Every sunrise and sunset in the bundle's daily window, rated where the
    /// hourly forecast can support it, past events dropped. Chronological.
    static func upcomingEvents(in bundle: WeatherBundle, now: Date = Date()) -> [SunEvent] {
        var events: [SunEvent] = []
        for day in bundle.daily {
            if let sunrise = day.sunrise, sunrise > now {
                events.append(SunEvent(kind: .sunrise, date: sunrise,
                                       rating: rate(kind: .sunrise, at: sunrise, in: bundle)))
            }
            if let sunset = day.sunset, sunset > now {
                events.append(SunEvent(kind: .sunset, date: sunset,
                                       rating: rate(kind: .sunset, at: sunset, in: bundle)))
            }
        }
        return events.sorted { $0.date < $1.date }
    }

    // MARK: Scoring

    /// Rates one event from the hourly forecast around it.
    static func rate(kind: SunEvent.Kind, at date: Date, in bundle: WeatherBundle) -> Rating? {
        // The color show lives in the half-light: the hour before a sunrise
        // and the hour after a sunset matter as much as the moment itself.
        // Sample the surrounding hours, weighted toward the event.
        let window: TimeInterval = 90 * 60
        let nearby = bundle.hourly.filter { abs($0.date.timeIntervalSince(date)) <= window }
        guard !nearby.isEmpty else { return nil }

        func weighted(_ value: (HourPoint) -> Double?) -> Double? {
            var total = 0.0, weightSum = 0.0
            for hour in nearby {
                guard let v = value(hour) else { continue }
                let hoursAway = abs(hour.date.timeIntervalSince(date)) / 3600
                let w = 1 / (1 + hoursAway)
                total += v * w
                weightSum += w
            }
            return weightSum > 0 ? total / weightSum : nil
        }

        // Layered cloud is the heart of the model; without it there is no
        // honest rating.
        guard let high = weighted({ $0.cloudCoverHigh }),
              let mid = weighted({ $0.cloudCoverMid }),
              let low = weighted({ $0.cloudCoverLow })
        else { return nil }

        let humidity = weighted { $0.humidity } ?? 50
        let precipProb = weighted { $0.precipitationProbability } ?? 0
        let visibility = weighted { $0.visibility }

        // The canvas sets the ceiling; everything else can only take away.
        // Multiplying (rather than adding weighted terms) keeps a clear, dry,
        // rain-free evening from accumulating "free" points into a top score
        // when there is nothing overhead to light up.

        // Canvas: high cloud lights up best, mid cloud counts for half.
        //   The sweet spot is a broken deck (~30–60%); clear is pleasant but
        //   plain, and a solid sheet goes gray.
        let deck = min(high + mid * 0.5, 100)
        let canvas = ramp(deck, points: [(0, 45), (15, 70), (30, 100), (60, 100),
                                         (80, 40), (100, 22)])

        // Horizon: low cloud stands between you and the light. A few
        //   fair-weather clouds are harmless; a closed deck ends the show.
        let horizon = ramp(low, points: [(0, 100), (15, 100), (40, 55), (70, 18), (100, 8)])

        // Clarity: how clean the light's path is. Visibility where the model
        //   provides it, humidity as the haze proxy otherwise; heavy humidity
        //   mutes the palette either way.
        var clarity: Double
        if let visibility {
            clarity = ramp(visibility, points: [(2_000, 40), (10_000, 70),
                                                (25_000, 92), (40_000, 100)])
        } else {
            clarity = ramp(humidity, points: [(30, 100), (60, 88), (85, 62), (100, 45)])
        }
        if humidity > 85 { clarity = min(clarity, 62) }

        // Rain: a steepening drag, then a hard veto below.
        let rain = 100 - precipProb * 0.7

        var score = canvas * (horizon / 100) * (clarity / 100) * (rain / 100)

        // Vetoes: an overcast low deck or probable rain caps the night no
        // matter how promising the layers above look.
        if low >= 80 { score = min(score, 18) }
        if precipProb >= 80 { score = min(score, 25) }

        return Rating(score: Int(score.rounded()),
                      canvas: Int(canvas.rounded()),
                      horizon: Int(horizon.rounded()),
                      clarity: Int(clarity.rounded()),
                      rainRisk: Int(precipProb.rounded()),
                      cloudHigh: high, cloudMid: mid, cloudLow: low,
                      humidity: humidity, visibility: visibility)
    }

    // MARK: - Narrative

    /// Two or three warm sentences about the event, the same editorial voice
    /// as the home screen's daily brief. Verdict first, then timing advice,
    /// then a garnish about the air; each sentence earns its place or is
    /// dropped. Whimsy mode swaps the wording, not the structure.
    static func narrative(kind: SunEvent.Kind,
                          rating: Rating,
                          eventDate: Date,
                          timezone: TimeZone,
                          voice: Voice = .editorial) -> String {
        let deck = min(rating.cloudHigh + rating.cloudMid * 0.5, 100)
        let time = Fmt.time(eventDate, timezone: timezone)
        let sunset = kind == .sunset

        let verdict: String
        switch rating.tier {
        case .spectacular:
            verdict = sunset
                ? voice.pick("The sky is set up for something special this evening, with a broken deck of high cloud ready to catch fire as the sun slips under.",
                             whimsy: "Tonight the sky is going all out, with a broken deck of high cloud waiting to catch fire as the sun slips under.")
                : voice.pick("The sky is set up for something special, with a broken deck of high cloud ready to catch first light and burn.",
                             whimsy: "The sky is going all out, with a broken deck of high cloud waiting to take the first light and glow.")
        case .great:
            verdict = sunset
                ? voice.pick("The clouds are arranged kindly tonight; expect real color climbing off the horizon.",
                             whimsy: "The clouds have lined themselves up beautifully tonight, so expect real color climbing off the horizon.")
                : voice.pick("The clouds are arranged kindly for the morning; expect real color before the sun clears the horizon.",
                             whimsy: "The clouds have lined themselves up beautifully for the morning, so expect real color before the sun clears the horizon.")
        case .good:
            verdict = deck < 15
                ? voice.pick("A clean, quiet sky. Expect a soft amber glow rather than fireworks.",
                             whimsy: "A clean, quiet sky. A soft amber glow, no fireworks.")
                : voice.pick("Some color is likely, with patches of high cloud warming as the light comes in low.",
                             whimsy: "Some color is likely, with patches of high cloud ready to catch the low light.")
        case .fair:
            verdict = rating.cloudLow >= 45
                ? voice.pick("Low cloud sits along the horizon, so most of the show will happen behind it.",
                             whimsy: "Low cloud has settled along the horizon, so most of the show happens behind it.")
                : voice.pick("A muted sky, with little up there for the light to work with.",
                             whimsy: "A gentle, muted sky, with not much up there for the light to play with.")
        case .poor:
            if rating.rainRisk >= 50 {
                verdict = sunset
                    ? voice.pick("Rain is likely around sunset; the light will go quietly.",
                                 whimsy: "Rain is likely around sunset, so the light will slip away quietly.")
                    : voice.pick("Rain is likely around sunrise; the day will arrive quietly.",
                                 whimsy: "Rain is likely around sunrise, so the day will let itself in quietly.")
            } else {
                verdict = sunset
                    ? voice.pick("An overcast lid tonight; the sun will slip away unseen.",
                                 whimsy: "A gray lid tonight, so the sun will slip out the back way.")
                    : voice.pick("An overcast lid this morning; the sun will arrive unseen.",
                                 whimsy: "A gray lid this morning, so the sun will let itself in unseen.")
            }
        }

        var timing: String?
        switch rating.tier {
        case .great, .spectacular:
            timing = sunset
                ? voice.pick("The best of it usually lands ten to twenty minutes after \(time), so stay a while.",
                             whimsy: "The best of it usually lands ten to twenty minutes after \(time), so linger a while.")
                : voice.pick("Worth the early alarm. The color peaks in the minutes before \(time).",
                             whimsy: "Worth the early alarm. The color gathers in the minutes before \(time).")
        case .good:
            timing = sunset
                ? voice.pick("Golden hour runs the hour before \(time).",
                             whimsy: "Golden hour runs the hour before \(time), and it's the good bit.")
                : voice.pick("First light starts warming the sky well before \(time).",
                             whimsy: "The sky starts warming well before \(time), gently at first.")
        case .fair, .poor:
            timing = nil
        }

        var garnish: String?
        if rating.tier != .poor {
            if rating.clarity >= 88 {
                garnish = voice.pick("The air is clean, so whatever color arrives will carry.",
                                     whimsy: "The air is clear, so every bit of color will carry.")
            } else if rating.clarity < 60 {
                garnish = voice.pick("Haze will soften whatever color arrives.",
                                     whimsy: "Haze will soften the color into something gentler.")
            }
        }

        return [verdict, timing, garnish].compactMap { $0 }.joined(separator: " ")
    }

    /// Piecewise-linear interpolation through (input, output) points, clamped
    /// at both ends. Points must be sorted by input.
    private static func ramp(_ x: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<points.count where x <= points[i].0 {
            let (x0, y0) = points[i - 1]
            let (x1, y1) = points[i]
            let t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
        }
        return last.1
    }
}
