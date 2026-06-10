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

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(WeatherEntry(date: .now, snapshot: WeatherSnapshotStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        // Fetch fresh data ourselves so the widget updates on WidgetKit's schedule
        // even when the app hasn't been opened. Fall back to the last cached
        // snapshot (written by the app or a previous fetch) on any failure.
        Task {
            let snapshot: WeatherWidgetSnapshot
            if let location = WeatherSnapshotStore.readLocation(),
               let fresh = await WidgetWeatherFetcher.fetch(location) {
                WeatherSnapshotStore.cache(fresh)
                snapshot = fresh
            } else {
                snapshot = WeatherSnapshotStore.read() ?? .placeholder
            }
            let next = Calendar.current.date(byAdding: .minute, value: 45, to: .now)
                ?? .now.addingTimeInterval(2700)
            completion(Timeline(entries: [WeatherEntry(date: .now, snapshot: snapshot)],
                                policy: .after(next)))
        }
    }
}

// MARK: - Widget

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeatherSnapshotStore.widgetKind,
                            provider: WeatherProvider()) { entry in
            WeatherWidgetEntryView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetCardBackground(hexes: entry.snapshot.skyHexes)
                }
        }
        .configurationDisplayName("Haze")
        .description("Your local forecast at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct WeatherWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WeatherWidgetSnapshot

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(snapshot: snapshot)
        default:           MediumWidgetView(snapshot: snapshot)
        }
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
                .font(.instrumentSerif(size))
            if hasDegree {
                Text("°")
                    .font(.instrumentSerif(size * 0.58))
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
                .font(.instrumentSerif(16))
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
                .font(.instrumentSerif(15))
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
                .font(.instrumentSerif(15))
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
                        .font(.instrumentSerif(14, italic: true))
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

// MARK: - Preview

#Preview(as: .systemMedium) {
    WeatherWidget()
} timeline: {
    WeatherEntry(date: .now, snapshot: .placeholder)
}
