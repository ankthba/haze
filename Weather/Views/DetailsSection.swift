//
//  DetailsSection.swift
//  Weather
//
//  The conditions detail: two interactive feature blocks (wind, sun) followed by
//  a clean single-column list of metric rows separated by hairlines — minimal and
//  editorial, no boxes.
//

import SwiftUI

struct DetailsSection: View {
    let bundle: WeatherBundle
    let unit: TemperatureUnit
    let speedUnit: SpeedUnit
    var showWindCompass = true
    var showSunCard = true

    @State private var selectedMetric: MetricKind?

    private var current: CurrentWeather { bundle.current }
    private var today: DayForecast? { bundle.today }

    var body: some View {
        VStack(spacing: 30) {
            // Interactive feature blocks.
            if showWindCompass {
                Button {
                    Haptics.tap()
                    selectedMetric = .wind(speedUnit: speedUnit)
                } label: {
                    WindCompass(speed: current.windSpeed,
                                gust: current.windGust,
                                direction: current.windDirection,
                                speedUnit: speedUnit)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            if showSunCard {
                SunArcCard(sunrise: today?.sunrise,
                           sunset: today?.sunset,
                           now: Date(),
                           timezone: bundle.timezone)
            }

            // Everything else as its own full-width row.
            VStack(spacing: 0) {
                let uv = current.uvIndex ?? today?.uvIndexMax ?? 0

                metricRow("thermometer.medium", "Feels Like",
                          Fmt.temp(current.apparentTemperature), unit: unit.symbol,
                          caption: feelsLikeCaption, metric: .feelsLike(unit: unit))

                metricRow("humidity.fill", "Humidity",
                          Fmt.percent(current.humidity),
                          caption: "Relative humidity", metric: .humidity)

                metricRow("sun.max.trianglebadge.exclamationmark", "UV Index",
                          Fmt.temp(uv),
                          caption: Fmt.uvLabel(uv), metric: .uvIndex)

                metricRow("drop.fill", "Precipitation",
                          Fmt.precip(current.precipitation, unit: unit),
                          caption: "In the last hour", metric: .precipitation(unit: unit))

                metricRow("gauge.with.dots.needle.bottom.50percent", "Pressure",
                          Fmt.pressure(current.pressure), unit: Fmt.pressureUnit.label,
                          caption: pressureCaption)

                metricRow("cloud.fill", "Cloud Cover",
                          Fmt.percent(current.cloudCover),
                          caption: cloudCaption)

                if let dew = current.dewPoint {
                    metricRow("drop.degreesign.fill", "Dew Point",
                              Fmt.temp(dew), unit: unit.symbol,
                              caption: "Moisture in the air")
                }

                if let visibility = current.visibility {
                    metricRow("eye.fill", "Visibility",
                              Fmt.visibility(visibility, unit: unit),
                              caption: "How far you can see")
                }

                if let aqi = bundle.airQuality {
                    metricRow("aqi.medium", "Air Quality",
                              "\(aqi.usAQI)", unit: "AQI",
                              caption: aqi.category.rawValue)
                }
            }
        }
        .sheet(item: $selectedMetric) { metric in
            MetricDetailView(metric: metric, bundle: bundle, unit: unit)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func metricRow(_ icon: String, _ label: String, _ value: String,
                           unit: String? = nil, caption: String? = nil,
                           metric: MetricKind? = nil) -> some View {
        Button {
            guard let metric else { return }
            Haptics.tap()
            selectedMetric = metric
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.serif(.body, weight: .medium))
                        .foregroundStyle(.white)
                    if let caption {
                        Text(caption)
                            .font(.serif(.caption))
                            .foregroundStyle(.white.opacity(0.75))
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
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                // Chevron marks rows that open a detail page; the space is
                // reserved on every row so the values stay aligned.
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(metric == nil ? 0 : 0.3))
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(metric == nil)
    }

    // MARK: - Captions

    private var feelsLikeCaption: String {
        let delta = current.apparentTemperature - current.temperature
        if abs(delta) < 1 { return "Similar to actual" }
        return delta > 0 ? "Warmer than actual" : "Cooler than actual"
    }

    private var pressureCaption: String {
        switch current.pressure {
        case ..<1000: return "Low, unsettled"
        case 1000..<1020: return "Steady"
        default: return "High, fair"
        }
    }

    private var cloudCaption: String {
        switch current.cloudCover {
        case ..<20: return "Mostly clear"
        case 20..<70: return "Partly cloudy"
        default: return "Overcast"
        }
    }
}
