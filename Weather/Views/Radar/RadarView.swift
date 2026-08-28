//
//  RadarView.swift
//  Weather
//
//  Full-screen precipitation radar: a map under an animated precipitation-
//  forecast heatmap, with an editorial timeline you can play or scrub. Sits in
//  the same visual family as the rest of the app — serif headings, hairline
//  chrome, white-on-dark.
//

import SwiftUI
import Combine

struct RadarView: View {
    let place: Place
    let timezone: TimeZone
    let accent: Color
    let isDay: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var field: RadarField?
    @State private var frameIndex = 0
    // Consults UIPrefs (not raw UserDefaults) so the system-wide Reduce Motion
    // setting also opens the radar paused.
    @State private var isPlaying =
        (UserDefaults.standard.object(forKey: WeatherViewModel.radarAutoplayKey) as? Bool ?? true)
        && !UIPrefs.shared.reduceMotion
    @State private var isScrubbing = false
    @State private var dwellTicks = 0
    @State private var stallTicks = 0
    /// Where playback began — "now" — and so where the growing loop restarts.
    @State private var loopStart = 0
    @State private var failed = false
    /// True once a pinch or drag has taken the map off its opening framing —
    /// which is the only time the reset control has anything to do.
    @State private var cameraMoved = false
    @State private var resetToken = 0
    /// Downloads every frame's tiles ahead of playback; playback steps only
    /// onto frames it reports ready, so the first pass looks like the second.
    @State private var prefetcher = RadarPrefetcher()

    private let service = RadarService()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var frames: [RadarFrame] { field?.frames ?? [] }
    private var currentFrame: RadarFrame? {
        guard frames.indices.contains(frameIndex) else { return frames.last }
        return frames[frameIndex]
    }

    /// Each frame's position along the timeline, normalized 0…1 by *time* — so a
    /// 12h past and 12h future span equal width even if their frame counts differ.
    private var framePositions: [Double] {
        let times = frames.map(\.time.timeIntervalSince1970)
        guard let lo = times.first, let hi = times.last, hi > lo else {
            return Array(repeating: 0, count: frames.count)
        }
        return times.map { ($0 - lo) / (hi - lo) }
    }

    /// Frames whose tiles are downloaded. Before the prefetcher has learned the
    /// tile set there's nothing to report, so the timeline shows every frame as
    /// available rather than implying the whole loop is stuck loading.
    private var bufferedFrames: Set<Int> {
        prefetcher.isActive ? prefetcher.readyFrames : Set(frames.indices)
    }

    /// Normalized position of "now" on the timeline (the past/forecast boundary).
    private var nowPosition: Double {
        let times = frames.map(\.time.timeIntervalSince1970)
        guard let lo = times.first, let hi = times.last, hi > lo else { return 0 }
        return min(max((Date().timeIntervalSince1970 - lo) / (hi - lo), 0), 1)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0A0E14).ignoresSafeArea()

