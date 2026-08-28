//
//  SunEventsView.swift
//  Weather
//
//  Tap the sun readout in the bottom bar to open this sheet: quality ratings
//  for the coming sunrises and sunsets — how likely each one is to be worth
//  stepping outside (or setting an alarm) for. The headline rates the next
//  event; the list below rates the days ahead, and tapping a row promotes it
//  to the headline.
//

import SwiftUI

/// The tiers' display colors live with the view: the model stays pure data.
private extension SunQuality.Tier {
    var accent: Color {
        switch self {
        case .poor:        return Color(hex: 0x8B97A8)
        case .fair:        return Color(hex: 0xB8C4CE)
        case .good:        return Color(hex: 0xF4D08A)
        case .great:       return Color(hex: 0xF4A85C)
        case .spectacular: return Color(hex: 0xFF6B4A)
        }
    }
}

struct SunEventsView: View {
    let bundle: WeatherBundle
    let unit: TemperatureUnit

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var timezone: TimeZone { bundle.timezone }

    private var events: [SunEvent] {
        SunQuality.upcomingEvents(in: bundle)
    }

    /// The event the headline describes — the tapped row, or the next one up.
    private var featured: SunEvent? {
        events.first { $0.id == selectedID } ?? events.first
    }

    var body: some View {
        ZStack {
            SkyBackground(condition: bundle.current.condition,
                          now: Date(),
                          sunrise: bundle.today?.sunrise,
                          sunset: bundle.today?.sunset)

            ScrollView {
                VStack(spacing: 20) {
                    if let event = featured {
                        header(event)
                        if let rating = event.rating {
                            breakdownCard(rating)
                        } else {
                            unratedCard
                        }
                        goldenHourCard(event)
                    }
                    if events.count > 1 {
                        upcomingCard
                    }
                    methodFootnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 44) }

            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)

            topBar
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .animation(.easeOut(duration: 0.25), value: selectedID)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(CardButtonStyle())
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            Spacer()
        }
    }

    // MARK: - Headline

    private func header(_ event: SunEvent) -> some View {
        VStack(spacing: 6) {
            Text("\(dayLabel(event.date))'s \(event.kind.rawValue.lowercased()) · \(Fmt.time(event.date, timezone: timezone))")
                .font(.serif(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Image(systemName: event.kind.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
                .padding(.vertical, 2)

            if let rating = event.rating {
                Text("\(rating.score)")
                    .font(.displaySerif(size: 92))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(rating.tier.rawValue)
                    .font(.serif(.title2, italic: true))
                    .foregroundStyle(rating.tier.accent)

                Text(rating.tier.blurb)
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text(event.kind.rawValue)
                    .font(.serif(.title2, italic: true))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Breakdown

    private func breakdownCard(_ rating: SunQuality.Rating) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                CardLabel(systemImage: "cloud.sun", title: "What the sky brings")

                factorRow("Cloud canvas", rating.canvas,
                          detail: "High cloud \(Int(rating.cloudHigh.rounded()))% · mid \(Int(rating.cloudMid.rounded()))% — the layers that catch color")
                factorRow("Clear horizon", rating.horizon,
                          detail: "Low cloud \(Int(rating.cloudLow.rounded()))% — the wall that hides the show")
                factorRow("Air clarity", rating.clarity,
                          detail: "Clean, dry air keeps the palette vivid")
                factorRow("Dry skies", 100 - rating.rainRisk,
                          detail: rating.rainRisk > 0
                              ? "\(rating.rainRisk)% chance of rain around the event"
                              : "No rain expected around the event")
            }
        }
    }

    private func factorRow(_ title: String, _ value: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(value)")
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.8))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.14))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Color(hex: 0xF4D08A), Color(hex: 0xF4A85C)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 4)

            Text(detail)
                .font(.serif(.caption2))
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) out of 100. \(detail)")
    }

    private var unratedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(systemImage: "cloud.sun", title: "No rating yet")
                Text("The cloud layers needed to rate this one haven't arrived yet — pull down on the main screen to refresh the forecast.")
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - Golden hour

    @ViewBuilder
    private func goldenHourCard(_ event: SunEvent) -> some View {
        let window: ClosedRange<Date>? = event.kind == .sunset
            ? GoldenHour.evening(sunset: event.date)
            : GoldenHour.morning(sunrise: event.date)
        if let window {
            GlassCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Golden hour")
                            .font(.serif(.caption2))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("\(Fmt.time(window.lowerBound, timezone: timezone)) – \(Fmt.time(window.upperBound, timezone: timezone))")
                            .font(.serif(.subheadline, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(event.kind == .sunset ? "Best light before" : "Best light after")
                            .font(.serif(.caption2))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(Fmt.time(event.date, timezone: timezone))
                            .font(.serif(.subheadline, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - The days ahead

    private var upcomingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "calendar", title: "The days ahead")

                ForEach(events.prefix(10)) { event in
                    Button {
                        Haptics.selection()
                        selectedID = event.id
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)

                    if event.id != events.prefix(10).last?.id {
                        Divider().overlay(Color.white.opacity(0.1))
                    }
                }

                Text("Worth an early alarm when a sunrise reads Great or better.")
                    .font(.serif(.caption, italic: true))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func eventRow(_ event: SunEvent) -> some View {
        let isFeatured = event.id == featured?.id
        return HStack(spacing: 12) {
            Image(systemName: event.kind.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(dayLabel(event.date)) \(event.kind.rawValue.lowercased())")
                    .font(.serif(.subheadline, weight: isFeatured ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isFeatured ? 1 : 0.9))
                Text(Fmt.time(event.date, timezone: timezone))
                    .font(.serif(.caption2))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            if let rating = event.rating {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(rating.score)")
                        .font(.serif(.title3))
                        .foregroundStyle(.white)
                    Text(rating.tier.rawValue)
                        .font(.serif(.caption2, italic: true))
                        .foregroundStyle(rating.tier.accent)
                }
            } else {
                Text("—")
                    .font(.serif(.title3))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(event))
    }

    private func accessibilitySummary(_ event: SunEvent) -> String {
        let when = "\(dayLabel(event.date)) \(event.kind.rawValue.lowercased()) at \(Fmt.time(event.date, timezone: timezone))"
        guard let rating = event.rating else { return "\(when), not yet rated" }
        return "\(when), rated \(rating.score) out of 100, \(rating.tier.rawValue)"
    }

    // MARK: - Footnote

    private var methodFootnote: some View {
        Text("Ratings weigh the cloud layers around each event: high and mid clouds catch color from below, low clouds block the horizon, and haze or rain mutes the show.")
            .font(.serif(.caption))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    /// "Today", "Tomorrow", then weekday names.
    private func dayLabel(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        if cal.isDate(date, inSameDayAs: Date()) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()),
           cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return Fmt.fullWeekday(date, timezone: timezone)
    }
}
