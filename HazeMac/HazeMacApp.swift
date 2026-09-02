//
//  HazeMacApp.swift
//  HazeMac
//
//  Haze for the Mac. The same forecast, models, cards, sky, and glass as the
//  iPhone app, arranged for one window: a locations column, the page, and a
//  panel beside it for Settings and the radar. No system chrome: the sky runs
//  edge to edge and the controls are the app's own. And, because it is a Mac,
//  the temperature sits in the menu bar.
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
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MacCommands(viewModel: viewModel, windows: windows)
        }

        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarPanel(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
