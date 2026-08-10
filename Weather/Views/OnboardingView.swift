//
//  OnboardingView.swift
//  Weather
//
//  A six-page editorial introduction: the wordmark, the type, the radar, your
//  units, comfort settings, and a choice of starting location. The sky palette
//  crossfades as pages turn and each beat lands with its own haptic.
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @Bindable var viewModel: WeatherViewModel
    var onUseLocation: () async -> Void
    var onChooseCity: () -> Void
    var onFinish: () -> Void

    @Bindable private var prefs = UIPrefs.shared
    @State private var page = 0
    @State private var revealed = false
    @State private var requestingLocation = false
    @State private var specimenDegrees = 60
    @State private var pinBob = false
    @State private var radarPulseTask: Task<Void, Never>?
    /// -1 = resting; 0/1/2 = dot, inner arcs, outer arcs lit.
    @State private var radarStep = -1

    private static let pageCount = 6

    /// One sky per page: day, dusk, storm gray, day, night, dawn.
    private static let skies: [[UInt]] = [
        [0x3D86E6, 0x68A4E8, 0xBCD7F1],
        [0x1E376B, 0x73557F, 0xE89A63],
        [0x39465A, 0x5A6B7E, 0x93A2B0],
        [0x3D86E6, 0x68A4E8, 0xBCD7F1],
        [0x0A1230, 0x152149, 0x223560],
        [0xF3B58C, 0xDCA7BA, 0x96B8E2]
    ]

    var body: some View {
        ZStack {
            // All six skies stacked; every sky up to the current page stays
            // fully opaque, so a page turn fades the new sky in OVER the old
            // one. A plain crossfade dips both layers through half opacity at
            // once, which briefly let the app show through the cover.
            ZStack {
                ForEach(0..<Self.pageCount, id: \.self) { i in
                    LinearGradient(colors: Self.skies[i].map { Color(hex: $0) },
                                   startPoint: .top, endPoint: .bottom)
                        .opacity(i <= page ? 1 : 0)
                }
            }
            .background(Color(hex: 0x0A1230))
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.35), value: page)

            // Match the app's deepened-sky look, previewing the contrast
            // toggle live when it's flipped on the comfort page.
            Color.black.opacity(prefs.increaseContrast ? 0.38 : 0.22)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: prefs.increaseContrast)

            TabView(selection: $page) {
                wordmarkPage.tag(0)
                typePage.tag(1)
                radarPage.tag(2)
                unitsPage.tag(3)
                comfortPage.tag(4)
                locationPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                controls
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .colorScheme(.dark)
        .onAppear {
            Haptics.crescendo()
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.15)) {
                revealed = true
            }
        }
        .onChange(of: page) { _, newPage in
            radarPulseTask?.cancel()
            switch newPage {
            case 1:  countUpSpecimen()
            case 2:  startRadarPulse()
            case 5:  Haptics.crescendo()
            default: Haptics.selection()
            }
        }
        .onDisappear { radarPulseTask?.cancel() }
    }

    /// One clock drives both the glyph's lighting and the haptics: each step
    /// brightens the next ring outward AND lands its tap in the same beat, so
    /// the two can never drift apart.
    private func startRadarPulse() {
        guard !UIPrefs.shared.reduceMotion else {
            radarStep = 2
            return
        }
        radarPulseTask = Task { @MainActor in
            while !Task.isCancelled, page == 2 {
                for (step, intensity) in [0.35, 0.6, 0.95].enumerated() {
                    guard !Task.isCancelled, page == 2 else { return }
                    withAnimation(.easeOut(duration: 0.22)) { radarStep = step }
                    if Haptics.isEnabled {
                        UIImpactFeedbackGenerator(style: step == 2 ? .light : .soft)
                            .impactOccurred(intensity: intensity)
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                guard !Task.isCancelled, page == 2 else { return }
                withAnimation(.easeInOut(duration: 0.5)) { radarStep = -1 }
                try? await Task.sleep(for: .milliseconds(850))
            }
        }
    }

    /// Drifts the type-specimen temperature from 60° to 72° in single degrees,
    /// deliberately unhurried: each digit rolls in with a slow ease, the pace
    /// stretches as the reading settles, and each step lands a solid tick.
    private func countUpSpecimen() {
        guard !UIPrefs.shared.reduceMotion else {
            specimenDegrees = 72
            return
        }
        specimenDegrees = 60
        Task { @MainActor in
            let start = 60, end = 72
            try? await Task.sleep(for: .milliseconds(600))
            for value in (start + 1)...end {
                guard page == 1 else { return }
                let progress = Double(value - start) / Double(end - start)
                withAnimation(.easeInOut(duration: 0.3)) { specimenDegrees = value }
                if Haptics.isEnabled {
                    UIImpactFeedbackGenerator(style: .light)
                        .impactOccurred(intensity: 0.5 + 0.4 * progress)
                }
                // A leisurely cadence that stretches as the reading settles.
                let delay = 200 + Int(pow(progress, 2.0) * 280)
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard page == 1 else { return }
            Haptics.tap(.medium)
        }
    }

    // MARK: - Pages

    private var wordmarkPage: some View {
        pageLayout {
            Text("Haze")
                .font(.displaySerif(size: 104))
                .foregroundStyle(.white)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 18)
                .blur(radius: revealed ? 0 : 6)
            Text("The forecast, beautifully set.")
                .font(.serif(.title3, italic: true))
                .foregroundStyle(.white.opacity(0.85))
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 10)
        }
    }

    private var typePage: some View {
        pageLayout {
            // The degree sign hangs as an overlay so the *number* is what's
            // optically centered, matching the app's hero temperature.
            Text("\(specimenDegrees)")
                .font(.displaySerif(size: 120))
                .contentTransition(.numericText(value: Double(specimenDegrees)))
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.displaySerif(size: 76))
                        .offset(x: 30, y: 8)
                }
                .foregroundStyle(.white)
            Text("Reads like print")
                .font(.serif(.title2))
                .foregroundStyle(.white)
            Text("Oversized numerals, editorial serifs,\nand a sky that changes with the weather.")
                .font(.serif(.body, italic: true))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var radarPage: some View {
        pageLayout {
            RadarGlyph(step: radarStep)
                .frame(width: 150, height: 84)
            Text("Radar that plays")
                .font(.serif(.title2))
                .foregroundStyle(.white)
            Text("Twelve hours behind you, twelve ahead.\nScrub the storm or let it run.")
                .font(.serif(.body, italic: true))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var unitsPage: some View {
        pageLayout {
            Text("Your units")
                .font(.serif(.title2))
                .foregroundStyle(.white)
            Text("Changeable anytime in Settings.")
                .font(.serif(.body, italic: true))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 10)

            optionRow("Temperature") {
                Picker("Temperature", selection: $viewModel.temperatureUnit) {
                    Text("°F").tag(TemperatureUnit.fahrenheit)
                    Text("°C").tag(TemperatureUnit.celsius)
                }
                .sensoryFeedback(.selection, trigger: viewModel.temperatureUnit)
            }
            optionRow("Wind") {
                Picker("Wind", selection: $viewModel.speedUnit) {
                    Text("mph").tag(SpeedUnit.mph)
                    Text("km/h").tag(SpeedUnit.kmh)
                    Text("m/s").tag(SpeedUnit.ms)
                }
                .sensoryFeedback(.selection, trigger: viewModel.speedUnit)
            }
            optionRow("Time") {
                Picker("Time", selection: $viewModel.timeFormat) {
                    Text("Auto").tag(TimeFormat.system)
                    Text("12-hour").tag(TimeFormat.twelveHour)
                    Text("24-hour").tag(TimeFormat.twentyFourHour)
                }
                .sensoryFeedback(.selection, trigger: viewModel.timeFormat)
            }
        }
    }

    private var comfortPage: some View {
        pageLayout {
            Text("Make it comfortable")
                .font(.serif(.title2))
                .foregroundStyle(.white)
            Text("The full set lives in Settings.")
                .font(.serif(.body, italic: true))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 10)

            optionRow("Text size") {
                Picker("Text size", selection: $viewModel.textSize) {
                    ForEach(WeatherViewModel.TextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .sensoryFeedback(.selection, trigger: viewModel.textSize)
            }

            comfortToggle("Bold text", isOn: $prefs.boldText)
            comfortToggle("Increase contrast", isOn: $prefs.increaseContrast)
            comfortToggle("Reduce motion", isOn: $prefs.reduceMotion)
        }
    }

    private var locationPage: some View {
        pageLayout {
            Image(systemName: "location.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white)
                .offset(y: pinBob ? -4 : 4)
                .animation(UIPrefs.shared.reduceMotion
                           ? nil
                           : .easeInOut(duration: 2.1).repeatForever(autoreverses: true),
                           value: pinBob)
                .onAppear { pinBob = true }
            Text("Where should we begin?")
                .font(.serif(.title2))
                .foregroundStyle(.white)
            Text("Haze can follow you, or stay\nwith the places you choose.")
                .font(.serif(.body, italic: true))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    /// Shared page scaffold: centered content, breathing room for the controls.
    private func pageLayout(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            Spacer()
            content()
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    // MARK: - Option rows (units & comfort pages)

    private func optionRow(_ label: String,
                           @ViewBuilder picker: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.serif(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func comfortToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.serif(.subheadline, weight: .medium))
                .foregroundStyle(.white)
        }
        .tint(.white.opacity(0.35))
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        .padding(.vertical, 2)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            pageDots

            if page < Self.pageCount - 1 {
                capsuleButton("Continue", prominent: true) {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        page += 1
                    }
                }
            } else {
                capsuleButton(requestingLocation ? "One moment…" : "Use My Location",
                              prominent: true) {
                    guard !requestingLocation else { return }
                    requestingLocation = true
                    Haptics.arrival()
                    Task {
                        await onUseLocation()
                        onFinish()
                    }
                }
                capsuleButton("Choose a City", prominent: false) {
                    Haptics.arrival()
                    onChooseCity()
                    onFinish()
                }
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pageCount, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == page ? 0.95 : 0.35))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
        }
        .padding(.bottom, 4)
    }

    /// The app's frosted-glass capsule: real backdrop blur clipped to the
    /// shape, a light frost, a top-lit tint, and a gradient rim. Prominent
    /// buttons wear a stronger frost so they read as the primary action.
    fileprivate func capsuleButton(_ title: String, prominent: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.serif(.body, weight: prominent ? .semibold : .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    GlassSurface(shape: Capsule(), frost: prominent ? 0.28 : 0.10)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Radar glyph

/// A hand-drawn "((•))": a center dot with two arcs sweeping out each side.
/// Lighting is driven by `step` (0 = dot, 1 = inner arcs, 2 = outer arcs),
/// so the onboarding can brighten each ring in lockstep with its haptics.
private struct RadarGlyph: View {
    let step: Int

    private func opacity(for ring: Int) -> Double {
        step >= ring ? 1.0 : 0.32
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 13, height: 13)
                .opacity(opacity(for: 0))

            arcPair(diameter: 52, ring: 1)
            arcPair(diameter: 92, ring: 2)
        }
        .foregroundStyle(.white)
    }

    /// Mirrored left/right arcs of the given diameter, ~60° each, centered on
    /// the horizontal axis.
    private func arcPair(diameter: CGFloat, ring: Int) -> some View {
        ForEach([0.0, 180.0], id: \.self) { rotation in
            Circle()
                .trim(from: 0, to: 0.17)
                .stroke(style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(rotation - 30.6))
                .opacity(opacity(for: ring))
        }
    }
}
