//
//  HazeComplications.swift
//  HazeWatchComplications
//
//  Watch face complications: temperature and condition at a glance, in the
//  corner, circle, inline and rectangular families. They render from the
//  shared snapshot, refreshing on WidgetKit's own schedule.
//

import WidgetKit
import SwiftUI

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now,
                                     snapshot: WatchSnapshotStore.readShared() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            // Prefer what the phone published; fetch only when that's stale,
            // keeping watch-side API usage to one small request.
            var snapshot = WatchSnapshotStore.readShared()
            if snapshot == nil { snapshot = await WatchSnapshotStore.fetchOwn() }
            let resolved = snapshot ?? .placeholder
            let next = Calendar.current.date(byAdding: .minute, value: 45, to: .now)
                ?? .now.addingTimeInterval(2700)
            completion(Timeline(entries: [ComplicationEntry(date: .now, snapshot: resolved)],
                                policy: .after(next)))
        }
    }
}

@main
struct HazeComplications: WidgetBundle {
    var body: some Widget {
        HazeComplication()
    }
}

struct HazeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HazeComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Haze")
        .description("Current conditions at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryInline, .accessoryRectangular])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WatchSnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(snapshot.temperatureText) \(snapshot.conditionText)",
                  systemImage: snapshot.conditionSymbol)

        case .accessoryCorner:
            Text(snapshot.temperatureText)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .widgetCurvesContent()
                .widgetLabel(snapshot.conditionText)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.locationName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(spacing: 5) {
                    Image(systemName: snapshot.conditionSymbol)
                        .font(.system(size: 12))
                    Text(snapshot.temperatureText)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                    Text(snapshot.highLowText)
                        .font(.system(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:   // .accessoryCircular
            VStack(spacing: 0) {
                Image(systemName: snapshot.conditionSymbol)
                    .font(.system(size: 13, weight: .medium))
                Text(snapshot.temperatureText)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
            }
            .widgetAccentable()
        }
    }
}
