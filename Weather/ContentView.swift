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

    /// Periodic silent refresh while the app stays open.
    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

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
        .animation(.easeInOut(duration: 0.5), value: viewModel.bundle?.place.id)
        .task {
            if viewModel.bundle == nil {
                await viewModel.bootstrap()
            }
        }
        // Refresh whenever the app returns to the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, viewModel.bundle != nil {
                Task { await viewModel.reload() }
            }
        }
        // And on a timer while it stays open (silent — no spinner).
        .onReceive(refreshTimer) { _ in
            if viewModel.bundle != nil {
                Task { await viewModel.reload() }
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
                          accent: bundle.current.condition.accent)
            }
        }
    }
}

// MARK: - Loading

private struct LoadingView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x16213E), Color(hex: 0x0B1020)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                    .scaleEffect(animate ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                               value: animate)
                Text("Gathering the skies…")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .onAppear { animate = true }
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
                    .font(.system(.title2, design: .serif))
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
