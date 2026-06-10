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
    private var continuation: CheckedContinuation<Place, Error>?

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
        state = .requesting

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
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
                manager.requestLocation()
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

        state = .resolved
        resume(returning: place)
    }

    private func resume(returning place: Place) {
        continuation?.resume(returning: place)
        continuation = nil
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
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
