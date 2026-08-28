//
//  WeatherViewModel.swift
//  Weather
//
//  Orchestrates location, saved places, units, and forecast fetching.
//

import CoreLocation
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
    private static let showBriefKey = "show_daily_brief"
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
    /// `.system` (the default) passes the device's own setting through — which
    /// is what makes the accessibility sizes AX1–AX5 reachable; a forced size
    /// at the root would cap every low-vision user at .xxLarge.
    enum TextSize: String, CaseIterable, Identifiable {
        case system, small, standard, large, extraLarge
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "Auto"
            case .small: "S"
            case .standard: "M"
            case .large: "L"
            case .extraLarge: "XL"
            }
        }
        /// nil = don't override; inherit the system size.
        var dynamicTypeSize: DynamicTypeSize? {
            switch self {
            case .system: nil
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
    private(set) var bundle: WeatherBundle? {
        didSet { refreshDerived() }
    }

    // Derived once per reading rather than inside a view body. These walk the
    // whole hourly series and do date formatting; evaluated per frame during a
    // swipe (as they were, being computed properties of WeatherScreen) they
    // were the swipe's stutter.
    private(set) var nowcast: RainNowcast?
    private(set) var briefText: String = ""
    private(set) var rainLikelyToday = false

    private func refreshDerived() {
        guard let bundle else {
            nowcast = nil
            briefText = ""
            rainLikelyToday = false
            return
        }
        let usesInches = precipUnit.apiValue(temperatureUnit: temperatureUnit) == "inch"
        nowcast = RainNowcast.compute(minutely: bundle.minutely,
                                      wetThreshold: usesInches ? 0.005 : 0.12)
        // The nowcast line under the hero already gives exact rain timing, so
        // the brief skips it — two copies stacked read as a glitch.
        briefText = DailyBrief.compose(bundle: bundle,
                                       nowcast: showDailyBrief && nowcast != nil ? nil : nowcast,
                                       usesFahrenheit: temperatureUnit == .fahrenheit)
        let todays = bundle.upcomingHours.filter {
            Fmt.isToday($0.date, timezone: bundle.timezone)
        }
        let pool = todays.isEmpty ? bundle.upcomingHours : todays
        rainLikelyToday = (pool.map(\.precipitationProbability).max() ?? 0) >= 30
    }
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

    /// The in-flight follow-up fetch for air quality / observations.
    private var enrichTask: Task<Void, Never>?

    /// Stamped onto cached readings so a unit change never redraws old numbers.
    private var cacheUnits: WeatherCache.Units {
        WeatherCache.Units(temperature: temperatureUnit, speed: speedUnit, precip: precipUnit)
    }

    var temperatureUnit: TemperatureUnit {
        didSet {
            guard oldValue != temperatureUnit else { return }
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: Self.tempUnitKey); CloudSync.push()
            Task { await reload() }
        }
    }

    var speedUnit: SpeedUnit {
        didSet {
            guard oldValue != speedUnit else { return }
            UserDefaults.standard.set(speedUnit.rawValue, forKey: Self.speedUnitKey); CloudSync.push()
            Task { await reload() }
        }
    }

    // MARK: - Appearance & behavior settings

    var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey); CloudSync.push() }
    }

    var precipUnit: PrecipUnit {
        didSet {
            guard oldValue != precipUnit else { return }
            UserDefaults.standard.set(precipUnit.rawValue, forKey: Self.precipUnitKey); CloudSync.push()
            Fmt.precipUnit = precipUnit
            // Amounts are fetched in the requested unit, so refetch.
            Task { await reload() }
        }
    }

    var pressureUnit: PressureUnit {
        didSet {
            guard oldValue != pressureUnit else { return }
            UserDefaults.standard.set(pressureUnit.rawValue, forKey: Self.pressureUnitKey); CloudSync.push()
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
            UserDefaults.standard.set(timeFormat.rawValue, forKey: Self.timeFormatKey); CloudSync.push()
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
        didSet { UserDefaults.standard.set(radarAutoplay, forKey: Self.radarAutoplayKey); CloudSync.push() }
    }

    /// Rain & advisory notifications via background refresh. Turning it on
    /// asks for permission; a denial flips the toggle straight back so the UI
    /// never claims something the system won't allow.
    var notificationsEnabled: Bool {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            RainAlertsService.isEnabled = notificationsEnabled
            if notificationsEnabled {
                Task { [weak self] in
                    let granted = await RainAlertsService.requestPermission()
                    if !granted { self?.notificationsEnabled = false }
                }
            } else {
                RainAlertsService.cancelScheduledChecks()
            }
        }
    }

    /// The daily brief as a notification, at the user's chosen time.
    var morningDigestEnabled: Bool {
        didSet {
            guard oldValue != morningDigestEnabled else { return }
            NotificationPlanner.digestEnabled = morningDigestEnabled
            if morningDigestEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    if await RainAlertsService.requestPermission() { replanNotifications() }
                    else { morningDigestEnabled = false }
                }
            } else {
                NotificationPlanner.cancelDigest()
            }
        }
    }

    /// When the digest arrives; only the hour and minute matter.
    var digestTime: Date {
        didSet {
            let cal = Calendar.current
            NotificationPlanner.digestMinutes =
                cal.component(.hour, from: digestTime) * 60 + cal.component(.minute, from: digestTime)
            replanNotifications()
        }
    }

    /// "Golden hour soon" — twenty minutes before the light turns.
    var goldenHourEnabled: Bool {
        didSet {
            guard oldValue != goldenHourEnabled else { return }
            NotificationPlanner.goldenHourEnabled = goldenHourEnabled
            if goldenHourEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    if await RainAlertsService.requestPermission() { replanNotifications() }
                    else { goldenHourEnabled = false }
                }
            } else {
                NotificationPlanner.cancelGoldenHour()
            }
        }
    }

    /// Rebuild the scheduled notifications from the on-screen device bundle.
    private func replanNotifications() {
        guard let bundle, isShowingDeviceLocation || locationManager.isDenied else { return }
        NotificationPlanner.refresh(bundle: bundle,
                                    usesFahrenheit: temperatureUnit == .fahrenheit)
    }

    var showTrendCard: Bool {
        didSet { UserDefaults.standard.set(showTrendCard, forKey: Self.showTrendKey); CloudSync.push() }
    }

    /// The composed prose standfirst under the hero.
    var showDailyBrief: Bool {
        didSet { UserDefaults.standard.set(showDailyBrief, forKey: Self.showBriefKey); CloudSync.push() }
    }

    var showRadarPreview: Bool {
        didSet { UserDefaults.standard.set(showRadarPreview, forKey: Self.showRadarPreviewKey); CloudSync.push() }
    }

    var showWindCompass: Bool {
        didSet { UserDefaults.standard.set(showWindCompass, forKey: Self.showWindKey); CloudSync.push() }
    }

    var showSunCard: Bool {
        didSet { UserDefaults.standard.set(showSunCard, forKey: Self.showSunKey); CloudSync.push() }
    }

    var cardOrder: [HomeCard] {
        didSet {
            UserDefaults.standard.set(cardOrder.map(\.rawValue), forKey: Self.cardOrderKey); CloudSync.push()
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
        // Default to following the system setting; users who explicitly chose
        // S/M/L/XL keep their stored choice.
        textSize = TextSize(rawValue: defaults.string(forKey: Self.textSizeKey) ?? "")
            ?? .system
        timeFormat = TimeFormat(rawValue: defaults.string(forKey: Self.timeFormatKey) ?? "")
            ?? .system
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        radarAutoplay = defaults.object(forKey: Self.radarAutoplayKey) as? Bool ?? true
        notificationsEnabled = RainAlertsService.isEnabled
        morningDigestEnabled = NotificationPlanner.digestEnabled
        goldenHourEnabled = NotificationPlanner.goldenHourEnabled
        digestTime = Calendar.current.date(
            bySettingHour: NotificationPlanner.digestMinutes / 60,
            minute: NotificationPlanner.digestMinutes % 60,
            second: 0, of: Date()) ?? Date()
        showTrendCard = defaults.object(forKey: Self.showTrendKey) as? Bool ?? true
        showDailyBrief = defaults.object(forKey: Self.showBriefKey) as? Bool ?? true
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
        // Draw last session's reading straight away — the location fix and the
        // network round trip then happen under real content instead of under a
        // spinner. Anything that arrives after this replaces it in place.
        if bundle == nil, let cached = await openingBundle() {
            selectedPlace = cached.place
            bundle = cached
            phase = .loaded
        }
        if useDeviceLocation, !locationManager.isDenied {
            await useCurrentLocation()
            if case .loaded = phase { return }
            // The device place resolved but its fetch failed (network blip).
            // Keep it selected while there's content on screen — refresh()
            // recovers it when the network returns. Falling through here used
            // to silently and stickily switch the app to a saved city. Only an
            // actual location failure (isShowingDeviceLocation still false) or
            // a truly empty screen goes on to the fallbacks.
            if isShowingDeviceLocation, bundle != nil { return }
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

    /// What to draw before anything has been fetched: the cached forecast for
    /// the place this launch is heading to (the remembered device location when
    /// that's where we start), falling back to whatever was shown last.
    private func openingBundle() async -> WeatherBundle? {
        if useDeviceLocation, !locationManager.isDenied,
           let known = locationManager.lastKnownPlace,
           let cached = await WeatherCache.shared.bundle(for: known, units: cacheUnits) {
            return cached
        }
        return await WeatherCache.shared.mostRecent(units: cacheUnits)
    }

    func useCurrentLocation() async {
        if bundle == nil { phase = .loading }
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
        // Everything after an await checks against these: if a newer selection
        // or a unit change happened while this request was in flight, its
        // response is stale and must not repaint the screen, retarget the
        // widgets, or become the launch cache.
        let requestedID = place.id
        let requestedUnits = cacheUnits
        // A previous load's enrich must not outlive this newer request.
        enrichTask?.cancel()
        // Switching places: show that place's last reading immediately rather
        // than an empty screen while the network answers.
        if bundle?.place.id != place.id,
           let cached = await WeatherCache.shared.bundle(for: place, units: requestedUnits),
           selectedPlace?.id == requestedID {
            bundle = cached
            phase = .loaded
        } else if showSpinner, bundle == nil {
            phase = .loading
        }
        do {
            var result = try await weatherService.fetchForecast(
                for: place,
                temperatureUnit: temperatureUnit,
                speedUnit: speedUnit,
                precipUnit: precipUnit
            )
            guard selectedPlace?.id == requestedID, cacheUnits == requestedUnits else { return }
            // Alerts arrive via enrich, not the forecast — carry the on-screen
            // ones forward (dropping any that have expired) so a reload doesn't
            // blink the banner out, and a failed alerts re-fetch doesn't lose a
            // warning that's still in force. A successful empty answer from
            // enrich still clears it.
            if bundle?.place.id == result.place.id {
                result.alerts = bundle?.alerts?.filter { ($0.ends ?? .distantFuture) > Date() }
            }
            bundle = result
            phase = .loaded
            // Units always reach the widgets, even when the device-location
            // snapshot publish below is gated off.
            WeatherSnapshotStore.writeUnitPrefs(
                temperatureUnit: temperatureUnit.apiValue,
                windSpeedUnit: speedUnit.apiValue,
                precipitationUnit: precipUnit.apiValue(temperatureUnit: temperatureUnit))
            publishToWidgets(result)
            if persist { addSavedPlace(result.place) }
            Task { await WeatherCache.shared.save(result, units: requestedUnits) }
            enrich(result, units: requestedUnits)
        } catch {
            // A stale request that fails must not stamp .failed over a newer
            // selection's loaded screen.
            guard selectedPlace?.id == requestedID, cacheUnits == requestedUnits else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Air quality and the nearest station's observation, applied to the bundle
    /// that's already on screen. Kept off the load path because the observation
    /// is a three-request chain that used to gate the first paint.
    ///
    /// `units` is the load's own stamp, checked again when the extras land: the
    /// chain can run for many seconds, and a °F bundle enriched after a flip to
    /// °C must be dropped, not repainted, republished, and cached under a °C
    /// stamp it doesn't match.
    private func enrich(_ base: WeatherBundle, units: WeatherCache.Units) {
        enrichTask?.cancel()
        enrichTask = Task { [weak self] in
            guard let self else { return }
            let extras = await weatherService.fetchExtras(for: base.place)
            guard !Task.isCancelled, !extras.isEmpty,
                  let current = bundle, current.place.id == base.place.id,
                  current.fetchedAt == base.fetchedAt,
                  cacheUnits == units
            else { return }
            let enriched = current.applying(airQuality: extras.airQuality,
                                            observedCode: extras.observedCode,
                                            alerts: extras.alerts)
            bundle = enriched
            publishToWidgets(enriched)
            Task { await WeatherCache.shared.save(enriched, units: units) }
        }
    }

    /// Widgets follow the device location: browsing another city doesn't
    /// retarget them (unless location is unavailable, in which case they follow
    /// whatever's viewed so they're never stale).
    private func publishToWidgets(_ bundle: WeatherBundle) {
        guard isShowingDeviceLocation || locationManager.isDenied else { return }
        WeatherWidgetSnapshot.publish(from: bundle,
                                      temperatureUnit: temperatureUnit,
                                      speedUnit: speedUnit,
                                      precipUnit: precipUnit)
        // Scheduled notifications ride the same device-place gate; the
        // planner itself checks whether each one is enabled.
        NotificationPlanner.refresh(bundle: bundle,
                                    usesFahrenheit: temperatureUnit == .fahrenheit)
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
        // Keep the widget's picker in step even if the list last changed
        // before the mirror existed.
        WeatherSnapshotStore.writeSavedPlaces(places)
    }

    private func persistSavedPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: Self.savedPlacesKey)
        }
        // Mirror for the widget's city picker, and up to iCloud for the
        // user's other devices.
        WeatherSnapshotStore.writeSavedPlaces(savedPlaces)
        CloudSync.push()
    }

    /// Re-read local state after iCloud delivered newer values from another
    /// device, and refresh what's on screen if the settings moved.
    func adoptCloudChanges() {
        let defaults = UserDefaults.standard
        loadSavedPlaces()
        let cloudTemp = TemperatureUnit(rawValue: defaults.string(forKey: Self.tempUnitKey) ?? "")
        let cloudSpeed = SpeedUnit(rawValue: defaults.string(forKey: Self.speedUnitKey) ?? "")
        let cloudPrecip = PrecipUnit(rawValue: defaults.string(forKey: Self.precipUnitKey) ?? "")
        var unitsMoved = false
        if let cloudTemp, cloudTemp != temperatureUnit { temperatureUnit = cloudTemp; unitsMoved = true }
        if let cloudSpeed, cloudSpeed != speedUnit { speedUnit = cloudSpeed; unitsMoved = true }
        if let cloudPrecip, cloudPrecip != precipUnit { precipUnit = cloudPrecip; unitsMoved = true }
        // The unit didSets each kick a reload; nothing more to do here.
        _ = unitsMoved
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
