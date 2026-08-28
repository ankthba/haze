//
//  CloudSync.swift
//  Weather
//
//  Saved places and the settings worth carrying, mirrored through iCloud's
//  key-value store so a new phone opens with your cities already in place.
//  Deliberately small: no forecasts, no caches — the few kilobytes that are
//  genuinely *yours*.
//
//  The store is best-effort by design (it needs an iCloud account and a
//  network at some point); every read falls back to the local value.
//

import Foundation

@MainActor
enum CloudSync {
    private static let store = NSUbiquitousKeyValueStore.default

    /// True once the iCloud key-value capability is enabled on the App ID and
    /// the user is signed in. Until then every call here is a no-op, so the
    /// feature can ship dark and light up the moment the checkbox is ticked
    /// (an unregistered entitlement would fail the device build outright).
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Keys mirrored in both directions. Values stay in UserDefaults as the
    /// source of truth for the running app; iCloud is the courier.
    static let placesKey = "saved_places_v1"
    static let mirroredSettings = [
        "temp_unit", "speed_unit", "precip_unit", "pressure_unit",
        "time_format", "text_size", "home_card_order",
        "show_trend_card", "show_radar_preview", "show_wind_compass",
        "show_sun_card", "show_daily_brief", "radar_autoplay",
    ]

    /// Push local values up. Called after any change worth carrying.
    static func push() {
        guard isAvailable else { return }
        let defaults = UserDefaults.standard
        if let places = defaults.data(forKey: placesKey) {
            store.set(places, forKey: placesKey)
        }
        for key in mirroredSettings {
            if let value = defaults.object(forKey: key) {
                store.set(value, forKey: key)
            }
        }
        store.synchronize()
    }

    /// Pull remote values down when they're newer than what we have. Returns
    /// true when something actually changed locally, so the caller can reload.
    @discardableResult
    static func pull() -> Bool {
        guard isAvailable else { return false }
        let defaults = UserDefaults.standard
        var changed = false

        if let remote = store.data(forKey: placesKey),
           remote != defaults.data(forKey: placesKey) {
            defaults.set(remote, forKey: placesKey)
            changed = true
        }
        for key in mirroredSettings {
            guard let remote = store.object(forKey: key) else { continue }
            let local = defaults.object(forKey: key)
            // Compare as strings: these are all scalars/arrays of scalars, and
            // it avoids an isEqual dance across NSNumber/NSString/NSArray.
            if String(describing: remote) != String(describing: local as Any) {
                defaults.set(remote, forKey: key)
                changed = true
            }
        }
        return changed
    }

    /// Start listening for pushes from the user's other devices. `onChange`
    /// runs on the main actor after remote values have been merged locally.
    static func start(onChange: @escaping @MainActor () -> Void) {
        guard isAvailable else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if pull() { onChange() }
            }
        }
        store.synchronize()
        _ = pull()
    }
}
