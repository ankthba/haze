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

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        return cal
    }

    /// Local midnights inside the plotted window. Three days of weather read as
    /// one undifferentiated wave without them: the axis was striding every 12
    /// hours from an arbitrary anchor, so it printed "5PM 5AM 5PM 5AM" and left
    /// readers to work out whether that was one day repeating or three.
    private var dayBoundaries: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: first)
        while cursor <= last {
            if cursor > first { result.append(cursor) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Ticks on the day's own landmarks — midnight and midday — rather than a
    /// stride that lands wherever the window happens to start.
    private var axisTicks: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        var ticks: [Date] = []
        var cursor = calendar.startOfDay(for: first)
        while cursor <= last {
            for hour in [0, 12] {
                if let tick = calendar.date(byAdding: .hour, value: hour, to: cursor),
                   tick >= first, tick <= last {
                    ticks.append(tick)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }

    private func isDayBoundary(_ date: Date) -> Bool {
        calendar.component(.hour, from: date) == 0
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

                    // The day separators themselves: a hairline the eye reads
                    // as a division without competing with the curve.
                    ForEach(dayBoundaries, id: \.self) { midnight in
                        RuleMark(x: .value("Day", midnight))
                            .lineStyle(StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(.white.opacity(0.28))
                    }

                    if let now = points.first {
                        RuleMark(x: .value("Now", now.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let selected {
                        // Lollipop: the guide line rises only to the selected
                        // value and the readout floats just above the dot — so the
                        // line never pokes above the box and the dot never overlaps it.
                        RuleMark(x: .value("Time", selected.date),
                                 yStart: .value("Base", tempRange.lowerBound),
                                 yEnd: .value("Temp", selected.temperature))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.75))
                        PointMark(x: .value("Time", selected.date),
                                  y: .value("Temp", selected.temperature))
                            .foregroundStyle(.white)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart),
                                                                  y: .fit(to: .chart))) {
                                ScrubReadout(
                                    value: Fmt.tempDegree(selected.temperature),
                                    caption: scrubCaption(for: selected.date),
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
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisTicks) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.07))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                // The day's name carries the weight; the noon
                                // tick is just a foothold between them.
                                let boundary = isDayBoundary(date)
                                Text(boundary
                                     ? Fmt.weekday(date, timezone: bundle.timezone)
                                     : Fmt.hour(date, timezone: bundle.timezone))
                                    .font(.serif(.caption2,
                                                 weight: boundary ? .semibold : .regular))
                                    .foregroundStyle(.white.opacity(boundary ? 0.95 : 0.6))
                            }
                        }
                    }
                }
                .frame(height: 184)
                .chartScrub(points: points, selection: $selected)
            }
        }
    }

    /// "1 PM" when that is unambiguous, "Tue 1 PM" once the reader could be
    /// looking at any of three days.
    private func scrubCaption(for date: Date) -> String {
        let hour = Fmt.hour(date, timezone: bundle.timezone)
        guard !calendar.isDateInToday(date) else { return hour }
        return "\(Fmt.weekday(date, timezone: bundle.timezone)) \(hour)"
    }

    /// Map precip probability (0–100) into the temperature scale for the underlay bars.
    private func precipHeight(for point: HourPoint) -> Double {
        let fraction = point.precipitationProbability / 100
        let span = tempRange.upperBound - tempRange.lowerBound
        return tempRange.lowerBound + fraction * span * 0.4
    }
}
