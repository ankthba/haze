//
//  ShareCard.swift
//  Weather
//
//  A shareable page: today's forecast composed as a 4:5 editorial card — the
//  place's sky gradient, oversized serif temperature, and the masthead. The
//  PNG renders lazily via Transferable, only when a share actually happens.
//

import SwiftUI
import UniformTypeIdentifiers

/// The share payload. Rendering happens inside the export closure, so opening
/// the share sheet costs nothing until a destination is picked.
struct ForecastShareCard: Transferable {
    let bundle: WeatherBundle

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await MainActor.run { try card.renderPNG() }
        }
        .suggestedFileName { "Haze – \($0.bundle.place.name).png" }
    }

    @MainActor
    private func renderPNG() throws -> Data {
        let renderer = ImageRenderer(content: ShareCardView(bundle: bundle))
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 450)
        guard let data = renderer.uiImage?.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

/// The card itself — a quiet page from the magazine.
struct ShareCardView: View {
    let bundle: WeatherBundle

    private var condition: WeatherCondition { bundle.current.condition }

    private var skyColors: [Color] {
        let phase = DayPhase.current(now: bundle.current.date,
                                     sunrise: bundle.today?.sunrise,
                                     sunset: bundle.today?.sunset,
                                     isDay: condition.isDay)
        return SkyPalette.gradientHexes(phase: phase, kind: condition.kind)
            .map { Color(hex: $0) }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
            Color.black.opacity(0.24)

            VStack(spacing: 7) {
                Spacer(minLength: 30)

                Text(Fmt.longDate(bundle.current.date, timezone: bundle.timezone))
                    .font(.serif(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                Text(bundle.place.name)
                    .font(.serif(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 24)

                Text(Fmt.temp(bundle.current.temperature))
                    .font(.displaySerif(size: 128))
                    .foregroundStyle(.white)
                    .overlay(alignment: .topTrailing) {
                        Text("°")
                            .font(.displaySerif(size: 72))
                            .foregroundStyle(.white)
                            .offset(x: 26, y: 12)
                    }

                Text(condition.description)
                    .font(.serif(size: 21, italic: true))
                    .foregroundStyle(.white.opacity(0.95))

                if let today = bundle.today {
                    HStack(spacing: 14) {
                        Label(Fmt.tempDegree(today.tempMax), systemImage: "arrow.up")
                        Label(Fmt.tempDegree(today.tempMin), systemImage: "arrow.down")
                    }
                    .font(.serif(size: 16))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 2)
                }

                Spacer(minLength: 24)

                // Colophon.
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 40, height: 1)
                Text("Haze")
                    .font(.displaySerif(size: 24))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 360, height: 450)
    }
}
