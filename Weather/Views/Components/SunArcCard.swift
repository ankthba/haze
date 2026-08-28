//
//  SunArcCard.swift
//  Weather
//
//  Sunrise/sunset arc with the sun's current progress along the daylight path.
//  The sun marker is draggable: scrub it along the arc to preview the light and
//  time at any point in the day. Releasing reverts to the live moment.
//

import SwiftUI

struct SunArcCard: View {
    let sunrise: Date?
    let sunset: Date?
    let now: Date
    let timezone: TimeZone

    /// When non-nil, the user is scrubbing the sun: this overrides the marker
    /// position, the wash colouring, the glow, and the headline time/label.
    @State private var scrubProgress: Double?
    /// The stage label captured at the last haptic tick, so we only buzz on change.
    @State private var lastStage: String?

    /// The celestial window we animate along: the daylight arc when the sun is
    /// up, otherwise the night arc (this evening's sunset → tomorrow's sunrise, or
    /// yesterday's sunset → this morning's sunrise). Night length is approximated
    /// with a 24h day since we only hold today's sun times.
    private var window: (start: Date, end: Date)? {
        guard let sunrise, let sunset, sunset > sunrise else { return nil }
        if now < sunrise {
            return (sunset.addingTimeInterval(-86_400), sunrise)
        } else if now > sunset {
            return (sunset, sunrise.addingTimeInterval(86_400))
        } else {
            return (sunrise, sunset)
        }
    }

