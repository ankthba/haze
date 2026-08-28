//
//  HourlyForecastCard.swift
//  Weather
//
//  Scrolling 24-hour strip with condition symbols, precip chance, and temps.
//

import SwiftUI

struct HourlyForecastCard: View {
    let bundle: WeatherBundle

    private var hours: [HourPoint] { bundle.upcomingHours }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "clock", title: "Hourly Forecast")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                            HourColumn(hour: hour,
                                       timezone: bundle.timezone,
                                       isNow: index == 0)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                // One soft tick per hour column gliding by (42pt min + 22 gap).
                .scrollTickHaptics(every: 64)
                .horizontalFadeEdges()
            }
        }
    }
}

private struct HourColumn: View {
    let hour: HourPoint
    let timezone: TimeZone
    let isNow: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(isNow ? "Now" : Fmt.hour(hour.date, timezone: timezone))
                .font(.serif(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            Image(systemName: hour.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 22))
                .frame(height: 26)

            if hour.precipitationProbability >= 10 {
                Text(Fmt.percent(hour.precipitationProbability))
                    .font(.serif(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x9FD6FF))
            } else {
                Text(" ")
                    .font(.serif(size: 13, weight: .semibold))
            }

            Text(Fmt.tempDegree(hour.temperature))
                .font(.serif(.title3))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 42)
        // One VoiceOver stop per hour, with every value in context — not four
        // floating fragments ("3PM", a symbol, "30%", "72°") per column.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [isNow ? "Now" : Fmt.hour(hour.date, timezone: timezone),
                     hour.condition.description]
        if hour.precipitationProbability >= 10 {
            parts.append("\(Fmt.percent(hour.precipitationProbability)) chance of precipitation")
        }
        parts.append(Fmt.tempDegree(hour.temperature))
        return parts.joined(separator: ", ")
    }
}
