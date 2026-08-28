//
//  SunEventsView.swift
//  Weather
//
//  Tap the sun readout in the bottom bar to open this page: the next sunrise
//  or sunset, rated — how likely it is to be worth stepping outside (or
//  setting an alarm) for. The background is the sky the forecast is promising:
//  ember and gold when the clouds are set up to burn, ash and slate when they
//  aren't. The headline is a verdict; the table below it is the evidence.
//

import SwiftUI

/// The tiers' display colors live with the view: the model stays pure data.
/// Internal, so the bottom bar can tint its one-word rating the same way.
extension SunQuality.Tier {
    var accent: Color {
        switch self {
        case .poor:        return Color(hex: 0x9AA5B4)
        case .fair:        return Color(hex: 0xC3CCD4)
        case .good:        return Color(hex: 0xF4D08A)
        case .great:       return Color(hex: 0xF4A85C)
        case .spectacular: return Color(hex: 0xFF7A52)
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
            SunSkyGradient(kind: featured?.kind ?? .sunset,
                           score: featured?.rating?.score ?? 30)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    if let event = featured {
                        header(event)
                        statRow(event)
                        if let rating = event.rating {
                            skyTable(event, rating)
                        } else {
                            unratedNote
                        }
                    }
                    if events.count > 1 {
                        daysAhead
                    }
                    methodFootnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
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
        .animation(.easeInOut(duration: 0.45), value: selectedID)
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
        VStack(spacing: 0) {
            Text("\(dayLabel(event.date))'s \(event.kind.rawValue.lowercased())")
                .font(.serif(.subheadline, italic: true))
                .foregroundStyle(.white.opacity(0.8))

            if let rating = event.rating {
                Text("\(rating.score)")
                    .font(.displaySerif(size: 118))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .padding(.top, -4)

                Text(rating.tier.rawValue)
                    .font(.serif(.title3, italic: true))
                    .foregroundStyle(rating.tier.accent)
                    .padding(.top, -8)

                // The standfirst — same voice as the home screen's brief.
                Text(SunQuality.narrative(kind: event.kind, rating: rating,
                                          eventDate: event.date, timezone: timezone))
                    .font(.serif(.callout, italic: true))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 18)
                    .padding(.horizontal, 6)
            } else {
                Text(Fmt.time(event.date, timezone: timezone))
                    .font(.displaySerif(size: 64))
                    .foregroundStyle(.white)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stat row

    /// The event's vitals in one hairline-divided line: when, where on the
    /// horizon to look, when the light turns golden, and the day's span.
    private func statRow(_ event: SunEvent) -> some View {
        let azimuth = SunPosition.azimuth(date: event.date,
                                          latitude: bundle.place.latitude,
                                          longitude: bundle.place.longitude)
        let golden: Date? = event.kind == .sunset
            ? GoldenHour.evening(sunset: event.date)?.lowerBound
            : event.date
        return HStack(spacing: 0) {
            stat(event.kind == .sunset ? "Sets" : "Rises",
                 Fmt.time(event.date, timezone: timezone))
            statDivider
            stat("Look", Fmt.windDirectionLabel(azimuth))
            if let golden {
                statDivider
                stat("Golden light", event.kind == .sunset
                        ? "from \(Fmt.time(golden, timezone: timezone))"
                        : "til \(Fmt.time(golden.addingTimeInterval(3600), timezone: timezone))")
            }
            if let daylight = daylightSpan(event) {
                statDivider
                stat("Daylight", daylight)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.serif(.caption2))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.serif(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: 0.6, height: 26)
    }

    private var hairline: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(height: 0.6)
    }

    /// "13h 12m" for the event's own day, when the daily window covers it.
    private func daylightSpan(_ event: SunEvent) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        guard let day = bundle.daily.first(where: { cal.isDate($0.date, inSameDayAs: event.date) }),
              let sunrise = day.sunrise, let sunset = day.sunset, sunset > sunrise
        else { return nil }
        let minutes = Int(sunset.timeIntervalSince(sunrise) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - The sky, itemized

    /// The evidence behind the verdict — a quiet ledger, not a dashboard.
    private func skyTable(_ event: SunEvent, _ rating: SunQuality.Rating) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The sky at \(Fmt.time(event.date, timezone: timezone))")
                .font(.serif(.footnote, italic: true))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 10)

            tableRow("High cloud", Fmt.percent(rating.cloudHigh), note: "the canvas")
            tableRow("Mid cloud", Fmt.percent(rating.cloudMid))
            tableRow("Low cloud", Fmt.percent(rating.cloudLow), note: "the wall")
            if let visibility = rating.visibility {
                tableRow("Visibility", Fmt.visibility(visibility, unit: unit))
            }
            tableRow("Humidity", Fmt.percent(rating.humidity))
            tableRow("Rain chance", Fmt.percent(Double(rating.rainRisk)), isLast: true)
        }
    }

    private func tableRow(_ label: String, _ value: String,
                          note: String? = nil, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.85))
                if let note {
                    Text(note)
                        .font(.serif(.caption, italic: true))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(value)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.vertical, 9)
            if !isLast {
                hairline.opacity(0.55)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private var unratedNote: some View {
        Text("The cloud layers needed to rate this one haven't arrived yet — pull down on the main screen to refresh the forecast.")
            .font(.serif(.subheadline, italic: true))
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The days ahead

    private var daysAhead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The days ahead")
                .font(.serif(.footnote, italic: true))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 6)

            let listed = Array(events.prefix(10))
            ForEach(listed) { event in
                Button {
                    Haptics.selection()
                    selectedID = event.id
                } label: {
                    eventRow(event, isLast: event.id == listed.last?.id)
                }
                .buttonStyle(.plain)
            }

            Text("Worth an early alarm when a sunrise reads Great or better.")
                .font(.serif(.caption, italic: true))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 12)
        }
    }

    private func eventRow(_ event: SunEvent, isLast: Bool) -> some View {
        let isFeatured = event.id == featured?.id
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayLabel(event.date)) \(event.kind.rawValue.lowercased())")
                        .font(.serif(.subheadline, weight: isFeatured ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(isFeatured ? 1 : 0.88))
                    Text(event.rating.map {
                            "\(Fmt.time(event.date, timezone: timezone)) · \($0.signature)"
                         } ?? Fmt.time(event.date, timezone: timezone))
                        .font(.serif(.caption, italic: true))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                if let rating = event.rating {
                    Text(rating.tier.rawValue)
                        .font(.serif(.caption, italic: true))
                        .foregroundStyle(rating.tier.accent)
                    Text("\(rating.score)")
                        .font(.serif(.title3))
                        .foregroundStyle(.white.opacity(isFeatured ? 1 : 0.9))
                        .frame(minWidth: 34, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.serif(.title3))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.vertical, 10)
            if !isLast {
                hairline.opacity(0.55)
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
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - The promised sky

/// A full-bleed gradient of the sky the forecast expects: the score slides
/// each band between an ashen "nothing doing" tone and the vivid version of
/// itself, so a Spectacular evening glows before a single word is read.
/// Sunset skies run coral into gold; sunrise skies run rose into pale honey.
private struct SunSkyGradient: View {
    let kind: SunEvent.Kind
    let score: Int

    private var stops: [Gradient.Stop] {
        // (muted, vivid) pairs, top → horizon.
        let bands: [(UInt, UInt, Double)] = kind == .sunset
            ? [(0x1E2742, 0x252041, 0.00),
               (0x35415E, 0x59416E, 0.38),
               (0x6B7689, 0xB05A64, 0.64),
               (0x93999F, 0xE08052, 0.84),
               (0xA9AAA8, 0xF6B168, 1.00)]
            : [(0x232C49, 0x2C3157, 0.00),
               (0x3A4560, 0x565277, 0.38),
               (0x6F7889, 0xA96A85, 0.64),
               (0x969BA1, 0xE0925E, 0.84),
               (0xABACAB, 0xF6C579, 1.00)]
        let t = min(max(Double(score) / 100, 0), 1)
        return bands.map { muted, vivid, location in
            Gradient.Stop(color: Color(hex: SkyPalette.mixHex(muted, vivid, t)),
                          location: location)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(stops: stops),
                           startPoint: .top, endPoint: .bottom)

            // The sun's afterglow pooling at the horizon, brighter the better
            // the forecast: an ellipse of warm light melting upward.
            GeometryReader { geo in
                Ellipse()
                    .fill(Color(hex: kind == .sunset ? 0xFFCE8A : 0xFFE0A3))
                    .frame(width: geo.size.width * 1.6, height: geo.size.height * 0.5)
                    .position(x: geo.size.width / 2, y: geo.size.height * 1.05)
                    .blur(radius: 70)
                    .opacity(0.05 + 0.30 * Double(score) / 100)
            }
        }
    }
}
