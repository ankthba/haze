//
//  WeatherWidget.swift
//  WeatherWidget
//
//  Home-screen widget, styled to match the app's editorial identity: Instrument
//  Serif numerals with a small raised degree, a hairline rule, and a pastel
//  frosted-card background. Built around fixed, fit-tested layouts so nothing
//  spills past the edges.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct WeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherWidgetSnapshot
}

struct WeatherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: WidgetPlaceIntent, in context: Context) async -> WeatherEntry {
        if let pinned = configuration.place,
           let cached = WeatherSnapshotStore.read(forPlaceID: pinned.id, unit: Self.unitPrefs().temperatureUnit) {
            return WeatherEntry(date: .now, snapshot: cached)
        }
        return WeatherEntry(date: .now, snapshot: WeatherSnapshotStore.read() ?? .placeholder)
    }

    /// The app's unit preferences, written on every load — never gated on the
    /// device-location publish, so a saved-cities-only Celsius user doesn't get
    /// Fahrenheit pinned widgets. The location record is the legacy fallback.
    static func unitPrefs() -> WidgetUnitPrefs {
        if let prefs = WeatherSnapshotStore.readUnitPrefs() { return prefs }
        if let loc = WeatherSnapshotStore.readLocation() {
            return WidgetUnitPrefs(temperatureUnit: loc.temperatureUnit,
                                   windSpeedUnit: loc.windSpeedUnit,
                                   precipitationUnit: loc.precipitationUnit)
        }
        return WidgetUnitPrefs(temperatureUnit: "fahrenheit",
                               windSpeedUnit: "mph", precipitationUnit: "inch")
    }

    func timeline(for configuration: WidgetPlaceIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let snapshot: WeatherWidgetSnapshot
        if let pinned = configuration.place {
            snapshot = await pinnedSnapshot(for: pinned)
        } else {
            snapshot = await deviceSnapshot()
        }
        let next = Calendar.current.date(byAdding: .minute, value: 45, to: .now)
            ?? .now.addingTimeInterval(2700)
        return Timeline(entries: [WeatherEntry(date: .now, snapshot: snapshot)],
                        policy: .after(next))
    }

    /// Follow-the-device widgets read what the app publishes; the freshness
    /// gate keeps a reload from re-fetching data the app wrote moments ago —
    /// each publish reloads every placed widget, and without the gate that was
    /// the exact multiplied-request pattern that once got the app rate-limited.
    /// The 20-minute window sits well inside the 45-minute timeline policy, so
    /// WidgetKit's own scheduled reloads (app closed) still fetch fresh data.
    private func deviceSnapshot() async -> WeatherWidgetSnapshot {
        if let cached = WeatherSnapshotStore.read(),
           Date().timeIntervalSince(cached.updatedAt) < 20 * 60 {
            return cached
        }
        if let location = WeatherSnapshotStore.readLocation(),
           let fresh = await WidgetWeatherFetcher.fetch(location) {
            WeatherSnapshotStore.cache(fresh)
            return fresh
        }
        return WeatherSnapshotStore.read() ?? .placeholder
    }

    /// Pinned widgets fetch their own city (a single-location call), behind
    /// the same 20-minute per-place gate. Unit preferences follow the app's,
    /// and are baked into the cache key so a unit change refetches promptly.
    private func pinnedSnapshot(for pinned: WidgetPlaceEntity) async -> WeatherWidgetSnapshot {
        let prefs = Self.unitPrefs()
        let unit = prefs.temperatureUnit
        if let cached = WeatherSnapshotStore.read(forPlaceID: pinned.id, unit: unit),
           Date().timeIntervalSince(cached.updatedAt) < 20 * 60 {
            return cached
        }
        let location = WidgetLocation(latitude: pinned.latitude,
                                      longitude: pinned.longitude,
                                      name: pinned.name,
                                      timezone: "auto",
                                      temperatureUnit: prefs.temperatureUnit,
                                      windSpeedUnit: prefs.windSpeedUnit,
                                      precipitationUnit: prefs.precipitationUnit)
        if let fresh = await WidgetWeatherFetcher.fetch(location) {
            WeatherSnapshotStore.cache(fresh, forPlaceID: pinned.id, unit: unit)
            return fresh
        }
        return WeatherSnapshotStore.read(forPlaceID: pinned.id, unit: unit) ?? .placeholder
    }
}

// MARK: - Widget

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WeatherSnapshotStore.widgetKind,
                               intent: WidgetPlaceIntent.self,
                               provider: WeatherProvider()) { entry in
            WeatherWidgetEntryView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Haze")
        .description("Your local forecast at a glance. Edit the widget to pin a saved city.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct WeatherWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineAccessoryView(snapshot: snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularAccessoryView(snapshot: snapshot)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            RectangularAccessoryView(snapshot: snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            SmallWidgetView(snapshot: snapshot)
                .containerBackground(for: .widget) { WidgetCardBackground(hexes: snapshot.skyHexes) }
        case .systemLarge:
            LargeWidgetView(snapshot: snapshot)
                .containerBackground(for: .widget) { WidgetCardBackground(hexes: snapshot.skyHexes) }
        default:
            MediumWidgetView(snapshot: snapshot)
                .containerBackground(for: .widget) { WidgetCardBackground(hexes: snapshot.skyHexes) }
        }
    }
}