    private var liveProgress: Double {
        guard let window else { return 0 }
        let total = window.end.timeIntervalSince(window.start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(window.start) / total, 0), 1)
    }

    private var isDaylight: Bool {
        guard let sunrise, let sunset else { return true }
        return now >= sunrise && now <= sunset
    }

    private var phase: DayPhase {
        DayPhase.current(now: now, sunrise: sunrise, sunset: sunset, isDay: isDaylight)
    }

    /// Dragging is only meaningful when we can map progress → time.
    private var canScrub: Bool { sunrise != nil && sunset != nil }

    /// The time at a given arc progress, across whichever window is active.
    private func time(at progress: Double) -> Date? {
        guard let window else { return nil }
        return window.start.addingTimeInterval(progress * window.end.timeIntervalSince(window.start))
    }

    /// Stage label for a scrubbed position — day phases by day, dusk/night/dawn
    /// across the night arc.
    private func scrubStageLabel(_ progress: Double) -> String {
        if isDaylight { return stageLabel(scrubPhase(progress)) }
        if progress < 0.12 { return "Dusk" }
        if progress > 0.88 { return "Dawn" }
        return "Night"
    }

    /// The headline time shown when not scrubbing: the next sun event.
    private var headlineTime: String {
        let date = isDaylight ? sunset : (window?.end ?? sunrise)
        return date.map { Fmt.time($0, timezone: timezone) } ?? "—"
    }

    /// The phase at the scrubbed position (treated as daytime along the arc).
    private func scrubPhase(_ progress: Double) -> DayPhase {
        guard let t = time(at: progress) else { return phase }
        return DayPhase.current(now: t, sunrise: sunrise, sunset: sunset, isDay: true)
    }

    /// Human-readable sun stage for a phase, e.g. "Sunrise · Golden Hour".
    private func stageLabel(_ phase: DayPhase) -> String {
        switch phase {
        case .dawn:  return "Sunrise · Golden Hour"
        case .day:   return "Daytime"
        case .dusk:  return "Sunset · Golden Hour"
        case .night: return "Night"
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let p = scrubProgress {
                    CardLabel(systemImage: isDaylight ? "sun.max" : "moon.stars",
                              title: scrubStageLabel(p))

                    Text(time(at: p).map { Fmt.time($0, timezone: timezone) } ?? "—")
                        .font(.serif(.title))
                        .foregroundStyle(.white)
                } else {
                    CardLabel(systemImage: isDaylight ? "sun.max" : "moon.stars",
                              title: isDaylight ? "Sunset" : "Sunrise")

                    Text(headlineTime)
                        .font(.serif(.title))
                        .foregroundStyle(.white)
                }

                ArcView(progress: scrubProgress ?? liveProgress,
                        isDaylight: isDaylight,
                        phase: phase,
                        isScrubbing: scrubProgress != nil,
                        canScrub: canScrub,
                        onScrub: handleScrub,
                        onEnd: endScrub)
                    .frame(height: 56)

                HStack {
                    label("Sunrise", sunrise)
                    Spacer()
                    label("Sunset", sunset)
                }

                // The sky's small print: tonight's moon and the golden hour.
                Divider().overlay(Color.white.opacity(0.12))

                HStack(alignment: .top) {
                    moonLabel
                    Spacer()
                    goldenHourLabel
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: scrubProgress != nil)
    }

    private var moonLabel: some View {
        let moon = MoonPhase.current()
        return HStack(spacing: 8) {
            Image(systemName: moon.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) {
                Text(moon.name)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(Int((moon.illumination * 100).rounded()))% lit")
                    .font(.serif(.caption2))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(moon.name), \(Int((moon.illumination * 100).rounded())) percent illuminated")
    }

    @ViewBuilder
    private var goldenHourLabel: some View {
        // Only while the window is still ahead or under way — an elapsed
        // golden hour shown at midnight reads as a mistake.
        if let window = GoldenHour.evening(sunset: sunset),
           window.upperBound > Date() {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Golden hour")
                    .font(.serif(.caption2))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(Fmt.time(window.lowerBound, timezone: timezone)) – \(Fmt.time(window.upperBound, timezone: timezone))")
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func handleScrub(_ progress: Double) {
        guard canScrub else { return }
        let clamped = min(max(progress, 0), 1)
        let stage = scrubStageLabel(clamped)
        if stage != lastStage {
            Haptics.selection()
            lastStage = stage
        }
        scrubProgress = clamped
    }

    private func endScrub() {
        scrubProgress = nil
        lastStage = nil
    }

    private func label(_ title: String, _ date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.serif(.caption2))
                .foregroundStyle(.white.opacity(0.75))
            Text(date.map { Fmt.time($0, timezone: timezone) } ?? "—")
                .font(.serif(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct ArcView: View {
    let progress: Double
    let isDaylight: Bool
    let phase: DayPhase
    let isScrubbing: Bool
    let canScrub: Bool
    let onScrub: (Double) -> Void
    let onEnd: () -> Void

    /// A literal read of the day's light, left (sunrise) → right (sunset):
    /// cool first light, a warm golden-hour sunrise, blue mid-morning, a pale
    /// bright noon, blue afternoon, a golden-hour glow, then a deep sunset.
    /// Tuned to look like real sky tones — not a saturated rainbow.
    private static let dayWash = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(hex: 0x3E6390).opacity(0.22), location: 0.00),
            Gradient.Stop(color: Color(hex: 0xF4A85C).opacity(0.34), location: 0.13),
            Gradient.Stop(color: Color(hex: 0xAFCDEA).opacity(0.20), location: 0.32),
            Gradient.Stop(color: Color(hex: 0xDCEBF8).opacity(0.16), location: 0.50),
            Gradient.Stop(color: Color(hex: 0xAFCDEA).opacity(0.20), location: 0.68),
            Gradient.Stop(color: Color(hex: 0xF4A85C).opacity(0.34), location: 0.87),
            Gradient.Stop(color: Color(hex: 0xC65A36).opacity(0.32), location: 1.00)
        ]),
        startPoint: .leading, endPoint: .trailing
    )

    /// Deep night sky for the hours outside the daylight window.
    private static let nightWash = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(hex: 0x0D1733).opacity(0.40), location: 0.00),
            Gradient.Stop(color: Color(hex: 0x1C2E57).opacity(0.34), location: 0.50),
            Gradient.Stop(color: Color(hex: 0x0D1733).opacity(0.40), location: 1.00)
        ]),
        startPoint: .leading, endPoint: .trailing
    )

    private var wash: LinearGradient {
        phase == .night ? Self.nightWash : Self.dayWash
    }

    /// The sun's glow shifts with the position along the arc — which is the live
    /// time of day, or the scrubbed position while dragging: a warm orange at
    /// sunrise, bright pale gold at midday, a deep red-orange at sunset.
    private var sunGlow: Color {
        let p = min(max(progress, 0), 1)
        let hex: UInt = p < 0.5
            ? SkyPalette.mixHex(0xFF7A3D, 0xFFF1C2, p / 0.5)
            : SkyPalette.mixHex(0xFFF1C2, 0xFF5E3A, (p - 0.5) / 0.5)
        return Color(hex: hex)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let control = CGPoint(x: w / 2, y: -h * 0.7)
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                p.addQuadCurve(to: CGPoint(x: w, y: h), control: control)
            }
            // Closed region under the arc, used to clip the day-progression fill.
            let fillShape = Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                p.addQuadCurve(to: CGPoint(x: w, y: h), control: control)
                p.closeSubpath()
            }

            ZStack {
                // The sun-tone wash under the curve, softly blurred and faded
                // downward so it melts into the card instead of ending on a hard
                // straight line at the bottom.
                // The sun-tone wash under the curve, softly blurred and faded
                // downward so it melts into the card instead of ending on a hard
                // straight line at the bottom.
                wash
                    .blur(radius: 5)
                    .clipShape(fillShape)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white.opacity(0.85), location: 0.5),
                                .init(color: .white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                path.stroke(.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 2, dash: [4, 5]))

                // Progress trail up to the current position — warm by day, a cool
                // silver by night.
                path.trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: isDaylight
                                ? [Color(hex: 0xFFD66B), Color(hex: 0xFF9E6B)]
                                : [Color(hex: 0xA9B8E2), Color(hex: 0xD8E0F2)],
                            startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )

                // The traversing marker (sun or moon), draggable to scrub the day
                // or the night.
                marker
                    .position(pointOnArc(progress: progress, width: w, height: h))
                    .gesture(dragGesture(width: w))
            }
        }
    }

    /// Maps a horizontal drag to arc progress. Because the Bézier control x is
    /// centered, the curve's x at parameter t is exactly t·w, so progress = x/w.
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canScrub, width > 0 else { return }
                onScrub(value.location.x / width)
            }
            .onEnded { _ in
                guard canScrub else { return }
                onEnd()
            }
    }

    /// The current celestial body — sun by day, moon by night.
    @ViewBuilder private var marker: some View {
        if isDaylight { sunMarker } else { moonMarker }
    }

    private var sunMarker: some View {
        Circle()
            .fill(Color(hex: 0xFFE08A))
            .frame(width: 14, height: 14)
            .shadow(color: sunGlow.opacity(0.9), radius: isScrubbing ? 10 : 8)
            // A generous transparent hit area so the sun is easy to grab.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private var moonMarker: some View {
        Circle()
            .fill(Color(hex: 0xD2DCF1))
            .frame(width: 13, height: 13)
            .shadow(color: Color(hex: 0x9FB6E0).opacity(0.6), radius: isScrubbing ? 9 : 6)
            // Match the sun's hit area so the moon is just as easy to scrub.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func pointOnArc(progress: Double, width: CGFloat, height: CGFloat) -> CGPoint {
        let t = progress
        let start = CGPoint(x: 0, y: height)
        let end = CGPoint(x: width, y: height)
        let control = CGPoint(x: width / 2, y: -height * 0.7)
        let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
        let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
        return CGPoint(x: x, y: y)
    }
}
