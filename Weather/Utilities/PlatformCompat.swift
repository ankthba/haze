//
//  PlatformCompat.swift
//  Weather
//
//  Small shims so the iOS-flavored UI also compiles cleanly on macOS/visionOS,
//  plus the handful of places where the Mac build wants a slightly different
//  answer (a title bar instead of a status bar, a pointer instead of a finger)
//  without every view growing its own #if.
//

import SwiftUI
import CoreLocation

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    /// Room to leave above a page's first line. On the iPhone it clears the
    /// status bar and the floating controls; a Mac sheet or window has its own
    /// title bar, so only a breath is needed.
    static var sheetTopInset: CGFloat { isMac ? 12 : 44 }

    /// Whether the Mac app shows the temperature in the menu bar.
    static let menuBarKey = "mac_menu_bar_enabled"
}

extension View {
    /// Inline navigation title on platforms that support it; no-op elsewhere.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Grouped list styling that degrades gracefully off iOS.
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS) || os(visionOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// A Mac sheet sizes itself to its content, and the app's scrolling pages
    /// have no intrinsic size to offer, so they are given a comfortable page.
    /// No-op on iOS, where a sheet is always the whole screen.
    @ViewBuilder
    func macSheetFrame(width: CGFloat = 580, height: CGFloat = 760) -> some View {
        #if os(macOS)
        self.frame(minWidth: 480, idealWidth: width, minHeight: 540, idealHeight: height)
        #else
        self
        #endif
    }

    /// Capitalises each word while typing a place name; iOS keyboards only.
    @ViewBuilder
    func wordsAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// A quiet lift under the pointer, so a row that opens something says so
    /// before it's clicked. Nothing on touch platforms, where hover doesn't exist.
    func hoverHighlight(cornerRadius: CGFloat = 12, bleed: CGFloat = 10,
                        enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, bleed: bleed, enabled: enabled))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    /// How far past the content's own edges the lift extends.
    let bleed: CGFloat
    let enabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(hovering && enabled ? 0.07 : 0))
                    .padding(.horizontal, -bleed)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        #else
        content
        #endif
    }
}

extension CLAuthorizationStatus {
    /// Whether the app may ask for a fix. macOS has no "while using" tier;
    /// its single "authorized" state is spelled `authorizedAlways`.
    var isAuthorizedForApp: Bool {
        #if os(macOS)
        self == .authorizedAlways
        #else
        self == .authorizedWhenInUse || self == .authorizedAlways
        #endif
    }
}
