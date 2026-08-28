//
//  LocationManager.swift
//  Weather
//
//  Thin CoreLocation wrapper: one-shot device location + reverse geocoding
//  into a Place the rest of the app understands.
//

import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle, requesting, denied, failed, resolved
    }

    private let manager = CLLocationManager()
    /// Everyone awaiting the current fix. Concurrent callers (bootstrap racing
    /// a foreground refresh, a panel tap racing the device summary) all join
    /// the same request and are resumed together — a single slot here used to
    /// drop the first caller's continuation, hanging that task forever.
    private var continuations: [CheckedContinuation<Place, Error>] = []

    var authorizationStatus: CLAuthorizationStatus
    private(set) var state: State = .idle

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Requests permission (if needed) and resolves the current location to a Place.
    func requestCurrentPlace() async throws -> Place {
        if isDenied { throw LocationError.denied }

        // Fast path: CoreLocation usually already holds a recent fix, and we
        // remember the place we resolved it to last time. Together that skips
        // both waits — the GPS callback and the reverse-geocode round trip —
        // which is most of a cold launch. A fix from somewhere new falls
        // through to the full path below.
        if let recent = manager.location,
           Date().timeIntervalSince(recent.timestamp) < 300,
           let known = Self.rememberedPlace(near: recent.coordinate) {
            state = .resolved
            // Still ask for a current fix, just without waiting on it: if you've
            // actually moved, the delegate remembers the new place and the next
            // refresh picks it up.
            if continuations.isEmpty { manager.requestLocation() }
            return known
        }

        state = .requesting

        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            // Only the first waiter starts CoreLocation; later callers just
            // join the fix already underway.
            guard continuations.count == 1 else { return }
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // CoreLocation fires this on every launch once the delegate is
                // set; only chase a fix when someone is actually waiting on one.
                if !self.continuations.isEmpty { manager.requestLocation() }
            case .denied, .restricted:
                self.state = .denied
                self.resume(throwing: LocationError.denied)
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.resolvePlace(from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .failed
            self.resume(throwing: LocationError.unavailable)
        }
    }

    // MARK: - Helpers

    private func resolvePlace(from location: CLLocation) async {
        // Still in the same area as the last resolve? Reuse that place rather
        // than paying for another reverse geocode — and reuse its coordinates
        // too, so the place id stays put and the cached forecast still matches.
        if let known = Self.rememberedPlace(near: location.coordinate) {
            state = .resolved
            resume(returning: known)
            return
        }

        let geocoder = CLGeocoder()
        var place = Place(
            name: "Current Location",
            admin1: nil,
            country: nil,
            countryCode: nil,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timezone: nil
        )

        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            place = Place(
                name: placemark.locality ?? placemark.name ?? "Current Location",
                // Apple returns the state as a 2-letter code (e.g. "VA"); expand
                // it to the full name so it matches searched places ("California").
                admin1: USStates.expand(placemark.administrativeArea,
                                        countryCode: placemark.isoCountryCode),
                country: placemark.country,
                countryCode: placemark.isoCountryCode,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timezone: placemark.timeZone?.identifier
            )
        }

        Self.remember(place)
        state = .resolved
        resume(returning: place)
    }

    // MARK: - Remembered place

    private static let rememberedKey = "remembered_device_place_v1"
    /// Close enough to be the same place, weather-wise.
    private static let sameAreaMeters: CLLocationDistance = 3_000
    private static let rememberedMaxAge: TimeInterval = 24 * 3600

    private struct Remembered: Codable {
        let place: Place
        let resolvedAt: Date
    }

    /// The device place resolved last time, whatever it was — lets a launch
    /// draw the right city's cached forecast before location answers.
    var lastKnownPlace: Place? { Self.remembered()?.place }

    /// Same fact for contexts with no manager instance (background checks).
    static func rememberedDevicePlace() -> Place? { remembered()?.place }

    private static func remembered() -> Remembered? {
        guard let data = UserDefaults.standard.data(forKey: rememberedKey),
              let stored = try? JSONDecoder().decode(Remembered.self, from: data),
              Date().timeIntervalSince(stored.resolvedAt) < rememberedMaxAge
        else { return nil }
        return stored
    }

    private static func rememberedPlace(near coordinate: CLLocationCoordinate2D) -> Place? {
        guard let stored = remembered() else { return nil }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let there = CLLocation(latitude: stored.place.latitude, longitude: stored.place.longitude)
        return here.distance(from: there) < sameAreaMeters ? stored.place : nil
    }

    private static func remember(_ place: Place) {
        guard let data = try? JSONEncoder().encode(Remembered(place: place, resolvedAt: Date()))
        else { return }
        UserDefaults.standard.set(data, forKey: rememberedKey)
    }

    /// Drains into a local copy before resuming, so a caller that immediately
    /// requests again can't be swept into this round's resume.
    private func resume(returning place: Place) {
        let waiting = continuations
        continuations = []
        for c in waiting { c.resume(returning: place) }
    }

    private func resume(throwing error: Error) {
        let waiting = continuations
        continuations = []
        for c in waiting { c.resume(throwing: error) }
    }
}

enum LocationError: LocalizedError {
    case denied, unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Search for a city instead."
        case .unavailable: return "Couldn't determine your location."
        }
    }
}
