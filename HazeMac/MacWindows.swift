//
//  MacWindows.swift
//  HazeMac
//
//  The bits of window state that menu commands and the floating buttons share:
//  which column is showing, which panel is open and how wide, which sheet is
//  up, and a nudge that moves focus into the search field.
//

import Foundation
import Observation

@MainActor
@Observable
final class MacWindows {
    static let mainWindowID = "main"

    /// What the right-hand panel holds. Settings and the radar live in the
    /// window, beside the page, rather than in windows of their own.
    enum Panel: Equatable {
        case settings
        case radar
    }

    /// The locations column; ⌃⌘S or the list button folds it away.
    var sidebarVisible = true
    var panel: Panel?
    /// The panel grown to the whole page, and back to a column.
    var panelExpanded = false

    var showSunEvents = false
    var sunEventsKind: SunEvent.Kind = .sunset
    var showAlerts = false
    /// Bumped by ⌘F and by "Choose a City" in the intro; the sidebar answers
    /// by putting the cursor in its search field.
    var searchFocusRequest = 0

    /// The buttons toggle: the same one again closes the panel.
    func toggle(_ which: Panel) {
        if panel == which {
            panel = nil
        } else {
            panel = which
        }
    }

    func closePanel() {
        panel = nil
    }

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
