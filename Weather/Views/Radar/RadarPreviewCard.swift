//
//  RadarPreviewCard.swift
//  Weather
//
//  A compact, non-interactive precipitation map in the main feed showing the
//  current frame. Tapping opens the full-screen, animatable RadarView.
//

import SwiftUI

struct RadarPreviewCard: View {
    let place: Place
    let accent: Color
    let isDay: Bool
    var onOpen: () -> Void

    @State private var field: RadarField?
    @State private var failed = false

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(systemImage: "dot.radiowaves.left.and.right", title: "Radar")
                    OpenBadge()
                }

                ZStack {
                    if let field {
                        RadarMapView(center: place.coordinate,
                                     field: field,
                                     currentIndex: field.nowIndex,
                                     isDay: isDay,
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
            do { field = try await OpenMeteoRadarService().fetchField(center: place.coordinate) }
            catch { failed = true }
        }
    }
}
