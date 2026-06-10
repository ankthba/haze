//
//  RadarView.swift
//  Weather
//
//  Full-screen precipitation radar: a dark map under an animated RainViewer
//  overlay, with an editorial timeline you can play or scrub. Sits in the same
//  visual family as the rest of the app — serif headings, hairline chrome,
//  white-on-dark.
//

import SwiftUI
import Combine

struct RadarView: View {
    let place: Place
    let timezone: TimeZone
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    @State private var maps: RainViewerService.Maps?
    @State private var frameIndex = 0
    @State private var isPlaying = true
    @State private var isScrubbing = false
    @State private var dwellTicks = 0
    @State private var failed = false

    private let service = RainViewerService()
    /// RainViewer "The Weather Channel" palette — vivid greens→reds over dark.
    private let palette = 4
    private let tick = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    private var frames: [RadarFrame] { maps?.frames ?? [] }
    private var currentFrame: RadarFrame? {
        guard frames.indices.contains(frameIndex) else { return frames.last }
        return frames[frameIndex]
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0A0E14).ignoresSafeArea()

            if let maps {
                RadarMapView(center: place.coordinate,
                             host: maps.host,
                             frames: maps.frames,
                             currentPath: currentFrame?.path,
                             colorScheme: palette)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else if failed {
                placeholder(icon: "antenna.radiowaves.left.and.right.slash",
                            text: "Radar isn't available right now.")
            } else {
                placeholder(icon: "dot.radiowaves.left.and.right",
                            text: "Loading radar…", pulse: true)
            }

            // Top + bottom scrims keep the chrome legible over busy radar.
            VStack {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer()
                if !frames.isEmpty { controls }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .colorScheme(.dark)
        .task { await load() }
        .onReceive(tick) { _ in advance() }
        // Grabbing the scrubber parks playback where you leave it.
        .onChange(of: isScrubbing) { _, scrubbing in
            if scrubbing { isPlaying = false }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                CardLabel(systemImage: "dot.radiowaves.left.and.right", title: "Radar")
                Text(place.name)
                    .font(.serif(size: 27))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Close radar")
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if let frame = currentFrame {
                    Text(Fmt.time(frame.time, timezone: timezone))
                        .font(.serif(size: 30))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(relativeLabel(for: frame))
                        .font(.system(.footnote, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(frame.isForecast ? accent : .white.opacity(0.55))
                }
                Spacer()
                IntensityLegend()
            }

            HStack(spacing: 16) {
                Button {
                    Haptics.tap()
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel(isPlaying ? "Pause radar animation" : "Play radar animation")

                RadarTimeline(count: frames.count,
                              index: $frameIndex,
                              nowIndex: maps?.nowIndex ?? 0,
                              accent: accent,
                              isScrubbing: $isScrubbing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }

    private func placeholder(icon: String, text: String, pulse: Bool = false) -> some View {
        VStack(spacing: 14) {
            PulsingIcon(systemName: icon, active: pulse)
            Text(text)
                .font(.serif(.title3))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Playback

    private func advance() {
        guard isPlaying, !isScrubbing, frames.count > 1 else { return }
        if frameIndex >= frames.count - 1 {
            // Hold on the latest frame a moment, then loop from the start.
            dwellTicks += 1
            if dwellTicks >= 3 { dwellTicks = 0; frameIndex = 0 }
        } else {
            dwellTicks = 0
            frameIndex += 1
        }
    }

    private func load() async {
        do {
            let result = try await service.fetchFrames()
            maps = result
            // Open on "now" (the most recent observed frame).
            frameIndex = result.nowIndex
            failed = false
        } catch {
            failed = true
        }
    }

    /// "now", "−40 min", "+30 min" relative to the present moment.
    private func relativeLabel(for frame: RadarFrame) -> String {
        let minutes = Int((frame.time.timeIntervalSinceNow / 60).rounded())
        switch minutes {
        case -5...5: return "NOW"
        case ..<0: return "\(minutes) MIN"
        default: return "+\(minutes) MIN"
        }
    }
}

// MARK: - Timeline scrubber

/// A hairline track of frame ticks with a draggable accent thumb and a brighter
/// "now" divider between observed and forecast frames.
private struct RadarTimeline: View {
    let count: Int
    @Binding var index: Int
    let nowIndex: Int
    let accent: Color
    @Binding var isScrubbing: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let step = count > 1 ? width / CGFloat(count - 1) : 0
            let thumbX = step * CGFloat(index)
            let nowX = step * CGFloat(nowIndex)

            ZStack(alignment: .leading) {
                // Base track
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(height: 3)

                // Elapsed portion up to the thumb
                Capsule()
                    .fill(accent.opacity(0.8))
                    .frame(width: max(0, thumbX), height: 3)

                // Frame ticks
                ForEach(0..<max(count, 1), id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i <= index ? 0.0 : 0.35))
                        .frame(width: 2, height: 2)
                        .offset(x: step * CGFloat(i) - 1)
                }

                // "Now" divider
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: 1.5, height: 14)
                    .offset(x: nowX - 0.75)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: thumbX - 7.5)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        guard step > 0 else { return }
                        let raw = Int((value.location.x / step).rounded())
                        let clamped = min(max(raw, 0), count - 1)
                        if clamped != index {
                            index = clamped
                            Haptics.selection()
                        }
                    }
                    .onEnded { _ in isScrubbing = false }
            )
        }
        .frame(height: 28)
    }
}

// MARK: - Intensity legend

private struct IntensityLegend: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            LinearGradient(
                colors: [Color(hex: 0x4CC76E), Color(hex: 0xE7D14B),
                         Color(hex: 0xE08A3C), Color(hex: 0xD2433B)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 78, height: 5)
            .clipShape(Capsule())
            Text("LIGHT · HEAVY")
                .font(.system(size: 8.5, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Pulsing placeholder icon

private struct PulsingIcon: View {
    let systemName: String
    let active: Bool
    @State private var on = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 40))
            .foregroundStyle(.white.opacity(0.85))
            .scaleEffect(on ? 1.08 : 0.92)
            .opacity(on ? 1 : 0.7)
            .animation(active ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                       value: on)
            .onAppear { if active { on = true } }
    }
}
