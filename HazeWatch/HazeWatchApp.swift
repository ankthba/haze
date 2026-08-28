//
//  HazeWatchApp.swift
//  HazeWatch
//
//  The watch app: the same editorial voice at a glance. It reads the snapshot
//  the phone publishes into the App Group when it can, and fetches its own
//  single-location forecast when it can't — so the wrist is never blank just
//  because the phone hasn't been opened today.
//

import SwiftUI

@main
struct HazeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchWeatherView()
        }
    }
}

struct WatchWeatherView: View {
    @State private var snapshot: WatchSnapshot?
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let snapshot {
                content(snapshot)
            } else if failed {
                Text("Open Haze on your iPhone to load a forecast.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            } else {
                ProgressView()
                    .padding(.top, 30)
            }
        }
        .containerBackground(gradient(for: snapshot), for: .navigation)
        .navigationTitle("Haze")
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func content(_ s: WatchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.locationName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.temperatureText)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                Image(systemName: s.conditionSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22))
            }

            Text(s.conditionText)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(.secondary)

            Text(s.highLowText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if !s.hours.isEmpty {
                Divider()
                ForEach(s.hours.prefix(5), id: \.time) { hour in
                    HStack {
                        Text(hour.time)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        Image(systemName: hour.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 13))
                        Spacer()
                        Text(hour.temp)
                            .font(.system(size: 15, design: .serif))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func gradient(for snapshot: WatchSnapshot?) -> LinearGradient {
        let colors = (snapshot?.skyHexes ?? [0x3D86E6, 0x68A4E8, 0xBCD7F1])
            .map { Color(watchHex: $0) }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func load(force: Bool = false) async {
        // Shared snapshot first — instant, and matches the phone exactly.
        if !force, let shared = WatchSnapshotStore.readShared() {
            snapshot = shared
            return
        }
        if let fresh = await WatchSnapshotStore.fetchOwn() {
            snapshot = fresh
        } else if let shared = WatchSnapshotStore.readShared() {
            snapshot = shared
        } else {
            failed = true
        }
    }
}

extension Color {
    init(watchHex hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
