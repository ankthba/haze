//
//  WindCompass.swift
//  Weather
//
//  A compass dial showing wind direction + speed, plus gusts.
//

import SwiftUI

struct WindCompass: View {
    let speed: Double
    let gust: Double
    let direction: Double
    let speedUnit: SpeedUnit

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(systemImage: "wind", title: "Wind")

                HStack(spacing: 16) {
                    dial
                        .frame(width: 104, height: 104)

                    Spacer(minLength: 12)

                    VStack(alignment: .leading, spacing: 12) {
                        reading(title: "Wind", value: Fmt.speed(speed))
                        reading(title: "Gusts", value: Fmt.speed(gust))
                        reading(title: "From", value: Fmt.windDirectionLabel(direction), unitless: true)
                    }
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reading(title: String, value: String, unitless: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.serif(.body))
                .foregroundStyle(.white)
            if !unitless {
                Text(speedUnit.label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var dial: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 1)

            ForEach(0..<12) { i in
                Rectangle()
                    .fill(.white.opacity(i % 3 == 0 ? 0.5 : 0.22))
                    .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 9 : 5)
                    .offset(y: -44)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }

            VStack {
                Text("N").font(.system(size: 10, weight: .bold))
                Spacer()
                Text("S").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(height: 74)

            HStack {
                Text("W").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("E").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 74)

            // Direction arrow (points the way the wind blows toward). Offset out
            // toward the rim so it orbits the center readout instead of covering it.
            Image(systemName: "location.north.fill")
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(hex: 0x9FD6FF)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .offset(y: -30)
                .rotationEffect(.degrees(direction + 180))

            VStack(spacing: 0) {
                Text(Fmt.speed(speed))
                    .font(.serif(size: 18))
                Text(speedUnit.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
        }
    }
}
