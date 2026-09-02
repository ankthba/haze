//
//  MacRootView.swift
//  HazeMac
//
//  Root of the main window: the intro until it's been seen, then the locations
//  column beside the page, both on one sky. Owns the app's lifecycle beats
//  (first fetch, iCloud adoption, the refresh timer, the rain check the iPhone
//  runs in the background) and the sheets that menu commands can summon.
//

import SwiftUI

struct MacRootView: View {
    @Bindable var viewModel: WeatherViewModel
    @Bindable var windows: MacWindows

    @State private var summaries = PlaceSummaries()
    @Environment(\.scenePhase) private var scenePhase

    static let sidebarWidth: CGFloat = 272

    private var units: WeatherCache.Units {
        WeatherCache.Units(temperature: viewModel.temperatureUnit,
                           speed: viewModel.speedUnit,
                           precip: viewModel.precipUnit)
    }

    /// Before the first forecast lands the window wears the app's day sky.
    private var skyCondition: WeatherCondition {
        viewModel.bundle?.current.condition ?? WeatherCondition(code: 1, isDay: true)
    }

    var body: some View {
        ZStack {
            if viewModel.hasOnboarded {
                // One sky under both columns, so the hairline between them is
                // a fold in the page rather than a seam between two apps.
                SkyBackground(condition: skyCondition,
                              now: Date(),
                              sunrise: viewModel.bundle?.today?.sunrise,
                              sunset: viewModel.bundle?.today?.sunset)

                HStack(spacing: 0) {
                    if windows.sidebarVisible {
                        MacSidebar(viewModel: viewModel, summaries: summaries, windows: windows)
                            .frame(width: Self.sidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    MacDetail(viewModel: viewModel, windows: windows)
                }
                .animation(UIPrefs.shared.reduceMotion ? nil
                           : .spring(response: 0.4, dampingFraction: 0.9),
                           value: windows.sidebarVisible)
            } else {
                intro
            }
        }
        .colorScheme(.dark)
        // The whole app is white type on a sky: sheets, menus, and the
        // Settings window all keep to the dark appearance so the chrome agrees.
        .preferredColorScheme(.dark)
        // The in-app text-size setting; custom serif fonts scale because
        // they're all `relativeTo:` a text style.
        .transformEnvironment(\.dynamicTypeSize) { size in
            if let override = viewModel.textSize.dynamicTypeSize { size = override }
        }
        .task {
            CloudSync.start { viewModel.adoptCloudChanges() }
            if viewModel.bundle == nil {
                await viewModel.bootstrap()
            }
            await summaries.refresh(places: viewModel.savedPlaces, units: units)
        }
        // Silent periodic refresh at the user-chosen interval; the task
        // restarts whenever the interval setting changes. The rain and
        // advisory check rides along: on the iPhone it runs as a background
        // task, and a Mac app that's open is its own background.
        .task(id: viewModel.refreshMinutes) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(viewModel.refreshMinutes) * 60))
                guard !Task.isCancelled, viewModel.bundle != nil else { continue }
                await viewModel.refresh()
                await summaries.refresh(places: viewModel.savedPlaces, units: units)
                await RainAlertsService.runCheck()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, viewModel.bundle != nil {
                Task { await viewModel.refresh() }
            }
        }
        .onChange(of: viewModel.savedPlaces) {
            Task { await summaries.refresh(places: viewModel.savedPlaces, units: units) }
        }
        .onChange(of: viewModel.bundle?.fetchedAt) {
            if let bundle = viewModel.bundle {
                summaries.note(bundle, unit: viewModel.temperatureUnit)
            }
        }
        .onChange(of: viewModel.temperatureUnit) {
            Task { await summaries.refresh(places: viewModel.savedPlaces, units: units, force: true) }
        }
        .sheet(isPresented: $windows.showSunEvents) {
            if let bundle = viewModel.bundle {
                SunEventsView(bundle: bundle, unit: viewModel.temperatureUnit,
                              initialKind: windows.sunEventsKind, voice: viewModel.voice)
            }
        }
        .sheet(isPresented: $windows.showAlerts) {
            AlertDetailView(alerts: viewModel.bundle?.alerts ?? [])
        }
    }

    private var intro: some View {
        OnboardingView(
            viewModel: viewModel,
            onUseLocation: {
                viewModel.useDeviceLocation = true
                await viewModel.useCurrentLocation()
            },
            onChooseCity: {
                // The column needs a moment to exist before it can take focus.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    windows.requestSearchFocus()
                }
            },
            onFinish: { viewModel.hasOnboarded = true })
    }
}
