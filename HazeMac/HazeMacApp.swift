//
//  HazeMacApp.swift
//  HazeMac
//
//  Haze for the Mac. The same forecast, models, cards, sky, and glass as the
//  iPhone app, arranged for a window: a locations column beside the page, the
//  radar in a window of its own, Settings under ⌘, and, because it is a Mac,
//  the temperature in the menu bar. No system chrome: the sky runs edge to
//  edge and the controls are the app's own.
//

import SwiftUI
import AppKit

@main
struct HazeMacApp: App {
    @State private var viewModel = WeatherViewModel()
    @State private var windows = MacWindows()
    @AppStorage(Platform.menuBarKey) private var showsMenuBar = true

    init() {
        AppSetup.prepare()
        #if DEBUG
        MacSnapshot.armIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: MacWindows.mainWindowID) {
            MacRootView(viewModel: viewModel, windows: windows)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MacCommands(viewModel: viewModel, windows: windows)
        }

        Window("Radar", id: MacWindows.radarWindowID) {
            MacRadarWindow(viewModel: viewModel)
        }
        .defaultSize(width: 920, height: 660)
        .windowStyle(.hiddenTitleBar)

        Settings {
            MacSettingsWindow(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarPanel(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
