//
//  AlertBanner.swift
//  Weather
//
//  Active NWS advisories, in the app's editorial voice: a pill that lives in
//  the top bar beside the controls — no flashing chrome, just an accent that
//  says how seriously to take it. Tapping opens the full advisory text.
//

import SwiftUI

/// The advisory as a pill sized to sit in the top bar, snug between the
/// locations button and the radar/settings pair. Same 38pt height and same
/// glass as those buttons, so the row reads as one piece of chrome.
struct AlertPill: View {
    let alerts: [WeatherAlert]
    var onOpen: () -> Void

    private var lead: WeatherAlert? {
        alerts.first(where: \.isUrgent) ?? alerts.first
    }

    private var accent: Color {
        (lead?.isUrgent ?? false) ? Color(hex: 0xFF7A6B) : Color(hex: 0xF5C46B)
    }

    var body: some View {
        if let lead {
            Button {
                Haptics.tap()
                onOpen()
            } label: {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(lead.event)
                        .font(.serif(.footnote, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if alerts.count > 1 {
                        Text("+\(alerts.count - 1)")
                            .font(.serif(.caption2, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                // Fills the gap between the controls rather than shrink-wrapping
                // the event name, so the row reads as one deliberate bar.
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                // The buttons' own material, tinted by how serious this is —
                // one family of chrome across the whole row.
                .background(
                    ZStack {
                        GlassSurface(shape: Capsule())
                        Capsule().fill(accent.opacity(0.16))
                    }
                )
                .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 0.8))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(lead.event)\(alerts.count > 1 ? ", plus \(alerts.count - 1) more" : ""). Opens the full advisory.")
        }
    }
}

// MARK: - Full advisory sheet

struct AlertDetailView: View {
    let alerts: [WeatherAlert]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A2030), Color(hex: 0x0B1020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            CardLabel(systemImage: "exclamationmark.triangle",
                                      title: "Active Advisories")
                            Text(alerts.count == 1
                                 ? (alerts.first?.event ?? "Advisory")
                                 : "\(alerts.count) advisories in force")
                                .font(.serif(size: 27))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 12)
                        Button {
                            Haptics.tap()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(CardButtonStyle())
                        .accessibilityLabel("Close advisories")
                    }

                    ForEach(alerts) { alert in
                        advisory(alert)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .colorScheme(.dark)
    }

    private func advisory(_ alert: WeatherAlert) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(alert.event)
                .font(.serif(.title3, weight: .semibold))
                .foregroundStyle(alert.isUrgent ? Color(hex: 0xFF9A8C) : Color(hex: 0xF5C46B))

            if let headline = alert.headline {
                Text(headline)
                    .font(.serif(.subheadline, italic: true))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if !alert.details.isEmpty {
                Text(alert.details)
                    .font(.serif(.body))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instruction = alert.instruction, !instruction.isEmpty {
                Text(instruction)
                    .font(.serif(.body, italic: true))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Text(alert.source)
                .font(.serif(.caption))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)

            Divider().overlay(Color.white.opacity(0.14))
        }
    }
}
