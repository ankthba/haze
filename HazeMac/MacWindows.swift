//
//  MacWindows.swift
//  HazeMac
//
//  The bits of window state that menu commands and toolbar buttons share:
//  which sheet is up, which side of the sun page was asked for, and a nudge
//  that moves focus into the sidebar's search field.
//

import Foundation
import Observation

@MainActor
@Observable
final class MacWindows {
    static let mainWindowID = "main"
    static let radarWindowID = "radar"

    /// The locations column; ⌃⌘S or the list button folds it away.
    var sidebarVisible = true
    var showSunEvents = false
    var sunEventsKind: SunEvent.Kind = .sunset
    var showAlerts = false
    /// Bumped by ⌘F and by "Choose a City" in the intro; the sidebar answers
    /// by putting the cursor in its search field.
    var searchFocusRequest = 0

    func openSun(_ kind: SunEvent.Kind) {
        sunEventsKind = kind
        showSunEvents = true
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }
}

/// A row in the locations sidebar.
enum SidebarItem: Hashable {
    case currentLocation
    case place(String)
}
