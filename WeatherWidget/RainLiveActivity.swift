//
//  RainLiveActivity.swift
//  WeatherWidget
//
//  The rain Live Activity, drawn in the app's own clothes: EB Garamond on the
//  place's real sky gradient, with the shower's shape as a soft filled curve
//  and a time axis that actually lines up with it.
//
//  Everything here is presentation — the app composes the strings, the colours
//  and the geometry, because it owns the timezone, the clock format and the
//  palette. The attributes struct mirrors the app's copy in
//  `Weather/Services/RainActivity.swift` — keep the two byte-identical.
//

import WidgetKit
import SwiftUI
import ActivityKit

nonisolated struct RainActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let headline: String
        let detail: String
        let intensities: [Double]
        let axisLabels: [String]
        let startFraction: Double?
        let skyHexes: [UInt]
        let beginsAt: Date?
    }
    let placeName: String
}

private let rainBlue = Color(hex: 0x9FD6FF)

struct RainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainActivityAttributes.self) { context in
            LockScreenRain(state: context.state, place: context.attributes.placeName)
                .activityBackgroundTint(nil)   // the view paints its own sky
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.placeName)
                        .font(.serif(14))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "umbrella.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(rainBlue)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(context.state.headline)
                            .font(.serif(20))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        RainShape(intensities: context.state.intensities,
                                  startFraction: context.state.startFraction)
                            .frame(height: 30)

                        TimeAxis(labels: context.state.axisLabels)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "umbrella.fill")
                    .foregroundStyle(rainBlue)
            } compactTrailing: {
                // A fixed time, never a ticking clock — the compact slot is far
                // too narrow for one, which is what produced "2:25…".
                if let begins = context.state.beginsAt {
                    Text(begins, style: .time)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rainBlue)
                } else {
                    RainShape(intensities: context.state.intensities, startFraction: nil)
                        .frame(width: 26, height: 14)
                }
            } minimal: {
                Image(systemName: "umbrella.fill")
                    .foregroundStyle(rainBlue)
            }
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenRain: View {
    let state: RainActivityAttributes.ContentState
    let place: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.headline)
                    .font(.serif(21))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(state.detail.isEmpty ? place : state.detail)
                    .font(.serif(13, italic: true))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer(minLength: 6)

                RainShape(intensities: state.intensities,
                          startFraction: state.startFraction)
                    .frame(height: 34)

                TimeAxis(labels: state.axisLabels)
            }

            Image(systemName: "umbrella.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(rainBlue)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The place's own sky, same palette as the app, deepened so white
            // type sits on it comfortably.
            LinearGradient(colors: state.skyHexes.map { Color(hex: $0) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Color.black.opacity(0.34))
        }
    }
}

// MARK: - The shower

/// The next three hours as a soft filled curve rather than a row of stubs: a
/// dry stretch reads as a flat baseline, a squall as a hump. A hairline marks
/// the moment rain arrives, positioned where it actually falls in the window.
private struct RainShape: View {
    let intensities: [Double]
    let startFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let points = curve(in: geo.size)

            ZStack(alignment: .topLeading) {
                // Baseline so an empty stretch still reads as a timeline.
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(height: 2)
                    .offset(y: height - 2)

                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [rainBlue.opacity(0.85), rainBlue.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))

                    Path { path in
                        for (index, point) in points.enumerated() {
                            index == 0 ? path.move(to: point) : path.addLine(to: point)
                        }
                    }
                    .stroke(rainBlue, style: StrokeStyle(lineWidth: 1.8,
                                                         lineCap: .round, lineJoin: .round))
                }

                if let startFraction, startFraction > 0.02, startFraction < 0.98 {
                    Rectangle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 1, height: height)
                        .offset(x: width * startFraction)
                }
            }
        }
    }

    private func curve(in size: CGSize) -> [CGPoint] {
        guard intensities.count > 1 else { return [] }
        let step = size.width / CGFloat(intensities.count - 1)
        // A floor keeps the trace visible while it's dry, so the curve reads as
        // "nothing yet" rather than "no data".
        return intensities.enumerated().map { index, value in
            let scaled = 0.06 + CGFloat(value) * 0.94
            return CGPoint(x: CGFloat(index) * step,
                           y: size.height - size.height * scaled * 0.92)
        }
    }
}

// MARK: - Axis

/// Four marks across the window, pinned to the ends so they line up with the
/// curve above instead of floating.
private struct TimeAxis: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.serif(10))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity,
                           alignment: index == 0 ? .leading
                               : (index == labels.count - 1 ? .trailing : .center))
            }
        }
    }
}
