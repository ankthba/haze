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

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .idle, .loading where viewModel.bundle == nil:
                LoadingView()
            case .failed(let message) where viewModel.bundle == nil:
                ErrorView(message: message) {
                    Task { await viewModel.bootstrap() }
                } onSearch: {
                    showSearch = true
                }
            default:
                if let bundle = viewModel.bundle {
                    WeatherScreen(bundle: bundle,
                                  viewModel: viewModel,
                                  showSearch: $showSearch,
                                  showSettings: $showSettings,
                                  showRadar: $showRadar)
                    .transition(.opacity)
                } else {
                    LoadingView()
                }
            }
        }
        // The whole app (sheets included) follows the in-app text-size setting;
        // custom serif fonts scale because they're all `relativeTo:` a text style.
        .dynamicTypeSize(viewModel.textSize.dynamicTypeSize)
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
        .task {
            if viewModel.bundle == nil {
                await viewModel.bootstrap()
            }
        }
        // Refresh whenever the app returns to the foreground; when showing the
        // device location this re-resolves the location itself, so arriving in
        // a new city never leaves yesterday's city on screen.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, viewModel.bundle != nil {
                Task { await viewModel.refresh() }
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
        .fullScreenCover(isPresented: $showRadar) {
            if let bundle = viewModel.bundle {
                RadarView(place: bundle.place,
                          timezone: bundle.timezone,
                          accent: bundle.current.condition.accent,
                          isDay: bundle.current.isDay)
            }
        }
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
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                HStack(spacing: 12) {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                    Button("Search a City", action: onSearch)
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
