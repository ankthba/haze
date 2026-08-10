//
//  TemperatureTrendCard.swift
//  Weather
//
//  48-hour temperature curve with a precipitation-probability underlay,
//  drawn with Swift Charts.
//

import SwiftUI
import Charts

struct TemperatureTrendCard: View {
    let bundle: WeatherBundle
    let accent: Color
    /// When false, the precipitation underlay is omitted (e.g. the dedicated rain
    /// card is already showing today's chance, so we avoid drawing it twice).
    var showPrecip: Bool = true

    @State private var selected: HourPoint?

    private var points: [HourPoint] {
        let now = Date().addingTimeInterval(-3600)
        let start = bundle.hourly.firstIndex { $0.date >= now } ?? 0
        return Array(bundle.hourly[start...].prefix(72))
    }

    private var tempRange: ClosedRange<Double> {
        let temps = points.map(\.temperature)
        let lo = (temps.min() ?? 0) - 6
        let hi = (temps.max() ?? 30) + 6
        return lo...hi
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "chart.line.uptrend.xyaxis", title: "72-Hour Trend")

                Chart {
                    ForEach(points) { point in
                        // Precipitation probability as a soft underlay (right axis scale 0–100).
                        if showPrecip, point.precipitationProbability > 0 {
                            BarMark(
                                x: .value("Time", point.date),
                                yStart: .value("Base", tempRange.lowerBound),
                                yEnd: .value("Precip", precipHeight(for: point)),
                                width: .fixed(6)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: 0x7FC4FF).opacity(0.45), .clear],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .clipShape(Capsule())
                        }
                    }

                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Base", tempRange.lowerBound),
                            yEnd: .value("Temp", point.temperature)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Temp", point.temperature)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, accent],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    }

                    if let now = points.first {
                        RuleMark(x: .value("Now", now.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    if let selected {
                        // Lollipop: the guide line rises only to the selected
                        // value and the readout floats just above the dot — so the
                        // line never pokes above the box and the dot never overlaps it.
                        RuleMark(x: .value("Time", selected.date),
                                 yStart: .value("Base", tempRange.lowerBound),
                                 yEnd: .value("Temp", selected.temperature))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.55))
                        PointMark(x: .value("Time", selected.date),
                                  y: .value("Temp", selected.temperature))
                            .foregroundStyle(.white)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart),
                                                                  y: .fit(to: .chart))) {
                                ScrubReadout(
                                    value: Fmt.tempDegree(selected.temperature),
                                    caption: Fmt.hour(selected.date, timezone: bundle.timezone),
                                    detail: selected.precipitationProbability >= 10
                                        ? "\(Fmt.percent(selected.precipitationProbability)) rain"
                                        : nil)
                            }
                    }
                }
                .chartYScale(domain: tempRange)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let t = value.as(Double.self) {
                                Text(Fmt.tempDegree(t))
                                    .font(.serif(.caption2))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 12)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.07))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Fmt.hour(date, timezone: bundle.timezone))
                                    .font(.serif(.caption2))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .frame(height: 184)
                .chartScrub(points: points, selection: $selected)
            }
        }
    }

    /// Map precip probability (0–100) into the temperature scale for the underlay bars.
    private func precipHeight(for point: HourPoint) -> Double {
        let fraction = point.precipitationProbability / 100
        let span = tempRange.upperBound - tempRange.lowerBound
        return tempRange.lowerBound + fraction * span * 0.4
    }
}