// MARK: - Lock Screen accessories

/// "72° Partly Cloudy" on one Lock Screen line.
private struct InlineAccessoryView: View {
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        // Inline widgets render a single Label; keep it terse.
        Label("\(snapshot.temperatureText) \(snapshot.conditionText)",
              systemImage: snapshot.conditionSymbol)
    }
}

/// Condition glyph over the temperature, in the system's vibrant circle.
private struct CircularAccessoryView: View {
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: snapshot.conditionSymbol)
                .font(.system(size: 14, weight: .medium))
            Text(snapshot.temperatureText)
                .font(.system(size: 18, weight: .semibold, design: .serif))
        }
        .widgetAccentable()
    }
}

/// Place, condition, and range — the small widget's story in vibrant text.
private struct RectangularAccessoryView: View {
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(snapshot.locationName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .widgetAccentable()

            HStack(spacing: 5) {
                Image(systemName: snapshot.conditionSymbol)
                    .font(.system(size: 12))
                Text(snapshot.temperatureText)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                Text(snapshot.highLowText)
                    .font(.system(size: 12))
                    .opacity(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Building blocks

/// Location name with a leading arrow, in the app's tracked sans for legibility.
private struct LocationLabel: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: size - 3, weight: .semibold))
            Text(name)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

/// Multicolor condition glyph.
private struct ConditionGlyph: View {
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
    }
}

/// Big serif temperature with a smaller, raised degree — the app's signature.
private struct TemperatureText: View {
    let text: String   // e.g. "81°"
    var size: CGFloat

    private var number: String { text.replacingOccurrences(of: "°", with: "") }
    private var hasDegree: Bool { text.contains("°") }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(number)
                .font(.displaySerif(size))
            if hasDegree {
                Text("°")
                    .font(.displaySerif(size * 0.58))
                    .baselineOffset(size * 0.16)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One column of the hourly strip: time, glyph, temperature.
private struct HourCell: View {
    let hour: WeatherWidgetHour

    var body: some View {
        VStack(spacing: 5) {
            Text(hour.time)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: hour.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 18))
                .frame(height: 20)
            Text(hour.temp)
                .font(.serif(16))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                LocationLabel(name: snapshot.locationName, size: 12)
                Spacer(minLength: 4)
                ConditionGlyph(symbol: snapshot.conditionSymbol, size: 20)
            }

            Spacer(minLength: 6)

            TemperatureText(text: snapshot.temperatureText, size: 54)

            Spacer(minLength: 6)

            Text(snapshot.conditionText)
                .font(.serif(15))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(snapshot.highLowText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

private struct MediumWidgetView: View {
    let snapshot: WeatherWidgetSnapshot

    /// A high/low item: a small arrow + the serif temperature, mirroring the app.
    private func highLow(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.serif(15))
                .foregroundStyle(.white.opacity(0.92))
        }
        .fixedSize()
    }

    var body: some View {
        VStack(spacing: 0) {
            // One headline row: big temperature (far left), the big glyph (far
            // right), and a centered cluster of high/low + location between them.
            HStack(alignment: .center, spacing: 8) {
                TemperatureText(text: snapshot.temperatureText, size: 56)
                    .padding(.leading, 8)
                    .offset(y: 4)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        highLow("arrow.up", snapshot.highText)
                        highLow("arrow.down", snapshot.lowText)
                    }
                    Text(snapshot.locationName)
                        .font(.serif(14, italic: true))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 8)

                ConditionGlyph(symbol: snapshot.conditionSymbol, size: 38)
            }

            Spacer(minLength: 14)

            // The hourly strip, lifted up a little off the bottom.
            HStack(spacing: 0) {
                ForEach(snapshot.hours.prefix(6), id: \.self) { HourCell(hour: $0) }
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Large

private struct LargeWidgetView: View {
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: temperature + condition on the left, glyph + location right.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    TemperatureText(text: snapshot.temperatureText, size: 58)
                    Text(snapshot.conditionText)
                        .font(.serif(16, italic: true))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    ConditionGlyph(symbol: snapshot.conditionSymbol, size: 34)
                    LocationLabel(name: snapshot.locationName, size: 12)
                }
            }

            Spacer(minLength: 12)

            // Hourly strip.
            HStack(spacing: 0) {
                ForEach(snapshot.hours.prefix(6), id: \.self) { HourCell(hour: $0) }
            }

            Spacer(minLength: 12)

            // Daily outlook, hairline-separated like the app's 10-day list.
            VStack(spacing: 0) {
                ForEach(Array((snapshot.days ?? []).prefix(5).enumerated()),
                        id: \.element) { index, day in
                    if index > 0 {
                        Divider().overlay(.white.opacity(0.14))
                    }
                    HStack(spacing: 8) {
                        Text(day.name)
                            .font(.serif(15))
                            .foregroundStyle(.white)
                            .frame(width: 62, alignment: .leading)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: day.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 15))
                            .frame(width: 24)
                        Spacer(minLength: 0)
                        Text(day.low)
                            .font(.serif(15))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 40, alignment: .trailing)
                        Text(day.high)
                            .font(.serif(15))
                            .foregroundStyle(.white)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    WeatherWidget()
} timeline: {
    WeatherEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    WeatherWidget()
} timeline: {
    WeatherEntry(date: .now, snapshot: .placeholder)
}
