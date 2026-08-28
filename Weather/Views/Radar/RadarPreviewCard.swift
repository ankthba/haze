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
    /// The place whose field has been fetched. The card lives in a LazyVStack,
    /// so `.task` re-runs every time it scrolls back on screen — this keeps
    /// that from refetching a field it already has.
    @State private var loadedPlaceID: String?

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
                                     currentIndex: field.latestObservedIndex,
                                     isDay: isDay,
                                     span: 3.5)
                            .allowsHitTesting(false)
                    } else {
                        Color(hex: 0x10151E)
                        if failed {
                            Label("Radar unavailable", systemImage: "antenna.radiowaves.left.and.right.slash")
                                .font(.serif(.footnote))
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
        .task(id: place.id) {
            guard loadedPlaceID != place.id else { return }
            failed = false
            // Detailed radar only — no costly forecast-grid fetch on the home feed.
            do {
                field = try await RadarService().buildField(center: place.coordinate,
                                                            includeForecast: false)
                loadedPlaceID = place.id
            } catch {
                // Scrolling off mid-fetch cancels the task; that's not a radar
                // failure, and the next appearance retries cleanly.
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
