//
//  DayDetailView.swift
//  Weather
//
//  Full breakdown for a single day tapped from the 10-day list: hero summary,
//  an hourly curve + strip (when within the forecast window), sun times, and a
//  grid of conditions detail.
//

import SwiftUI
import Charts

struct DayDetailView: View {
    let day: DayForecast
    let bundle: WeatherBundle
    let unit: TemperatureUnit
    let speedUnit: SpeedUnit

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemp: HourPoint?
    @State private var selectedPrecip: HourPoint?

    private var timezone: TimeZone { bundle.timezone }

    private var hours: [HourPoint] { bundle.hours(on: day.date) }

    private var noon: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day.date) ?? day.date
    }

    var body: some View {
        ZStack {
            SkyBackground(condition: day.condition,
                          now: noon,
                          sunrise: day.sunrise,
                          sunset: day.sunset)

            ScrollView {
                VStack(spacing: 20) {
                    header

                    if !hours.isEmpty {
                        hourlyCurve
                        precipChart
                        hourlyStrip
                    }

                    DayMetricsGrid(day: day, hours: hours, timezone: timezone,
                                   unit: unit, speedUnit: speedUnit)
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
            Text(Fmt.longDate(day.date, timezone: timezone))
                .font(.serif(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Image(systemName: day.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 56))
                .padding(.vertical, 2)

            Text(day.condition.description)
                .font(.serif(.title2, italic: true))
                .foregroundStyle(.white)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text(Fmt.tempDegree(day.tempMax))
                        .font(.serif(.largeTitle))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    Text(Fmt.tempDegree(day.tempMin))
                        .font(.serif(.largeTitle))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Hourly curve

    private var tempRange: ClosedRange<Double> {
        let temps = hours.map(\.temperature)
        let lo = (temps.min() ?? day.tempMin) - 5
        let hi = (temps.max() ?? day.tempMax) + 5
        return lo...hi
    }

    private var hourlyCurve: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "chart.line.uptrend.xyaxis", title: "Hourly Temperature")

                Chart(hours) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Base", tempRange.lowerBound),
                        yEnd: .value("Temp", point.temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [day.condition.accent.opacity(0.35),
                                                day.condition.accent.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", point.temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, day.condition.accent],
                                       startPoint: .leading, endPoint: .trailing)
                    )

                    if let selectedTemp {
                        RuleMark(x: .value("Time", selectedTemp.date),
                                 yStart: .value("Base", tempRange.lowerBound),
                                 yEnd: .value("Temp", selectedTemp.temperature))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.55))
                        PointMark(x: .value("Time", selectedTemp.date),
                                  y: .value("Temp", selectedTemp.temperature))
                            .foregroundStyle(.white)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart),
                                                                  y: .fit(to: .chart))) {
                                ScrubReadout(
                                    value: Fmt.tempDegree(selectedTemp.temperature),
                                    caption: Fmt.hour(selectedTemp.date, timezone: timezone))
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
                .frame(height: 174)
                .chartScrub(points: hours, selection: $selectedTemp)
            }
        }
    }

    // MARK: - Precipitation chart

    private var precipColor: Color { Color(hex: 0x6FB8FF) }

    /// Total liquid expected across the day's hours.
    private var precipTotal: Double { hours.reduce(0) { $0 + $1.precipitation } }

    private var precipChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "umbrella.fill", title: "Chance of Precipitation")

                Chart(hours) { point in
                    BarMark(
                        x: .value("Time", point.date, unit: .hour),
                        y: .value("Chance", point.precipitationProbability)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(
                        LinearGradient(colors: [precipColor, precipColor.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                    if let selectedPrecip {
                        RuleMark(x: .value("Time", selectedPrecip.date),
                                 yStart: .value("Chance", 0),
                                 yEnd: .value("Chance", selectedPrecip.precipitationProbability))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.6))
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart),
                                                                  y: .fit(to: .chart))) {
                                ScrubReadout(
                                    value: Fmt.percent(selectedPrecip.precipitationProbability),
                                    caption: Fmt.hour(selectedPrecip.date, timezone: timezone),
                                    detail: Fmt.precip(selectedPrecip.precipitation, unit: unit))
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
                .frame(height: 164)
                .chartScrub(points: hours, selection: $selectedPrecip)

                if precipTotal > 0 {
                    Text("\(Fmt.precip(precipTotal, unit: unit)) expected total")
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("No precipitation expected")
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var hourlyStrip: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "clock", title: "By the Hour")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(hours) { hour in
                            VStack(spacing: 10) {
                                Text(Fmt.hour(hour.date, timezone: timezone))
                                    .font(.serif(.subheadline, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Image(systemName: hour.condition.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 21))
                                    .frame(height: 24)
                                if hour.precipitationProbability >= 10 {
                                    Text(Fmt.percent(hour.precipitationProbability))
                                        .font(.serif(size: 13, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x9FD6FF))
                                } else {
                                    Text(" ").font(.serif(size: 13, weight: .semibold))
                                }
                                Text(Fmt.tempDegree(hour.temperature))
                                    .font(.serif(.title3))
                                    .foregroundStyle(.white)
                            }
                            .frame(minWidth: 40)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .horizontalFadeEdges()
            }
        }
    }
}

// MARK: - Metrics grid

private struct DayMetricsGrid: View {
    let day: DayForecast
    let hours: [HourPoint]
    let timezone: TimeZone
    let unit: TemperatureUnit
    let speedUnit: SpeedUnit

    private var avgHumidity: Double? {
        guard !hours.isEmpty else { return nil }
        return hours.map(\.humidity).reduce(0, +) / Double(hours.count)
    }

    /// Length of day from sunrise to sunset, e.g. "13h 24m".
    private var daylight: String? {
        guard let sunrise = day.sunrise, let sunset = day.sunset, sunset > sunrise
        else { return nil }
        let minutes = Int(sunset.timeIntervalSince(sunrise) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            row("sunrise.fill", "Sunrise",
                day.sunrise.map { Fmt.time($0, timezone: timezone) } ?? "—")
            row("sunset.fill", "Sunset",
                day.sunset.map { Fmt.time($0, timezone: timezone) } ?? "—")
            row("sun.horizon.fill", "Daylight", daylight ?? "—",
                caption: "Sunrise to sunset")
            row("sun.max.trianglebadge.exclamationmark", "UV Index",
                Fmt.temp(day.uvIndexMax), caption: Fmt.uvLabel(day.uvIndexMax))
            row("umbrella.fill", "Precip Chance",
                Fmt.percent(day.precipitationProbabilityMax), caption: "Peak through the day")
            row("drop.fill", "Precip Total", Fmt.precip(day.precipitationSum, unit: unit))
            row("wind", "Wind", Fmt.speed(day.windSpeedMax), unit: speedUnit.label,
                caption: "From \(Fmt.windDirectionLabel(day.windDirectionDominant))")
            row("wind.circle", "Gusts", Fmt.speed(day.windGustMax), unit: speedUnit.label)
            row("thermometer.medium", "Feels Like", Fmt.tempDegree(day.apparentMax),
                caption: "Low \(Fmt.tempDegree(day.apparentMin))")
            if let humidity = avgHumidity {
                row("humidity.fill", "Humidity", Fmt.percent(humidity), caption: "Average")
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String,
                     unit: String? = nil, caption: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.serif(.body, weight: .medium))
                    .foregroundStyle(.white)
                if let caption {
                    Text(caption)
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.serif(.title2))
                    .foregroundStyle(.white)
                if let unit {
                    Text(unit)
                        .font(.serif(.subheadline, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
        }
    }
}
