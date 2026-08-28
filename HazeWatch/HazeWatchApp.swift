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
    init() { WatchFonts.register() }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchWeatherView()
            }
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
                    .font(.watchSerif(15, italic: true))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            } else {
                ProgressView()
                    .padding(.top, 30)
            }
        }
        .containerBackground(for: .navigation) { WatchSkyBackground(hexes: snapshot?.skyHexes) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("haze°")
                    .font(.watchSerif(16, italic: true))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func content(_ s: WatchSnapshot) -> some View {
        VStack(spacing: 0) {
            // The hero mirrors the phone: centered, serif, the degree sign an
            // overlay so the numerals stay optically centered.
            Text(s.locationName)
                .font(.watchSerif(18))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(s.temperatureText.hasSuffix("°")
                 ? String(s.temperatureText.dropLast())
                 : s.temperatureText)
                .font(.watchDisplaySerif(68))
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.watchDisplaySerif(42))
                        .foregroundStyle(.white)
                        .offset(x: 16, y: 5)
                }
                .padding(.top, -2)

            Text(s.conditionText)
                .font(.watchSerif(16, italic: true))
                .foregroundStyle(.white.opacity(0.95))

            HStack(spacing: 12) {
                Label(s.highText, systemImage: "arrow.up")
                Label(s.lowText, systemImage: "arrow.down")
            }
            .font(.watchSerif(14))
            .imageScale(.small)
            .foregroundStyle(.white.opacity(0.88))
            .padding(.top, 5)

            if !s.hours.isEmpty {
                hairline
                    .padding(.top, 12)
                    .padding(.bottom, 9)

                VStack(spacing: 7) {
                    ForEach(s.hours.prefix(5), id: \.time) { hour in
                        HStack(spacing: 0) {
                            Text(hour.time)
                                .font(.watchSerif(14))
                                .foregroundStyle(.white.opacity(0.66))
                                .frame(width: 52, alignment: .leading)
                            Image(systemName: hour.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                                .font(.system(size: 12))
                            Spacer()
                            Text(hour.temp)
                                .font(.watchSerif(16))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
    }

    /// Hairline rule — the app's signature divider.
    private var hairline: some View {
        Rectangle()
            .fill(.white.opacity(0.26))
            .frame(height: 0.5)
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

/// A miniature of the phone's SkyBackground: the shared gradient, a soft
/// sun/moon glow, atmospheric haze pooling at the horizon, and the same
/// bottom-weighted scrim so white type reads comfortably.
struct WatchSkyBackground: View {
    let hexes: [UInt]?

    private var colors: [UInt] { hexes ?? [0x3D86E6, 0x68A4E8, 0xBCD7F1] }

    /// Perceived brightness of the top stop — enough to tell night from day so
    /// the glow and haze take the right tint.
    private var isDarkSky: Bool {
        let hex = colors.first ?? 0x3D86E6
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.28
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors.map { Color(watchHex: $0) },
                           startPoint: .top, endPoint: .bottom)

            // Soft sun/moon glow, gently diffused.
            RadialGradient(
                colors: [glowColor.opacity(glowOpacity), .clear],
                center: .init(x: 0.78, y: 0.14),
                startRadius: 0,
                endRadius: 260)
                .blendMode(.screen)

            // Atmospheric haze drifting up from the horizon.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: hazeColor.opacity(hazeStrength * 0.5), location: 0.74),
                    .init(color: hazeColor.opacity(hazeStrength), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom)

            // Bottom-weighted deepening scrim, matching the phone's stops.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.22), location: 0),
                    .init(color: .black.opacity(0.22), location: 0.45),
                    .init(color: .black.opacity(0.30), location: 0.72),
                    .init(color: .black.opacity(0.40), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var glowColor: Color {
        Color(watchHex: isDarkSky ? 0xC4D4F2 : 0xFFF3D2)
    }
    private var glowOpacity: Double { isDarkSky ? 0.13 : 0.32 }

    private var hazeColor: Color {
        Color(watchHex: isDarkSky ? 0x9FB2D8 : 0xEAF3FB)
    }
    private var hazeStrength: Double { isDarkSky ? 0.07 : 0.17 }
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
