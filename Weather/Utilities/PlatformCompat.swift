//
//  PlatformCompat.swift
//  Weather
//
//  Small shims so the iOS-flavored UI also compiles cleanly on macOS/visionOS.
//

import SwiftUI

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
}
