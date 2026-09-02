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
    @State private var cards = CardPresenter()
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

                GeometryReader { geo in
                    // Every column gets an explicit width from the window, so
                    // the three of them can never disagree about who owns the
                    // space, and opening a panel animates as a plain resize.
                    // A panel that would leave the page thinner than a phone
                    // simply takes the page instead.
                    let sidebar: CGFloat = windows.sidebarVisible ? Self.sidebarWidth : 0
                    let pageWidth = geo.size.width - sidebar
                    let canCollapse = pageWidth - MacPanel.width >= 420
                    let expanded = windows.panel != nil && (windows.panelExpanded || !canCollapse)
                    let panelWidth: CGFloat = windows.panel == nil ? 0
                        : (expanded ? pageWidth : MacPanel.width)
                    let detailWidth = pageWidth - panelWidth

                    HStack(spacing: 0) {
                        if windows.sidebarVisible {
                            MacSidebar(viewModel: viewModel, summaries: summaries, windows: windows)
                                .frame(width: Self.sidebarWidth)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        if !expanded {
                            MacDetail(viewModel: viewModel, windows: windows)
                                .frame(width: detailWidth)
                                .clipped()
                                .transition(.opacity)
                        }
                        if let panel = windows.panel {
                            MacPanel(viewModel: viewModel, windows: windows, panel: panel,
                                     isExpanded: expanded, canCollapse: canCollapse)
                                .frame(width: panelWidth)
                                .clipped()
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .animation(UIPrefs.shared.reduceMotion ? nil
                               : .spring(response: 0.4, dampingFraction: 0.9),
                               value: windows.sidebarVisible)
                    .animation(UIPrefs.shared.reduceMotion ? nil
                               : .spring(response: 0.4, dampingFraction: 0.9),
                               value: windows.panel)
                    .animation(UIPrefs.shared.reduceMotion ? nil
                               : .spring(response: 0.4, dampingFraction: 0.9),
                               value: expanded)
                }
                // The columns own the top row themselves (the traffic lights
                // sit on it); nothing is held back for a title bar.
                .ignoresSafeArea(.container, edges: .top)
            } else {
                intro
            }
        }
        .background(WindowChrome())
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
        .hazeSheet(isPresented: $windows.showSunEvents) { close in
            if let bundle = viewModel.bundle {
                SunEventsView(bundle: bundle, unit: viewModel.temperatureUnit,
                              initialKind: windows.sunEventsKind, voice: viewModel.voice,
                              onClose: close)
            }
        }
        .hazeSheet(isPresented: $windows.showAlerts) { close in
            AlertDetailView(alerts: viewModel.bundle?.alerts ?? [], onClose: close)
        }
        // The cards themselves, over a blur of the whole window.
        .overlay { MacCardOverlay(presenter: cards) }
        .environment(\.cardPresenter, cards)
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
