//
//  WeatherViewModel.swift
//  Weather
//
//  Orchestrates location, saved places, units, and forecast fetching.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // Persistence keys
    private static let savedPlacesKey = "saved_places_v1"
    private static let tempUnitKey = "temp_unit"
    private static let speedUnitKey = "speed_unit"

    private let weatherService = WeatherService()
    private let geocoder = GeocodingService()
    let locationManager = LocationManager()

    private(set) var phase: Phase = .idle
    private(set) var bundle: WeatherBundle?
    private(set) var savedPlaces: [Place] = []
    var selectedPlace: Place?

    var temperatureUnit: TemperatureUnit {
        didSet {
            guard oldValue != temperatureUnit else { return }
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: Self.tempUnitKey)
            Task { await reload() }
        }
    }

    var speedUnit: SpeedUnit {
        didSet {
            guard oldValue != speedUnit else { return }
            UserDefaults.standard.set(speedUnit.rawValue, forKey: Self.speedUnitKey)
            Task { await reload() }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Self.tempUnitKey) ?? "")
            ?? .fahrenheit
        speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Self.speedUnitKey) ?? "")
            ?? .mph
        loadSavedPlaces()
    }

    // MARK: - Lifecycle

    /// Decide what to show on first launch: device location, else last/first saved place.
    func bootstrap() async {
        if !locationManager.isDenied {
            await useCurrentLocation()
            if case .loaded = phase { return }
        }
        if let first = savedPlaces.first {
            await select(first)
        } else {
            // Sensible default so the app is never empty.
            await select(Place(name: "San Francisco", admin1: "California",
                               country: "United States", countryCode: "US",
                               latitude: 37.7749, longitude: -122.4194, timezone: nil))
        }
    }

    func useCurrentLocation() async {
        phase = .loading
        do {
            let place = try await locationManager.requestCurrentPlace()
            await load(place: place, persist: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func select(_ place: Place) async {
        await load(place: place, persist: true)
    }

    func reload() async {
        guard let place = selectedPlace else { return }
        await load(place: place, persist: false, showSpinner: bundle == nil)
    }

    private func load(place: Place, persist: Bool, showSpinner: Bool = true) async {
        selectedPlace = place
        if showSpinner { phase = .loading }
        do {
            let result = try await weatherService.fetch(
                for: place,
                temperatureUnit: temperatureUnit,
                speedUnit: speedUnit
            )
            bundle = result
            phase = .loaded
            WeatherWidgetSnapshot.publish(from: result,
                                          temperatureUnit: temperatureUnit,
                                          speedUnit: speedUnit)
            if persist { addSavedPlace(result.place) }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Search

    func search(_ query: String) async -> [Place] {
        (try? await geocoder.search(query)) ?? []
    }

    // MARK: - Saved places

    private func loadSavedPlaces() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedPlacesKey),
              let places = try? JSONDecoder().decode([Place].self, from: data) else { return }
        savedPlaces = places
    }

    private func persistSavedPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: Self.savedPlacesKey)
        }
    }

    func addSavedPlace(_ place: Place) {
        if !savedPlaces.contains(where: { $0.id == place.id }) {
            savedPlaces.insert(place, at: 0)
            persistSavedPlaces()
        }
    }

    func removeSavedPlace(_ place: Place) {
        savedPlaces.removeAll { $0.id == place.id }
        persistSavedPlaces()
    }

    func moveSavedPlace(from offsets: IndexSet, to destination: Int) {
        savedPlaces.move(fromOffsets: offsets, toOffset: destination)
        persistSavedPlaces()
    }

    func isSaved(_ place: Place) -> Bool {
        savedPlaces.contains { $0.id == place.id }
    }
}
