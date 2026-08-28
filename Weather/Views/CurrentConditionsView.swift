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
    /// The nowcast sentence ("Rain starting around 3:40"), shown only when
    /// precipitation is actually imminent.
    var nowcastLine: String? = nil

    private var current: CurrentWeather { bundle.current }

    var body: some View {
        VStack(spacing: 6) {
            Text(Fmt.longDate(current.date, timezone: bundle.timezone))
                .font(.serif(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            Text(bundle.place.name)
                .serifDisplay(36, weight: .medium)
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
                .font(.displaySerif(size: 104))
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.displaySerif(size: 66))
                        .foregroundStyle(.white)
                        .offset(x: 24, y: 7)
                }

            Text(current.condition.description)
                .font(.serif(.title3, italic: true))
                .foregroundStyle(.white.opacity(0.95))

            if let nowcastLine {
                HStack(spacing: 6) {
                    Image(systemName: "umbrella.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x9FD6FF))
                    Text(nowcastLine)
                        .font(.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .padding(.top, 2)
                .transition(.opacity)
            }

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
    }
}
