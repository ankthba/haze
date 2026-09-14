//
//  MacCommands.swift
//  HazeMac
//
//  The menu bar's share of the app: a Location menu for finding, choosing, and
//  refreshing; the panel and the sun page under View; Settings under ⌘, where
//  a Mac expects it. Every item has a key.
//

import SwiftUI

struct MacCommands: Commands {
    let viewModel: WeatherViewModel
    let windows: MacWindows

    var body: some Commands {
        // One window is the app; a second would only be a twin of the first.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                windows.toggle(.settings)
            }
            .keyboardShortcut(",")
        }

        CommandMenu("Location") {
            Button("Find a City…") {
                windows.requestSearchFocus()
            }
            .keyboardShortcut("f")

            Button("Use My Location") {
                Task { await viewModel.useCurrentLocation() }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(viewModel.locationManager.isDenied)

            Divider()

            Button("Refresh") {
                Task { await viewModel.refresh(userInitiated: true) }
            }
            .keyboardShortcut("r")
            .disabled(viewModel.bundle == nil)

            if !viewModel.savedPlaces.isEmpty {
                Divider()
                ForEach(Array(viewModel.savedPlaces.prefix(9).enumerated()), id: \.element.id) { index, place in
                    Button(place.name) {
                        Task { await viewModel.select(place) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        CommandGroup(replacing: .sidebar) {
            Button(windows.sidebarVisible ? "Hide Locations" : "Show Locations") {
                windows.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button("Radar") {
                windows.toggle(.radar)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(viewModel.bundle == nil)

            Button(windows.panelExpanded ? "Shrink Panel" : "Expand Panel") {
                windows.panelExpanded.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(windows.panel == nil)

            Button("Sunrise & Sunset") {
                windows.openSun(.sunset)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(viewModel.bundle == nil)

            Button("Advisories") {
                windows.showAlerts = true
            }
            .disabled((viewModel.bundle?.alerts ?? []).isEmpty)
        }
    }
}
