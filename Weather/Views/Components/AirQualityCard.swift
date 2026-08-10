//
//  AirQualityCard.swift
//  Weather
//
//  US AQI with a position indicator on the standard color scale.
//

import SwiftUI

struct AirQualityCard: View {
    let airQuality: AirQuality

    private let scaleColors: [Color] = [
        Color(hex: 0x4CC97E), // good
        Color(hex: 0xF4D03F), // moderate
        Color(hex: 0xF39C3D), // sensitive
        Color(hex: 0xE74C3C), // unhealthy
        Color(hex: 0x9B59B6), // very unhealthy
        Color(hex: 0x7E1E2B)  // hazardous
    ]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(systemImage: "aqi.medium", title: "Air Quality")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(airQuality.usAQI)")
                        .font(.serif(.title))
                        .foregroundStyle(.white)
                    Text("US AQI")
                        .font(.serif(.subheadline, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text(airQuality.category.rawValue)
                    .font(.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                GeometryReader { geo in
                    let fraction = min(Double(airQuality.usAQI) / 300, 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: scaleColors,
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 6)
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 0.5))
                            .offset(x: geo.size.width * fraction - 5.5)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 14)

                if let pm25 = airQuality.pm25 {
                    Text("PM2.5  \(String(format: "%.0f", pm25)) µg/m³")
                        .font(.serif(.footnote))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
    }
}
