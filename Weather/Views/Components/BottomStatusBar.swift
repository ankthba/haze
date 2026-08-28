//
//  BottomStatusBar.swift
//  Weather
//
//  The bar at the foot of the screen, in two states:
//
//   • Away from home — your own location's weather, and a circle that takes
//     you back to it. The whole bar is the way home.
//   • At home — the next thing the sky is going to do (sunset, or sunrise
//     overnight) alongside today's range. Both are things people check
//     constantly and neither sits near the top of the feed.
//
//  Its corners are measured from the device's own display radius so the bar
//  nests inside the screen's curve — tight on an 11 Pro, round on a 16 Pro.
//

import SwiftUI

struct BottomStatusBar: View {
    let bundle: WeatherBundle
    /// Home's weather — present only while browsing somewhere else, which is
    /// also the only time returning home means anything.
    let homeSummary: WeatherViewModel.DeviceSummary?
    var onReturnHome: () -> Void
    /// Opens the sunrise/sunset quality page; the sun readout is the door.
    var onSunTap: (() -> Void)? = nil

    /// Inset from the screen's side edges; the corner radius is measured from it.
    static let inset: CGFloat = 16
    /// A little more room underneath than at the sides — the bar is tall
    /// enough that hugging the very bottom edge reads as cramped.
    static let bottomGap: CGFloat = 20

    private static let height: CGFloat = 76
    private static let circle: CGFloat = 52

    private var isAwayFromHome: Bool { homeSummary != nil }

    private var shape: RoundedRectangle {
        // Clamped to the bar's own half-height: a radius larger than that
        // would silently render as a capsule instead of the device's curve.
        let radius = min(DeviceScreen.concentricRadius(inset: Self.inset), Self.height / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        Group {
            if let homeSummary {
                Button {
                    Haptics.tap()
                    onReturnHome()
                } label: {
                    awayContent(homeSummary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(homeSummary.place.name), \(Fmt.tempDegree(homeSummary.temperature)), \(homeSummary.condition.description)")
            } else {
                homeContent
            }
        }
        .frame(height: Self.height)
        .background(GlassSurface(shape: shape, blurRadius: 16))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }

    // MARK: - Away: the way home

    private func awayContent(_ summary: WeatherViewModel.DeviceSummary) -> some View {
        HStack(spacing: 14) {
            circleBadge(active: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.place.name)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Back to your location")
                    .font(.serif(.caption2, italic: true))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: summary.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))

            Text(Fmt.tempDegree(summary.temperature))
                .font(.serif(.title3))
                .foregroundStyle(.white)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .contentShape(shape)
    }

    // MARK: - Home: what the sky does next

    /// At home the bar belongs to the sky entirely — the next sun event, its
    /// verdict, and its score. "Your location" and the arrow are the away
    /// state's furniture; here the whole bar is the door to the sun page.
    private var homeContent: some View {
        Button {
            Haptics.tap()
            onSunTap?()
        } label: {
            HStack(spacing: 14) {
                if let sun = nextSunEvent {
                    sunBadge(symbol: sun.kind.symbolName)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sun.kind.rawValue)
                            .font(.serif(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(whenWord(for: sun)) at \(Fmt.time(sun.date, timezone: bundle.timezone))")
                            .font(.serif(.caption2, italic: true))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let rating = sun.rating {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(rating.score)")
                                .font(.serif(.title3))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                            Text(rating.tier.rawValue)
                                .font(.serif(.caption2, italic: true))
                                .foregroundStyle(rating.tier.accent)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                } else {
                    // No sun times in the forecast (polar edge cases): fall
                    // back to naming the place rather than an empty bar.
                    circleBadge(active: false)
                    Text(bundle.place.subtitle.isEmpty ? bundle.place.name : bundle.place.subtitle)
                        .font(.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(homeAccessibilityLabel)
        .accessibilityHint("Shows sunrise and sunset quality ratings")
    }

    /// The sun's own circle, standing where the location arrow stands when
    /// the bar is the way home.
    private func sunBadge(symbol: String) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 19))
            .frame(width: Self.circle, height: Self.circle)
            .background(GlassSurface(shape: Circle()))
            .clipShape(Circle())
    }

    /// "Tonight", "This morning", or "Tomorrow" — the word before "at 7:44".
    private func whenWord(for sun: (kind: SunEvent.Kind, date: Date, rating: SunQuality.Rating?)) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        if cal.isDate(sun.date, inSameDayAs: Date()) {
            return sun.kind == .sunset ? "Tonight" : "This morning"
        }
        return "Tomorrow"
    }

    private var homeAccessibilityLabel: String {
        guard let sun = nextSunEvent else {
            return bundle.place.subtitle.isEmpty ? bundle.place.name : bundle.place.subtitle
        }
        let when = "\(sun.kind.rawValue) \(whenWord(for: sun).lowercased()) at \(Fmt.time(sun.date, timezone: bundle.timezone))"
        if let rating = sun.rating {
            return "\(when), rated \(rating.score) out of 100, \(rating.tier.rawValue)"
        }
        return when
    }

    private func circleBadge(active: Bool) -> some View {
        Image(systemName: "location.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.circle, height: Self.circle)
            .background(GlassSurface(shape: Circle()))
            .clipShape(Circle())
            .opacity(active ? 1 : 0.55)
    }

    /// Sunset while the sun is still up, sunrise once it's down — whichever is
    /// genuinely next, including tomorrow's sunrise late at night. Carries the
    /// event's quality rating when the forecast can support one.
    private var nextSunEvent: (kind: SunEvent.Kind, date: Date,
                               rating: SunQuality.Rating?)? {
        let now = Date()
        let upcoming: [(Date, SunEvent.Kind)] = bundle.daily.prefix(2).flatMap { day -> [(Date, SunEvent.Kind)] in
            var events: [(Date, SunEvent.Kind)] = []
            if let sunrise = day.sunrise { events.append((sunrise, .sunrise)) }
            if let sunset = day.sunset { events.append((sunset, .sunset)) }
            return events
        }
        guard let next = upcoming
            .filter({ $0.0 > now })
            .min(by: { $0.0 < $1.0 })
        else { return nil }
        let rating = SunQuality.rate(kind: next.1, at: next.0, in: bundle)
        return (next.1, next.0, rating)
    }
}
