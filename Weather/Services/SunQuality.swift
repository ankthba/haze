//
//  SunQuality.swift
//  Weather
//
//  Predicts how good a sunrise or sunset will look, from the forecast the app
//  already holds — no extra network. The physics in brief: high and mid clouds
//  are the canvas the low sun paints from below; low clouds are a wall between
//  you and the horizon; haze mutes the palette; rain usually means no show.
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

        var tier: Tier { Tier(score: score) }
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
        var blurb: String {
            switch self {
            case .poor:        return "Cloud or rain will likely smother the color."
            case .fair:        return "A quiet sky — soft light, little drama."
            case .good:        return "Some color is likely along the horizon."
            case .great:       return "Clouds are set up to catch real color."
            case .spectacular: return "A painted sky is on the cards — go look."
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

        // — Canvas: high cloud lights up best, mid cloud counts for half.
        //   The sweet spot is a broken deck (~30–60%); clear is pleasant but
        //   plain, and a solid sheet goes gray.
        let deck = min(high + mid * 0.5, 100)
        let canvas = ramp(deck, points: [(0, 45), (15, 70), (30, 100), (60, 100),
                                         (80, 40), (100, 22)])

        // — Horizon: low cloud stands between you and the light. A few
        //   fair-weather clouds are harmless; a closed deck ends the show.
        let horizon = ramp(low, points: [(0, 100), (15, 100), (40, 55), (70, 18), (100, 8)])

        // — Clarity: how clean the light's path is. Visibility where the model
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

        // — Rain: a steepening drag, then a hard veto below.
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
                      cloudHigh: high, cloudMid: mid, cloudLow: low)
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
