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
    private static let textSizeKey = "text_size"
    private static let timeFormatKey = "time_format"
    private static let hapticsKey = "haptics_enabled"
    static let radarAutoplayKey = "radar_autoplay"
    private static let showTrendKey = "show_trend_card"
    private static let showRadarPreviewKey = "show_radar_preview"
    private static let showWindKey = "show_wind_compass"
    private static let showSunKey = "show_sun_card"
    private static let cardOrderKey = "home_card_order"
    private static let precipUnitKey = "precip_unit"
    private static let pressureUnitKey = "pressure_unit"
    private static let refreshMinutesKey = "refresh_minutes"
    private static let deviceLocationKey = "use_device_location"
    private static let onboardedKey = "has_onboarded"

    /// The reorderable blocks of the main screen, in their user-chosen order.
    /// (The hero conditions header always stays on top.)
    enum HomeCard: String, CaseIterable, Identifiable {
        case hourly, trend, daily, radar, details
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hourly: "Hourly forecast"
            case .trend: "72-hour trend"
            case .daily: "10-day forecast"
            case .radar: "Radar preview"
            case .details: "Conditions detail"
            }
        }
        var symbol: String {
            switch self {
            case .hourly: "clock"
            case .trend: "chart.line.uptrend.xyaxis"
            case .daily: "calendar"
            case .radar: "dot.radiowaves.left.and.right"
            case .details: "list.bullet"
            }
        }
    }

    /// App-wide type scale, applied as a Dynamic Type size at the root so every
    /// serif font (they're all `relativeTo:` a text style) follows along.
    enum TextSize: String, CaseIterable, Identifiable {
        case small, standard, large, extraLarge
        var id: String { rawValue }
        var label: String {
            switch self {
            case .small: "S"
            case .standard: "M"
            case .large: "L"
            case .extraLarge: "XL"
            }
        }
        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .small: .medium
            case .standard: .large
            case .large: .xLarge
            case .extraLarge: .xxLarge
            }
        }
    }

    private let weatherService = WeatherService()
    private let geocoder = GeocodingService()
    let locationManager = LocationManager()

    private(set) var phase: Phase = .idle
    private(set) var bundle: WeatherBundle?
    private(set) var savedPlaces: [Place] = []
    var selectedPlace: Place?

    /// Whether the screen is showing the device's own location (vs. a saved
    /// or searched place).
    private(set) var isShowingDeviceLocation = false

    /// The device location's weather, shown in the "back to your location"
    /// panel while browsing another place.
    struct DeviceSummary {
        let place: Place
        let temperature: Double
        let condition: WeatherCondition
        let fetchedAt: Date
    }
    private(set) var deviceSummary: DeviceSummary?

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

    // MARK: - Appearance & behavior settings

    var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey) }
    }

    var precipUnit: PrecipUnit {
        didSet {
            guard oldValue != precipUnit else { return }
            UserDefaults.standard.set(precipUnit.rawValue, forKey: Self.precipUnitKey)
            Fmt.precipUnit = precipUnit
            // Amounts are fetched in the requested unit, so refetch.
            Task { await reload() }
        }
    }

    var pressureUnit: PressureUnit {
        didSet {
            guard oldValue != pressureUnit else { return }
            UserDefaults.standard.set(pressureUnit.rawValue, forKey: Self.pressureUnitKey)
            Fmt.pressureUnit = pressureUnit
            // Display-side conversion; republish the bundle so rows re-render.
            Task { await reload() }
        }
    }

    /// Minutes between silent background refreshes while the app is open.
    var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: Self.refreshMinutesKey) }
    }

    /// Whether launch should start from the device's location (when permitted)
    /// rather than the first saved place.
    var useDeviceLocation: Bool {
        didSet { UserDefaults.standard.set(useDeviceLocation, forKey: Self.deviceLocationKey) }
    }

    /// False until the intro has been seen; Settings can reset it to replay.
    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Self.onboardedKey) }
    }

    var timeFormat: TimeFormat {
        didSet {
            guard oldValue != timeFormat else { return }
            UserDefaults.standard.set(timeFormat.rawValue, forKey: Self.timeFormatKey)
            Fmt.timeFormat = timeFormat
            // Republish the bundle so every time label re-renders in the new style.
            Task { await reload() }
        }
    }

    var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticsKey)
            Haptics.isEnabled = hapticsEnabled
        }
    }

    var radarAutoplay: Bool {
        didSet { UserDefaults.standard.set(radarAutoplay, forKey: Self.radarAutoplayKey) }
    }

    var showTrendCard: Bool {
        didSet { UserDefaults.standard.set(showTrendCard, forKey: Self.showTrendKey) }
    }

    var showRadarPreview: Bool {
        didSet { UserDefaults.standard.set(showRadarPreview, forKey: Self.showRadarPreviewKey) }
    }

    var showWindCompass: Bool {
        didSet { UserDefaults.standard.set(showWindCompass, forKey: Self.showWindKey) }
    }

    var showSunCard: Bool {
        didSet { UserDefaults.standard.set(showSunCard, forKey: Self.showSunKey) }
    }

    var cardOrder: [HomeCard] {
        didSet {
            UserDefaults.standard.set(cardOrder.map(\.rawValue), forKey: Self.cardOrderKey)
        }
    }

    /// Nudge a card one slot up or down in the main-screen order.
    func moveCard(_ card: HomeCard, up: Bool) {
        guard let i = cardOrder.firstIndex(of: card) else { return }
        let j = up ? i - 1 : i + 1
        guard cardOrder.indices.contains(j) else { return }
        cardOrder.swapAt(i, j)
    }

    init() {
        let defaults = UserDefaults.standard
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Self.tempUnitKey) ?? "")
            ?? .fahrenheit
        speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Self.speedUnitKey) ?? "")
            ?? .mph
        textSize = TextSize(rawValue: defaults.string(forKey: Self.textSizeKey) ?? "")
            ?? .standard
        timeFormat = TimeFormat(rawValue: defaults.string(forKey: Self.timeFormatKey) ?? "")
            ?? .system
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        radarAutoplay = defaults.object(forKey: Self.radarAutoplayKey) as? Bool ?? true
        showTrendCard = defaults.object(forKey: Self.showTrendKey) as? Bool ?? true
        showRadarPreview = defaults.object(forKey: Self.showRadarPreviewKey) as? Bool ?? true
        showWindCompass = defaults.object(forKey: Self.showWindKey) as? Bool ?? true
        showSunCard = defaults.object(forKey: Self.showSunKey) as? Bool ?? true
        precipUnit = PrecipUnit(rawValue: defaults.string(forKey: Self.precipUnitKey) ?? "")
            ?? .auto
        pressureUnit = PressureUnit(rawValue: defaults.string(forKey: Self.pressureUnitKey) ?? "")
            ?? .hPa
        refreshMinutes = {
            let stored = defaults.integer(forKey: Self.refreshMinutesKey)
            return stored > 0 ? stored : 5
        }()
        useDeviceLocation = defaults.object(forKey: Self.deviceLocationKey) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Self.onboardedKey)
        // Stored order, tolerant of future cards: unknown names are dropped and
        // any cards missing from the stored list are appended in default order.
        let stored = (defaults.stringArray(forKey: Self.cardOrderKey) ?? [])
            .compactMap(HomeCard.init(rawValue:))
        cardOrder = stored + HomeCard.allCases.filter { !stored.contains($0) }
        Fmt.timeFormat = timeFormat
        Fmt.precipUnit = precipUnit
        Fmt.pressureUnit = pressureUnit
        Haptics.isEnabled = hapticsEnabled
        loadSavedPlaces()
    }

    // MARK: - Lifecycle

    /// Decide what to show on first launch: device location, else last/first saved place.
    func bootstrap() async {
        if useDeviceLocation, !locationManager.isDenied {
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
            isShowingDeviceLocation = true
            deviceSummary = nil
            await load(place: place, persist: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func select(_ place: Place) async {
        isShowingDeviceLocation = false
        await load(place: place, persist: true)
        await refreshDeviceSummary()
    }

    func reload() async {
        guard let place = selectedPlace else { return }
        await load(place: place, persist: false, showSpinner: bundle == nil)
    }

    /// Foreground / periodic refresh. When the screen is the device location,
    /// re-resolve the location itself first, so moving cities never leaves the
    /// app (or widget) showing where you used to be.
    func refresh() async {
        if isShowingDeviceLocation, !locationManager.isDenied {
            await useCurrentLocation()
        } else {
            await reload()
            await refreshDeviceSummary()
        }
    }

    /// Fetch (or re-fetch) the device location's current conditions for the
    /// return panel. Cheap single call, cached for 15 minutes, and only runs
    /// when permission is already granted so browsing never triggers a prompt.
    func refreshDeviceSummary() async {
        guard !isShowingDeviceLocation else { return }
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        if let summary = deviceSummary,
           Date().timeIntervalSince(summary.fetchedAt) < 15 * 60 { return }
        guard let place = try? await locationManager.requestCurrentPlace(),
              let current = try? await weatherService.fetchCurrentSummary(
                  for: place, temperatureUnit: temperatureUnit) else { return }
        deviceSummary = DeviceSummary(
            place: place,
            temperature: current.temperature,
            condition: WeatherCondition(code: current.code, isDay: current.isDay),
            fetchedAt: Date())
    }

    private func load(place: Place, persist: Bool, showSpinner: Bool = true) async {
        selectedPlace = place
        if showSpinner { phase = .loading }
        do {
            let result = try await weatherService.fetch(
                for: place,
                temperatureUnit: temperatureUnit,
                speedUnit: speedUnit,
                precipUnit: precipUnit
            )
            bundle = result
            phase = .loaded
            // Widgets follow the device location: browsing another city
            // doesn't retarget them (unless location is unavailable, in which
            // case they follow whatever's viewed so they're never stale).
            if isShowingDeviceLocation || locationManager.isDenied {
                WeatherWidgetSnapshot.publish(from: result,
                                              temperatureUnit: temperatureUnit,
                                              speedUnit: speedUnit,
                                              precipUnit: precipUnit)
            }
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
