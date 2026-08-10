//
//  CurrentConditionsView.swift
//  Weather
//
//  The hero: location, oversized serif temperature, condition, and today's range.
//

import SwiftUI

struct CurrentConditionsView: View {
    let bundle: WeatherBundle
    let unit: TemperatureUnit

    private var current: CurrentWeather { bundle.current }

    var body: some View {
        VStack(spacing: 8) {
            Text(Fmt.longDate(current.date, timezone: bundle.timezone))
                .font(.serif(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.bottom, 2)

            Text(bundle.place.name)
                .serifDisplay(38, weight: .medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if !bundle.place.subtitle.isEmpty {
                Text(bundle.place.subtitle)
                    .font(.serif(.subheadline, italic: true))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            // Oversized temperature. The degree sign is an overlay so it doesn't
            // count toward layout width — that keeps the *number* optically
            // centered rather than the number+degree as a unit.
            Text(Fmt.temp(current.temperature))
                .font(.displaySerif(size: 116))
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.displaySerif(size: 74))
                        .foregroundStyle(.white)
                        .offset(x: 26, y: 8)
                }
                .padding(.top, 2)

            Text(current.condition.description)
                .font(.serif(.title3, italic: true))
                .foregroundStyle(.white.opacity(0.95))

            HStack(spacing: 16) {
                Label(Fmt.tempDegree(bundle.today?.tempMax ?? current.temperature),
                      systemImage: "arrow.up")
                Label(Fmt.tempDegree(bundle.today?.tempMin ?? current.temperature),
                      systemImage: "arrow.down")
                Text("Feels \(Fmt.tempDegree(current.apparentTemperature))")
            }
            .font(.serif(.callout))
            .foregroundStyle(.white.opacity(0.88))
            .labelStyle(.titleAndIcon)
            .padding(.top, 2)
        }
        .skyReadable()
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
