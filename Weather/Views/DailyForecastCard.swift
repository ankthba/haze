//
//  DailyForecastCard.swift
//  Weather
//
//  10-day outlook with proportional temperature-range bars and today's
//  reading marked on the bar, à la Apple Weather.
//

import SwiftUI

struct DailyForecastCard: View {
    let bundle: WeatherBundle
    let accent: Color
    var onSelect: (DayForecast) -> Void = { _ in }

    private var days: [DayForecast] { bundle.daily }

    /// Overall min/max across the range, for proportional bar scaling.
    private var globalRange: (min: Double, max: Double) {
        let mins = days.map(\.tempMin)
        let maxs = days.map(\.tempMax)
        return (mins.min() ?? 0, maxs.max() ?? 1)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(systemImage: "calendar", title: "10-Day Forecast")

                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        Button {
                            Haptics.tap(.medium)
                            onSelect(day)
                        } label: {
                            DayRow(
                                day: day,
                                isToday: index == 0,
                                timezone: bundle.timezone,
                                globalMin: globalRange.min,
                                globalMax: globalRange.max,
                                currentTemp: index == 0 ? bundle.current.temperature : nil,
                                accent: accent
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < days.count - 1 {
                            Divider().overlay(.white.opacity(0.1))
                        }
                    }
                }
            }
        }
    }
}

private struct DayRow: View {
    let day: DayForecast
    let isToday: Bool
    let timezone: TimeZone
    let globalMin: Double
    let globalMax: Double
    let currentTemp: Double?
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : Fmt.weekday(day.date, timezone: timezone))
                    .font(.serif(.body))
                    .foregroundStyle(.white)
                if day.precipitationProbabilityMax >= 20 {
                    Text(Fmt.percent(day.precipitationProbabilityMax))
                        .font(.serif(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x9FD6FF))
                }
            }
            .frame(width: 58, alignment: .leading)

            Image(systemName: day.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 19))
                .frame(width: 28)

            Text(Fmt.tempDegree(day.tempMin))
                .font(.serif(.body))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 32, alignment: .trailing)

            TemperatureRangeBar(
                dayMin: day.tempMin,
                dayMax: day.tempMax,
                globalMin: globalMin,
                globalMax: globalMax,
                currentTemp: currentTemp
            )
            .frame(maxWidth: .infinity)
            .frame(height: 6)

            Text(Fmt.tempDegree(day.tempMax))
                .font(.serif(.body))
                .foregroundStyle(.white)
                .frame(width: 34, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
    }
}

private struct TemperatureRangeBar: View {
    let dayMin: Double
    let dayMax: Double
    let globalMin: Double
    let globalMax: Double
    let currentTemp: Double?

    var body: some View {
        GeometryReader { geo in
            let span = max(globalMax - globalMin, 1)
            let startFraction = (dayMin - globalMin) / span
            let endFraction = (dayMax - globalMin) / span
            let width = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x6FB8FF), Color(hex: 0xFFD66B),
                                     Color(hex: 0xFF8E6B)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(width * (endFraction - startFraction), 6))
                    .offset(x: width * startFraction)

                if let current = currentTemp {
                    let fraction = min(max((current - globalMin) / span, 0), 1)
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                        .offset(x: width * fraction - 3.5)
                }
            }
        }
    }
}
