//
//  RadarPreviewCard.swift
//  Weather
//
//  A compact, non-interactive radar map in the main feed showing the latest
//  observed frame. Tapping opens the full-screen, animatable RadarView.
//

import SwiftUI

struct RadarPreviewCard: View {
    let place: Place
    let accent: Color
    var onOpen: () -> Void

    @State private var maps: RainViewerService.Maps?
    @State private var failed = false

    /// Latest observed frame (fall back to whatever's newest).
    private var latest: RadarFrame? {
        maps?.frames.last(where: { !$0.isForecast }) ?? maps?.frames.last
    }

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(systemImage: "dot.radiowaves.left.and.right", title: "Radar")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                }

                ZStack {
                    if let maps, let latest {
                        RadarMapView(center: place.coordinate,
                                     host: maps.host,
                                     frames: [latest],
                                     currentPath: latest.path,
                                     colorScheme: 4,
                                     span: 6)
                            .allowsHitTesting(false)
                    } else {
                        Color(hex: 0x10151E)
                        if failed {
                            Label("Radar unavailable", systemImage: "antenna.radiowaves.left.and.right.slash")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.55))
                        } else {
                            ProgressView().tint(.white.opacity(0.7))
                        }
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Precipitation radar for \(place.name). Opens the full radar map.")
        .task {
            do { maps = try await RainViewerService().fetchFrames() }
            catch { failed = true }
        }
    }
}