            if field != nil {
                RadarMapView(center: place.coordinate,
                             field: field,
                             currentIndex: frameIndex,
                             isDay: isDay,
                             prefetcher: prefetcher,
                             isInteractive: true,
                             resetToken: resetToken,
                             onCameraMoved: { cameraMoved = $0 })
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else if failed {
                Button {
                    Haptics.tap()
                    Task { await load() }
                } label: {
                    placeholder(icon: "antenna.radiowaves.left.and.right.slash",
                                text: "Radar isn't available.\nTap to retry.")
                }
                .buttonStyle(.plain)
            } else {
                placeholder(icon: "dot.radiowaves.left.and.right",
                            text: "Loading radar…", pulse: true)
            }

            // Progressive blur + soft scrims keep the chrome legible over the
            // busy map: the header text sits on genuinely blurred map, not raw
            // streets and city labels.
            TopScrollBlur(maxRadius: 12, height: 130)
                .allowsHitTesting(false)

            VStack {
                LinearGradient(colors: [.black.opacity(0.45), .clear],
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
        .onDisappear { prefetcher.cancel() }
        .onChange(of: frameIndex) { _, index in prefetcher.playbackIndex = index }
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
            if cameraMoved {
                Button {
                    Haptics.tap()
                    resetToken += 1
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel("Reset zoom")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
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
        .animation(UIPrefs.shared.reduceMotion ? nil : .easeInOut(duration: 0.2),
                   value: cameraMoved)
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
                        .font(.serif(.footnote, weight: .medium))
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

                RadarTimeline(positions: framePositions,
                              index: $frameIndex,
                              nowPosition: nowPosition,
                              accent: accent,
                              readyFrames: bufferedFrames,
                              isScrubbing: $isScrubbing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            GlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous),
                         blurRadius: 16)
        )
    }

    private func placeholder(icon: String, text: String, pulse: Bool = false) -> some View {
        VStack(spacing: 14) {
            PulsingIcon(systemName: icon, active: pulse)
            Text(text)
                .font(.serif(.title3))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Playback

    /// Tiles are downloaded in playback order from where the view opened, so
    /// the hours nearest now land first. Rather than stalling at the edge of
    /// what's downloaded, playback replays that stretch and the loop grows
    /// outward as the rest of the timeline arrives — by the time it's all in,
    /// this is an ordinary full-timeline loop.
    private func advance() {
        guard isPlaying, !isScrubbing, frames.count > 1 else { return }

        if frameIndex >= frames.count - 1 {
            // Linger on the latest forecast frame — that's the point of interest —
            // then loop back to the start.
            dwellTicks += 1
            guard dwellTicks >= 4, canShow(0) else { return }
            step(to: 0)
            return
        }

        let next = frameIndex + 1
        if prefetcher.isReady(next) {
            step(to: next)
            return
        }

        stallTicks += 1
        // Loop back over the buffered stretch instead of freezing on a frame
        // whose tiles are still in flight.
        if stallTicks >= 2, frameIndex > loopStart, prefetcher.isReady(loopStart) {
            step(to: loopStart)
            return
        }
        // Nothing is arriving — a missing or very slow tile shouldn't strand
        // the timeline, so move on and let the frame beneath cover the gap.
        if stallTicks >= 12 { step(to: next) }
    }

    private func step(to index: Int) {
        stallTicks = 0
        dwellTicks = 0
        frameIndex = index
    }

    private func canShow(_ index: Int) -> Bool {
        if prefetcher.isReady(index) { return true }
        stallTicks += 1
        if stallTicks >= 12 { return true }
        return false
    }

    private func load() async {
        failed = false
        do {
            let result = try await service.buildField(center: place.coordinate)
            prefetcher.arm()
            field = result
            // Open on the latest observed (real-radar) frame, ~now; playback then
            // runs forward into the forecast.
            frameIndex = result.latestObservedIndex
            loopStart = result.latestObservedIndex
        } catch {
            failed = true
        }
    }

    /// "Now", "1 hr ago", "+3 hr" relative to the present moment.
    private func relativeLabel(for frame: RadarFrame) -> String {
        let minutes = Int((frame.time.timeIntervalSinceNow / 60).rounded())
        if abs(minutes) <= 30 { return "Now" }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours < 0 ? "\(-hours) hr ago" : "+\(hours) hr"
    }
}

// MARK: - Timeline scrubber

/// A hairline track of frame ticks with a draggable accent thumb and a brighter
/// "now" divider between observed and forecast frames.
private struct RadarTimeline: View {
    let positions: [Double]   // each frame's normalized 0…1 position by time
    @Binding var index: Int
    let nowPosition: Double
    let accent: Color
    /// Frames whose tiles are downloaded — their ticks read brighter, so the
    /// timeline shows how much of the loop is buffered.
    let readyFrames: Set<Int>
    @Binding var isScrubbing: Bool

    private func pos(_ i: Int) -> Double { positions.indices.contains(i) ? positions[i] : 0 }

    private func tickOpacity(_ i: Int) -> Double {
        if i <= index { return 0 }                      // covered by the elapsed fill
        return readyFrames.contains(i) ? 0.35 : 0.12    // buffered vs still loading
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbX = width * pos(index)
            let nowX = width * nowPosition

            ZStack(alignment: .leading) {
                // Base track
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(height: 3)

                // Elapsed portion up to the thumb
                Capsule()
                    .fill(accent.opacity(0.8))
                    .frame(width: max(0, thumbX), height: 3)

                // Frame ticks (spaced by time)
                ForEach(positions.indices, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(tickOpacity(i)))
                        .frame(width: 2, height: 2)
                        .offset(x: width * positions[i] - 1)
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
                        guard width > 0, !positions.isEmpty else { return }
                        let target = min(max(value.location.x / width, 0), 1)
                        // Nearest frame to the dragged time position.
                        let clamped = positions.indices.min(by: {
                            abs(positions[$0] - target) < abs(positions[$1] - target)
                        }) ?? 0
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
                colors: [Color(hex: 0x04E9E7), Color(hex: 0x019FF4), Color(hex: 0x02C502),
                         Color(hex: 0xFDF802), Color(hex: 0xFD9500), Color(hex: 0xFD0000),
                         Color(hex: 0xF800FD)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 92, height: 5)
            .clipShape(Capsule())
            Text("Light · Heavy")
                .font(.serif(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Pulsing placeholder icon

private struct PulsingIcon: View {
    let systemName: String
    let active: Bool
    @State private var on = false

    var body: some View {
        let animate = active && !UIPrefs.shared.reduceMotion
        Image(systemName: systemName)
            .font(.system(size: 40))
            .foregroundStyle(.white.opacity(0.85))
            .scaleEffect(animate && on ? 1.08 : 0.92)
            .opacity(animate && on ? 1 : 0.7)
            .animation(animate ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                       value: on)
            .onAppear { if active { on = true } }
    }
}
