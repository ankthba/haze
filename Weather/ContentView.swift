//
//  ContentView.swift
//  Weather
//
//  Root coordinator: owns the view model, shows the weather screen, loading,
//  and error states, and hosts the search & settings sheets.
//

import SwiftUI
import Combine

struct ContentView: View {
    @State private var viewModel = WeatherViewModel()
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showRadar = false
    @State private var showSunEvents = false
    /// Which side of the sun page the tap asked for.
    @State private var sunEventsKind: SunEvent.Kind = .sunset

    @Environment(\.scenePhase) private var scenePhase

    /// Screen metrics, refreshed on rotation — reading the window hierarchy
    /// inside a body is both wasteful and stale after the device turns.
    private var metrics: ScreenMetrics { .shared }

    /// The bar earns its place when there's a way home to offer, or a sky
    /// event to report.
    private var showsStatusBar: Bool { viewModel.bundle != nil }

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .idle where viewModel.bundle == nil,
                 .loading where viewModel.bundle == nil:
                LoadingView()
            case .failed(let message) where viewModel.bundle == nil:
                ErrorView(message: message) {
                    Task { await viewModel.bootstrap() }
                } onSearch: {
                    showSearch = true
                }
            default:
                if let bundle = viewModel.bundle {
                    ZStack(alignment: .bottom) {
                        WeatherScreen(bundle: bundle,
                                      viewModel: viewModel,
                                      showSearch: $showSearch,
                                      showSettings: $showSettings,
                                      showRadar: $showRadar,
                                      bottomInset: showsStatusBar ? 104 : 0)

                        if showsStatusBar {
                            BottomStatusBar(
                                bundle: bundle,
                                homeSummary: viewModel.isShowingDeviceLocation
                                    ? nil : viewModel.deviceSummary,
                                onReturnHome: {
                                    Task { await viewModel.useCurrentLocation() }
                                },
                                onSunTap: { kind in
                                    sunEventsKind = kind
                                    showSunEvents = true
                                })
                            // Same inset on the sides as the corner radius is
                            // measured from; the bottom value is measured from
                            // the *physical* edge, since bottom-aligned inside
                            // the safe area leaves it a whole home-indicator
                            // (34pt on a 14 Pro) too high.
                            .padding(.horizontal, BottomStatusBar.inset)
                            .padding(.bottom, BottomStatusBar.bottomGap - metrics.bottomSafeInset)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85),
                               value: viewModel.isShowingDeviceLocation)
                    .transition(.opacity)
                } else {
                    LoadingView()
                }
            }
        }
        // The whole app (sheets included) follows the in-app text-size setting;
        // custom serif fonts scale because they're all `relativeTo:` a text
        // style. On "Auto" the environment passes through untouched, so the
        // system setting — including accessibility sizes — applies as-is.
        .transformEnvironment(\.dynamicTypeSize) { size in
            if let override = viewModel.textSize.dynamicTypeSize { size = override }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !viewModel.hasOnboarded },
            set: { viewModel.hasOnboarded = !$0 }
        )) {
            OnboardingView(
                viewModel: viewModel,
                onUseLocation: {
                    viewModel.useDeviceLocation = true
                    await viewModel.useCurrentLocation()
                },
                onChooseCity: { showSearch = true },
                onFinish: { viewModel.hasOnboarded = true })
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.bundle?.place.id)
        // Screenshot/automation hooks: land on a sheet once the forecast is up.
        .onChange(of: viewModel.bundle == nil) { _, isNil in
            guard !isNil else { return }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-openSunEvents") { showSunEvents = true }
            if arguments.contains("-openSettings") { showSettings = true }
        }
        .task {
            metrics.refresh()
            // Adopt anything iCloud already has before the first fetch, then
            // keep listening for pushes from other devices.
            CloudSync.start { viewModel.adoptCloudChanges() }
            if viewModel.bundle == nil {
                await viewModel.bootstrap()
            }
        }
        // Refresh whenever the app returns to the foreground; when showing the
        // device location this re-resolves the location itself, so arriving in
        // a new city never leaves yesterday's city on screen.
        // "Open the radar" via Siri/Shortcuts leaves a note that's consumed
        // only once a bundle exists — on a cold start the intent's perform()
        // can run *after* the scene goes active, and presenting the radar
        // cover with no bundle would show an undismissable blank screen. The
        // bundle-arrival hook below catches both orderings.
        .onChange(of: viewModel.bundle?.place.id) { consumePendingRadarIfReady() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                consumePendingRadarIfReady()
                if viewModel.bundle != nil {
                    Task { await viewModel.refresh() }
                }
            }
            // Keep the background rain/alert check queued while we're away.
            if phase == .background {
                RainAlertsService.scheduleNextCheck()
            }
        }
        // And on a timer while it stays open (silent — no spinner).
        // Silent periodic refresh at the user-chosen interval; the task restarts
        // whenever the interval setting changes.
        .task(id: viewModel.refreshMinutes) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(viewModel.refreshMinutes) * 60))
                guard !Task.isCancelled, viewModel.bundle != nil else { continue }
                await viewModel.refresh()
            }
        }
        .sheet(isPresented: $showSearch) {
            LocationSearchView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSunEvents) {
            if let bundle = viewModel.bundle {
                SunEventsView(bundle: bundle, unit: viewModel.temperatureUnit,
                              initialKind: sunEventsKind)
            }
        }
        .fullScreenCover(isPresented: $showRadar) {
            if let bundle = viewModel.bundle {
                RadarView(place: bundle.place,
                          timezone: bundle.timezone,
                          accent: bundle.current.condition.accent,
                          isDay: bundle.current.isDay)
            }
        }
    }

    private func consumePendingRadarIfReady() {
        guard viewModel.bundle != nil,
              UserDefaults.standard.bool(forKey: OpenRadarIntent.pendingKey) else { return }
        UserDefaults.standard.set(false, forKey: OpenRadarIntent.pendingKey)
        showRadar = true
    }
}

// MARK: - Loading

private struct LoadingView: View {
    @State private var breathe = false

    var body: some View {
        ZStack {
            // The app's own day sky, softened toward the horizon — the loading
            // screen should feel like the first page of the magazine, not a
            // separate app.
            LinearGradient(
                colors: [Color(hex: 0x3D86E6), Color(hex: 0x68A4E8), Color(hex: 0xBCD7F1)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Spacer()

                Text("Haze")
                    .font(.displaySerif(size: 88))
                    .foregroundStyle(.white)
                    .opacity(breathe ? 1 : 0.82)
                    .animation(UIPrefs.shared.reduceMotion
                               ? nil
                               : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                               value: breathe)

                Text("Gathering the skies…")
                    .font(.serif(.title3, italic: true))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text("Data from Open-Meteo")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 18)
            }
        }
        .onAppear { breathe = true }
    }
}

// MARK: - Error

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onSearch: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2A2030), Color(hex: 0x0B1020)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Couldn't load weather")
                    .font(.serif(.title2))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // The failure state keeps the app's serif voice — this is the
                // one screen a user sees when things break.
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.serif(.body, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: onSearch) {
                        Text("Search a City")
                            .font(.serif(.body, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                .tint(.white)
                .padding(.top, 6)
            }
        }
        .colorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
