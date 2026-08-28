//
//  DeviceScreen.swift
//  Weather
//
//  The display's own corner radius, so floating chrome can sit *concentric*
//  inside the screen's curve instead of guessing a radius that looks tight on
//  one iPhone and bloated on another.
//
//  Deliberately a size table rather than UIScreen's private `_displayCornerRadius`:
//  that key is a private API string and has no place in a shipping build. Where
//  two devices share a point size and differ in radius, the entry takes the
//  more common of the two — the gap is a few points and reads identically.
//

import UIKit

/// Observable snapshot of the values views need every frame. Reading the window
/// hierarchy inside a view body is both wasteful (it walks connected scenes)
/// and *stale* — nothing tells SwiftUI to re-read it after a rotation. This
/// caches them and republishes when the geometry actually changes.
@MainActor
@Observable
final class ScreenMetrics {
    static let shared = ScreenMetrics()

    private(set) var width: CGFloat = DeviceScreen.width
    private(set) var bottomSafeInset: CGFloat = DeviceScreen.bottomSafeInset

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Called on rotation, and once per appearance in case the app launched
    /// into an orientation the notification never announced.
    func refresh() {
        let newWidth = DeviceScreen.width
        let newInset = DeviceScreen.bottomSafeInset
        if newWidth != width { width = newWidth }
        if newInset != bottomSafeInset { bottomSafeInset = newInset }
    }
}

/// Main-actor by default (like the rest of the app): every value here reads
/// UIKit window state, which is main-actor only.
enum DeviceScreen {
    /// Apple's published display corner radii, keyed by portrait point size.
    private static let radiiByPortraitSize: [CGSize: CGFloat] = [
        CGSize(width: 320, height: 568): 0,      // SE 1st gen
        CGSize(width: 375, height: 667): 0,      // 8, SE 2nd/3rd gen
        CGSize(width: 414, height: 736): 0,      // 8 Plus
        CGSize(width: 375, height: 812): 39,     // X, XS, 11 Pro, 12 mini*, 13 mini*
        CGSize(width: 414, height: 896): 41.5,   // XR, 11 (XS Max/11 Pro Max are 39)
        CGSize(width: 390, height: 844): 47.33,  // 12, 12 Pro, 13, 13 Pro, 14
        CGSize(width: 428, height: 926): 53.33,  // 12/13 Pro Max, 14 Plus
        CGSize(width: 393, height: 852): 55,     // 14 Pro, 15, 15 Pro, 16
        CGSize(width: 430, height: 932): 55,     // 14/15 Pro Max, 15 Plus, 16 Plus
        CGSize(width: 402, height: 874): 62,     // 16 Pro
        CGSize(width: 440, height: 956): 62,     // 16 Pro Max
    ]

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    /// The home-indicator strip at the foot of the screen (0 on a Home-button
    /// device), so floating chrome can sit just clear of it.
    static var bottomSafeInset: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }

    /// Full screen width — used for page geometry without wrapping the layout
    /// in a GeometryReader, which would change how the screen lays out.
    static var width: CGFloat {
        keyWindow?.bounds.width ?? 393
    }

    /// The display's corner radius in points, or a sensible modern default for
    /// a device that isn't in the table yet (new hardware trends larger, and
    /// the safe-area inset tells us whether the screen is rounded at all).
    static var displayCornerRadius: CGFloat {
        guard let window = keyWindow else { return 44 }

        let size = window.screen.bounds.size
        let portrait = CGSize(width: min(size.width, size.height),
                              height: max(size.width, size.height))
        if let known = radiiByPortraitSize[portrait] { return known }

        // Unknown device: square corners have no bottom inset; rounded ones
        // scale roughly with the screen's short edge.
        let bottomInset = window.safeAreaInsets.bottom
        guard bottomInset > 0 else { return 0 }
        return max(44, portrait.width * 0.14)
    }

    /// The radius a panel should use to look concentric with the screen when
    /// it's inset from the edges by `inset`. Clamped so a square-cornered
    /// device (or a very deep inset) still gets a graceful rounded card.
    static func concentricRadius(inset: CGFloat, minimum: CGFloat = 22) -> CGFloat {
        max(minimum, displayCornerRadius - inset)
    }
}
