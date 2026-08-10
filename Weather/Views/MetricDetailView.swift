//
//  MetricDetailView.swift
//  Weather
//
//  Tap a metric card on the main screen to open this sheet: the chosen metric
//  charted across the upcoming forecast hours, scrubbable by dragging to read
//  the value at any hour.
//

import SwiftUI
import Charts

// MARK: - Metric kind

/// Describes a single tappable metric — its identity, styling, how to read its
/// value out of an `HourPoint`, and how to format that value for display.
struct MetricKind: Identifiable {
    enum Style { case line, bar }

    let id: String
    let title: String
    let symbol: String
    let accent: Color
    /// Pulls this metric's value out of an hourly point.
    let value: (HourPoint) -> Double
    /// Renders a value as a display string (e.g. "62%", "8 mph", "71°").
    let format: (Double) -> String
    let style: Style

    static func wind(speedUnit: SpeedUnit) -> MetricKind {
        MetricKind(id: "wind",
                   title: "Wind",
                   symbol: "wind",
                   accent: Color(hex: 0x7FC4FF),
                   value: { $0.windSpeed },
                   format: { "\(Fmt.speed($0)) \(speedUnit.label)" },
                   style: .line)
    }

    static func feelsLike(unit: TemperatureUnit) -> MetricKind {
        MetricKind(id: "feelsLike",
                   title: "Feels Like",
                   symbol: "thermometer.medium",
                   accent: Color(hex: 0xF4A65E),
                   value: { $0.apparentTemperature },
                   format: { Fmt.tempDegree($0) },
                   style: .line)
    }

    static let humidity = MetricKind(
        id: "humidity",
        title: "Humidity",
        symbol: "humidity.fill",
        accent: Color(hex: 0x6FD3C4),
        value: { $0.humidity },
        format: { Fmt.percent($0) },
        style: .line)

    static let uvIndex = MetricKind(
        id: "uvIndex",
        title: "UV Index",
        symbol: "sun.max.trianglebadge.exclamationmark",
        accent: Color(hex: 0xF4D03F),
        value: { $0.uvIndex },
        format: { Fmt.temp($0) },
        style: .line)

    static func precipitation(unit: TemperatureUnit) -> MetricKind {
        MetricKind(id: "precipitation",
                   title: "Precipitation",
                   symbol: "drop.fill",
                   accent: Color(hex: 0x6FB8FF),
                   value: { $0.precipitationProbability },
                   format: { Fmt.percent($0) },
                   style: .bar)
    }
}

// MARK: - Detail sheet

struct MetricDetailView: View {
    let metric: MetricKind
    let bundle: WeatherBundle
    let unit: TemperatureUnit

    @Environment(\.dismiss) private var dismiss
    @State private var selected: HourPoint?

    private var timezone: TimeZone { bundle.timezone }

    /// A useful forward window: the next 24 hours of the forecast.
    private var hours: [HourPoint] { bundle.upcomingHours }

    private var values: [Double] { hours.map(metric.value) }

    var body: some View {
        ZStack {
            SkyBackground(condition: bundle.current.condition,
                          now: Date(),
                          sunrise: bundle.today?.sunrise,
                          sunset: bundle.today?.sunset)

            ScrollView {
                VStack(spacing: 20) {
                    header
                    chartCard
                    if metric.id == "wind" {
                        windDirectionCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 44) }

            // Content dissolves into the status bar instead of colliding with it.
            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)

            topBar
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(CardButtonStyle())
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Next 24 hours")
                .font(.serif(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Image(systemName: metric.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 46))
                .foregroundStyle(.white)
                .padding(.vertical, 2)

            Text(metric.title)
                .font(.serif(.title2, italic: true))
                .foregroundStyle(.white)

            if let first = hours.first {
                Text(metric.format(metric.value(first)))
                    .font(.serif(.largeTitle))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: metric.symbol, title: "Hourly \(metric.title)")

                chart
                    .frame(height: 184)
                    .chartScrub(points: hours, selection: $selected)

                summaryRow
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(hours) { point in
                let v = metric.value(point)
                switch metric.style {
                case .line:
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Base", domain.lowerBound),
                        yEnd: .value(metric.title, v)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [metric.accent.opacity(0.35),
                                                metric.accent.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(metric.title, v)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, metric.accent],
                                       startPoint: .leading, endPoint: .trailing)
                    )

                case .bar:
                    BarMark(
                        x: .value("Time", point.date, unit: .hour),
                        y: .value(metric.title, v)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(
                        LinearGradient(colors: [metric.accent, metric.accent.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }

            if let selected {
                let v = metric.value(selected)
                // Guide rises only to the value; the readout floats just above it.
                RuleMark(x: .value("Time", selected.date),
                         yStart: .value("Base", domain.lowerBound),
                         yEnd: .value(metric.title, v))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.55))
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart),
                                                          y: .fit(to: .chart))) {
                        ScrubReadout(value: metric.format(v),
                                     caption: Fmt.hour(selected.date, timezone: timezone))
                    }
                if metric.style == .line {
                    PointMark(x: .value("Time", selected.date),
                              y: .value(metric.title, v))
                        .foregroundStyle(.white)
                        .symbolSize(70)
                }
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric.format(v))
                            .font(.serif(.caption2))
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
                        Text(Fmt.hour(date, timezone: timezone))
                            .font(.serif(.caption2))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    /// Y domain padded a little above/below the series so the curve breathes.
    private var domain: ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        switch metric.style {
        case .bar:
            // Probabilities sit on a fixed 0–100 scale.
            return 0...100
        case .line:
            if lo == hi { return (lo - 1)...(hi + 1) }
            let pad = (hi - lo) * 0.15
            return (lo - pad)...(hi + pad)
        }
    }

    // MARK: - Wind direction

    /// A horizontal strip of per-hour arrows showing the way the wind blows,
    /// shown only on the Wind detail sheet.
    private var windDirectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "location.north.line.fill", title: "Wind Direction")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(hours) { hour in
                            VStack(spacing: 7) {
                                Text(Fmt.hour(hour.date, timezone: timezone))
                                    .font(.serif(.caption2))
                                    .foregroundStyle(.white.opacity(0.6))

                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.white, metric.accent],
                                                       startPoint: .top, endPoint: .bottom)
                                    )
                                    // windDirection is the bearing the wind comes FROM,
                                    // so add 180° to point the way it blows TO.
                                    .rotationEffect(.degrees(hour.windDirection + 180))
                                    .frame(height: 22)

                                Text(Fmt.windDirectionLabel(hour.windDirection))
                                    .font(.serif(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))

                                Text(Fmt.speed(hour.windSpeed))
                                    .font(.serif(.caption2))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .horizontalFadeEdges()

                Text("Arrows show the way the wind blows.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            if let first = hours.first {
                stat("Now", metric.value(first))
            }
            if let lo = values.min() { divider; stat("Min", lo) }
            if let hi = values.max() { divider; stat("Max", hi) }
            if !values.isEmpty {
                divider
                stat("Avg", values.reduce(0, +) / Double(values.count))
            }
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.serif(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(metric.format(value))
                .font(.serif(.title3))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 0.6, height: 28)
    }
}
