//
//  PrecipChanceCard.swift
//  Weather
//
//  Today's hourly chance-of-precipitation, drawn as a scrubbable bar chart for
//  the main screen — drag across it to read the odds at any hour.
//

import SwiftUI
import Charts

struct PrecipChanceCard: View {
    let bundle: WeatherBundle

    @State private var selected: HourPoint?

    private var hours: [HourPoint] { bundle.upcomingHours }
    private var precipColor: Color { Color(hex: 0x6FB8FF) }

    /// Peak chance across the window, for the header summary.
    private var peak: Double { hours.map(\.precipitationProbability).max() ?? 0 }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "umbrella.fill", title: "Chance of Rain")

                Chart {
                    ForEach(hours) { point in
                        BarMark(
                            x: .value("Time", point.date, unit: .hour),
                            y: .value("Chance", point.precipitationProbability)
                        )
                        .cornerRadius(3)
                        .foregroundStyle(
                            LinearGradient(colors: [precipColor, precipColor.opacity(0.25)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    }

                    if let selected {
                        // Guide rises to the selected bar's height; readout floats
                        // just above it (never clipped, never poking past the box).
                        RuleMark(x: .value("Time", selected.date),
                                 yStart: .value("Chance", 0),
                                 yEnd: .value("Chance", selected.precipitationProbability))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.6))
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart),
                                                                  y: .fit(to: .chart))) {
                                ScrubReadout(
                                    value: Fmt.percent(selected.precipitationProbability),
                                    caption: Fmt.hour(selected.date, timezone: bundle.timezone))
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let p = value.as(Int.self) {
                                Text("\(p)%")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.07))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Fmt.hour(date, timezone: bundle.timezone))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .frame(height: 164)
                .chartScrub(points: hours, selection: $selected)

                Text(peak < 5 ? "Dry through the next 24 hours"
                              : "Peak \(Fmt.percent(peak)) chance over the next 24 hours")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
