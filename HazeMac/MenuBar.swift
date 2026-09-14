//
//  MenuBar.swift
//  HazeMac
//
//  The temperature in the menu bar, and the small page that drops from it: the
//  place, the reading, today's range, the brief, and the next few hours. Enough
//  to answer "do I need a coat" without switching apps.
//

import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let viewModel: WeatherViewModel

    var body: some View {
        if let bundle = viewModel.bundle {
            Label(Fmt.tempDegree(bundle.current.temperature),
                  systemImage: bundle.current.condition.symbolName)
        } else {
            Label("haze°", systemImage: "cloud.sun")
        }
    }
}

struct MenuBarPanel: View {
    let viewModel: WeatherViewModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            if let bundle = viewModel.bundle {
                SkyBackground(condition: bundle.current.condition,
                              now: Date(),
                              sunrise: bundle.today?.sunrise,
                              sunset: bundle.today?.sunset)
                content(bundle)
            } else {
                LinearGradient(colors: [Color(hex: 0x3D86E6), Color(hex: 0xBCD7F1)],
                               startPoint: .top, endPoint: .bottom)
                Text("Gathering the skies…")
                    .font(.serif(.body, italic: true))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(28)
            }
        }
        .frame(width: 340)
        .colorScheme(.dark)
    }

    private func content(_ bundle: WeatherBundle) -> some View {
        let current = bundle.current
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.longDate(current.date, timezone: bundle.timezone))
                    .font(.serif(.caption, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(bundle.place.name)
                    .font(.serif(.title2, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Fmt.tempDegree(current.temperature))
                    .font(.displaySerif(size: 58))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.condition.description)
                        .font(.serif(.callout, italic: true))
                        .foregroundStyle(.white.opacity(0.95))
                    HStack(spacing: 10) {
                        Label(Fmt.tempDegree(bundle.today?.tempMax ?? current.temperature),
                              systemImage: "arrow.up")
                        Label(Fmt.tempDegree(bundle.today?.tempMin ?? current.temperature),
                              systemImage: "arrow.down")
                    }
                    .font(.serif(.footnote))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }

            if !viewModel.briefText.isEmpty {
                Text(viewModel.briefText)
                    .font(.serif(.footnote, italic: true))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                ForEach(Array(bundle.upcomingHours.prefix(6).enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 6) {
                        Text(index == 0 ? "Now" : Fmt.hour(hour.date, timezone: bundle.timezone))
                            .font(.serif(.caption2, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Image(systemName: hour.condition.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 16))
                            .frame(height: 20)
                        Text(Fmt.tempDegree(hour.temperature))
                            .font(.serif(.subheadline))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) { hairline }
            .overlay(alignment: .bottom) { hairline }

            HStack {
                Button("Open Haze") {
                    NSApp.activate()
                    openWindow(id: MacWindows.mainWindowID)
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.refresh(userInitiated: true) }
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .font(.serif(.footnote, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
    }

    private var hairline: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 0.6)
    }
}
