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
    /// Opens the sunrise/sunset quality page on the tapped event's side.
    var onSunTap: ((SunEvent.Kind) -> Void)? = nil

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

    /// At home the bar belongs to the sky entirely: the next sunset and the
    /// next sunrise side by side, each with its verdict, each half a door to
    /// its own side of the sun page.
    @ViewBuilder
    private var homeContent: some View {
        let events = nextSunEvents
        if events.isEmpty {
            // No sun times in the forecast (polar edge cases): fall back to
            // naming the place rather than an empty bar.
            HStack(spacing: 14) {
                circleBadge(active: false)
                Text(bundle.place.subtitle.isEmpty ? bundle.place.name : bundle.place.subtitle)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    sunHalf(event)
                    if index == 0, events.count > 1 {
                        Rectangle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 0.6, height: 34)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    /// One event's half of the bar: icon, name with score, and when.
    private func sunHalf(_ event: (kind: SunEvent.Kind, date: Date,
                                   rating: SunQuality.Rating?)) -> some View {
        Button {
            Haptics.tap()
            onSunTap?(event.kind)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: event.kind.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 17))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(event.kind.rawValue)
                            .font(.serif(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                        if let rating = event.rating {
                            Text("\(rating.score)")
                                .font(.serif(.subheadline, weight: .semibold))
                                .foregroundStyle(rating.tier.accent)
                        }
                    }
                    .lineLimit(1)
                    Text("\(whenWord(for: event)) at \(Fmt.time(event.date, timezone: bundle.timezone))")
                        .font(.serif(.caption2, italic: true))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            // Centered in its half so the pair reads as balanced around the
            // divider instead of both clusters hugging their left edges.
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: event))
        .accessibilityHint("Shows sunrise and sunset quality ratings")
    }

    /// "Tonight", "This morning", or "Tomorrow" — the word before "at 7:44".
    private func whenWord(for event: (kind: SunEvent.Kind, date: Date,
                                      rating: SunQuality.Rating?)) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        if cal.isDate(event.date, inSameDayAs: Date()) {
            return event.kind == .sunset ? "Tonight" : "This morning"
        }
        return "Tomorrow"
    }

    private func accessibilityLabel(for event: (kind: SunEvent.Kind, date: Date,
                                                rating: SunQuality.Rating?)) -> String {
        let when = "\(event.kind.rawValue) \(whenWord(for: event).lowercased()) at \(Fmt.time(event.date, timezone: bundle.timezone))"
        if let rating = event.rating {
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

    /// The next sunset and the next sunrise, in arrival order, each rated
    /// where the forecast can support it.
    private var nextSunEvents: [(kind: SunEvent.Kind, date: Date,
                                 rating: SunQuality.Rating?)] {
        let now = Date()
        let upcoming: [(Date, SunEvent.Kind)] = bundle.daily.prefix(2).flatMap { day -> [(Date, SunEvent.Kind)] in
            var events: [(Date, SunEvent.Kind)] = []
            if let sunrise = day.sunrise { events.append((sunrise, .sunrise)) }
            if let sunset = day.sunset { events.append((sunset, .sunset)) }
            return events
        }
        var next: [(kind: SunEvent.Kind, date: Date, rating: SunQuality.Rating?)] = []
        for kind in [SunEvent.Kind.sunset, .sunrise] {
            if let date = upcoming.filter({ $0.1 == kind && $0.0 > now }).map(\.0).min() {
                next.append((kind, date, SunQuality.rate(kind: kind, at: date, in: bundle)))
            }
        }
        return next.sorted { $0.date < $1.date }
    }
}
