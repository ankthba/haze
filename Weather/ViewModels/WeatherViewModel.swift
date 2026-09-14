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
    private static let whimsyKey = Voice.defaultsKey
    static let forecastSourceKey = "forecast_source"

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
    /// `.system` (the default) passes the device's own setting through, which
    /// is what makes the accessibility sizes AX1 to AX5 reachable; a forced size
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

        /// The Mac has no Dynamic Type; the serif faces scale by this instead.
        var macScale: CGFloat {
            switch self {
            case .system, .standard: 1
            case .small: 0.92
            case .large: 1.1
            case .extraLarge: 1.22
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
        // the brief skips it; two copies stacked read as a glitch.
        briefText = DailyBrief.compose(bundle: bundle,
                                       nowcast: showDailyBrief && nowcast != nil ? nil : nowcast,
                                       usesFahrenheit: temperatureUnit == .fahrenheit,
                                       voice: voice)
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

    /// True while a saved place stands in for a device location we wanted but
    /// couldn't resolve. The distinction from a place the reader actually
    /// chose is what keeps the fallback temporary: `refresh` retries the fix
    /// while this is set, so one flaky launch fix no longer parks the app on
    /// `savedPlaces.first` (whatever city was searched last) for the rest of
    /// the session, widgets and notifications included.
    private(set) var isStandingInForDeviceLocation = false

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
    /// The source is part of the stamp too: switching models must not flash
    /// the other model's forecast under the new attribution line.
    private var cacheUnits: WeatherCache.Units {
        WeatherCache.Units(temperature: temperatureUnit, speed: speedUnit, precip: precipUnit,
                           source: effectiveSource)
    }

    // MARK: - Forecast source

    /// The model the user asked for. `effectiveSource` is what actually gets
    /// fetched: WeatherNext needs an API key, and the choice is kept even
    /// while no key is configured so it lights up the moment one is pasted.
    var forecastSource: ForecastSource {
        didSet {
            guard oldValue != forecastSource else { return }
            UserDefaults.standard.set(forecastSource.rawValue, forKey: Self.forecastSourceKey); CloudSync.push()
            reloadUnlessAdoptingCloud()
        }
    }

    /// True while `adoptCloudChanges` is writing several settings at once.
    /// Each unit didSet below would otherwise start its own reload, and the
    /// concurrent loads all miss the snapshot the first one has not saved
    /// yet: one iCloud pull could cost several full WeatherNext fetches.
    private var isAdoptingCloudSettings = false

    private func reloadUnlessAdoptingCloud() {
        guard !isAdoptingCloudSettings else { return }
        Task { await reload() }
    }

    var effectiveSource: ForecastSource { .effective(for: forecastSource) }

    /// A pasted Google Weather API key, bound to the Settings field. Local
    /// only: it never goes through CloudSync. The key is stored on every edit
    /// so the Settings caption follows the typing, but the reload it triggers
    /// waits for the typing to stop: a WeatherNext refresh is about 13 calls,
    /// and firing one per character would spend them on partial keys and let
    /// a late failure stamp `.failed` over the final key's loaded page.
    var weatherNextKeyOverride: String {
        didSet {
            let trimmed = weatherNextKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != weatherNextKeyOverride { weatherNextKeyOverride = trimmed }
            let defaults = UserDefaults.standard
            let before = WeatherNextKey.value
            if trimmed.isEmpty {
                defaults.removeObject(forKey: WeatherNextKey.overrideDefaultsKey)
            } else {
                defaults.set(trimmed, forKey: WeatherNextKey.overrideDefaultsKey)
            }
            keyReloadTask?.cancel()
            guard forecastSource == .weatherNext, WeatherNextKey.value != before else { return }
            keyReloadTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await reload()
            }
        }
    }
    private var keyReloadTask: Task<Void, Never>?

    var temperatureUnit: TemperatureUnit {
        didSet {
            guard oldValue != temperatureUnit else { return }
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: Self.tempUnitKey); CloudSync.push()
            Fmt.temperatureUnit = temperatureUnit
            reloadUnlessAdoptingCloud()
        }
    }

    var speedUnit: SpeedUnit {
        didSet {
            guard oldValue != speedUnit else { return }
            UserDefaults.standard.set(speedUnit.rawValue, forKey: Self.speedUnitKey); CloudSync.push()
            reloadUnlessAdoptingCloud()
        }
    }

    // MARK: - Appearance & behavior settings

    var textSize: TextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey); CloudSync.push()
            applyMacTextScale()
        }
    }

    private func applyMacTextScale() {
        #if os(macOS)
        UIPrefs.shared.textScale = textSize.macScale
        #endif
    }

    var precipUnit: PrecipUnit {
        didSet {
            guard oldValue != precipUnit else { return }
            UserDefaults.standard.set(precipUnit.rawValue, forKey: Self.precipUnitKey); CloudSync.push()
            Fmt.precipUnit = precipUnit
            // Amounts are fetched in the requested unit, so refetch.
            reloadUnlessAdoptingCloud()
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

    /// How old a stored Google WeatherNext snapshot may be and still be
    /// re-adapted instead of refetched on a load the user did not ask for
    /// (a unit change, a launch, the timer, returning to the foreground). The
    /// refresh interval is the natural window: the user has already said how
    /// stale a page may get before it is worth a fetch, and every hourly page
    /// Google serves counts against a per-day quota, so a unit flip that
    /// converts locally should never spend one. An explicit refresh passes 0.
    private var automaticSnapshotMaxAge: TimeInterval { TimeInterval(refreshMinutes * 60) }

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

    /// "Golden hour soon", twenty minutes before the light turns.
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

    /// Sunset and sunrise quality alerts: a heads-up before the next event
    /// that clears the user's chosen bar.
    var sunsetAlertEnabled: Bool {
        didSet {
            guard oldValue != sunsetAlertEnabled else { return }
            NotificationPlanner.sunsetAlertEnabled = sunsetAlertEnabled
            if sunsetAlertEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    if await RainAlertsService.requestPermission() { replanNotifications() }
                    else { sunsetAlertEnabled = false }
                }
            } else {
                NotificationPlanner.cancelSunAlert(kind: .sunset)
            }
        }
    }

    var sunriseAlertEnabled: Bool {
        didSet {
            guard oldValue != sunriseAlertEnabled else { return }
            NotificationPlanner.sunriseAlertEnabled = sunriseAlertEnabled
            if sunriseAlertEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    if await RainAlertsService.requestPermission() { replanNotifications() }
                    else { sunriseAlertEnabled = false }
                }
            } else {
                NotificationPlanner.cancelSunAlert(kind: .sunrise)
                // The night-before heads-up hangs off this switch, so it goes too.
                NotificationPlanner.cancelSunriseEvening()
            }
        }
    }

    /// The night-before heads-up for a promising sunrise, so the alarm can
    /// actually be set. Rides on the sunrise alert's own quality bar.
    var sunriseEveningEnabled: Bool {
        didSet {
            guard oldValue != sunriseEveningEnabled else { return }
            NotificationPlanner.sunriseEveningEnabled = sunriseEveningEnabled
            if sunriseEveningEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    if await RainAlertsService.requestPermission() { replanNotifications() }
                    else { sunriseEveningEnabled = false }
                }
            } else {
                NotificationPlanner.cancelSunriseEvening()
            }
        }
    }

    /// "Don't wake me before": on, a sunrise alert that would fire earlier
    /// than `sunriseEarliestTime` is skipped rather than delayed (see
    /// NotificationPlanner.sunriseEarliestMinutes). Stored as 0 when off, so
    /// the two properties here are one setting in the planner.
    var sunriseEarliestEnabled: Bool {
        didSet {
            guard oldValue != sunriseEarliestEnabled else { return }
            NotificationPlanner.sunriseEarliestMinutes =
                sunriseEarliestEnabled ? Self.minutes(from: sunriseEarliestTime) : 0
            replanNotifications()
        }
    }

    var sunriseEarliestTime: Date {
        didSet {
            guard sunriseEarliestEnabled else { return }
            NotificationPlanner.sunriseEarliestMinutes = Self.minutes(from: sunriseEarliestTime)
            replanNotifications()
        }
    }

    /// Minutes from midnight, the shape every scheduled time is stored in.
    private static func minutes(from date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    /// When that heads-up arrives; only the hour and minute matter.
    var sunriseEveningTime: Date {
        didSet {
            let cal = Calendar.current
            NotificationPlanner.sunriseEveningMinutes =
                cal.component(.hour, from: sunriseEveningTime) * 60
                + cal.component(.minute, from: sunriseEveningTime)
            replanNotifications()
        }
    }

    var sunsetAlertLeadMinutes: Int {
        didSet {
            guard oldValue != sunsetAlertLeadMinutes else { return }
            NotificationPlanner.sunsetAlertLeadMinutes = sunsetAlertLeadMinutes
            replanNotifications()
        }
    }

    var sunriseAlertLeadMinutes: Int {
        didSet {
            guard oldValue != sunriseAlertLeadMinutes else { return }
            NotificationPlanner.sunriseAlertLeadMinutes = sunriseAlertLeadMinutes
            replanNotifications()
        }
    }

    var sunsetAlertGate: SunQuality.AlertGate {
        didSet {
            guard oldValue != sunsetAlertGate else { return }
            NotificationPlanner.sunsetAlertGate = sunsetAlertGate
            replanNotifications()
        }
    }

    var sunriseAlertGate: SunQuality.AlertGate {
        didSet {
            guard oldValue != sunriseAlertGate else { return }
            NotificationPlanner.sunriseAlertGate = sunriseAlertGate
            replanNotifications()
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

    /// Whimsy mode: the same forecast, told with a lighter step. Every
    /// composed sentence in the app is written in both registers, so this
    /// only changes wording. Flipping it recomposes the brief in place and
    /// rebuilds the scheduled notifications so the queued digest doesn't
    /// arrive tomorrow morning still speaking in the old voice.
    var whimsyEnabled: Bool {
        didSet {
            guard oldValue != whimsyEnabled else { return }
            UserDefaults.standard.set(whimsyEnabled, forKey: Self.whimsyKey)
            CloudSync.push()
            refreshDerived()
            replanNotifications()
        }
    }

    /// The register every composed sentence is written in.
    var voice: Voice { whimsyEnabled ? .whimsical : .editorial }

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
        sunsetAlertEnabled = NotificationPlanner.sunsetAlertEnabled
        sunriseAlertEnabled = NotificationPlanner.sunriseAlertEnabled
        sunsetAlertLeadMinutes = NotificationPlanner.sunsetAlertLeadMinutes
        sunriseAlertLeadMinutes = NotificationPlanner.sunriseAlertLeadMinutes
        sunsetAlertGate = NotificationPlanner.sunsetAlertGate
        sunriseAlertGate = NotificationPlanner.sunriseAlertGate
        sunriseEveningEnabled = NotificationPlanner.sunriseEveningEnabled
        let earliest = NotificationPlanner.sunriseEarliestMinutes
        sunriseEarliestEnabled = earliest > 0
        sunriseEarliestTime = Calendar.current.date(
            bySettingHour: (earliest > 0 ? earliest : 6 * 60) / 60,
            minute: (earliest > 0 ? earliest : 6 * 60) % 60,
            second: 0, of: Date()) ?? Date()
        sunriseEveningTime = Calendar.current.date(
            bySettingHour: NotificationPlanner.sunriseEveningMinutes / 60,
            minute: NotificationPlanner.sunriseEveningMinutes % 60,
            second: 0, of: Date()) ?? Date()
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
        whimsyEnabled = defaults.bool(forKey: Self.whimsyKey)
        // A stored `.weatherNext` from before the feature was parked would
        // otherwise leave Settings describing a source the app is not using,
        // so the preference itself is brought back to Classic.
        let storedSource = ForecastSource(rawValue: defaults.string(forKey: Self.forecastSourceKey) ?? "")
            ?? .classic
        forecastSource = WeatherNextFeature.isEnabled ? storedSource : .classic
        weatherNextKeyOverride = defaults.string(forKey: WeatherNextKey.overrideDefaultsKey) ?? ""
        // Stored order, tolerant of future cards: unknown names are dropped and
        // any cards missing from the stored list are appended in default order.
        let stored = (defaults.stringArray(forKey: Self.cardOrderKey) ?? [])
            .compactMap(HomeCard.init(rawValue:))
        cardOrder = stored + HomeCard.allCases.filter { !stored.contains($0) }
        Fmt.timeFormat = timeFormat
        Fmt.temperatureUnit = temperatureUnit
        Fmt.precipUnit = precipUnit
        Fmt.pressureUnit = pressureUnit
        Haptics.isEnabled = hapticsEnabled
        applyMacTextScale()
        loadSavedPlaces()
    }

    // MARK: - Lifecycle

    /// Decide what to show on first launch: device location, else last/first saved place.
    func bootstrap() async {
        // Draw last session's reading straight away: the location fix and the
        // network round trip then happen under real content instead of under a
        // spinner. Anything that arrives after this replaces it in place.
        if bundle == nil, let cached = await openingBundle() {
            selectedPlace = cached.place
            bundle = cached
            phase = .loaded
        }
        var wantedDeviceLocation = false
        if useDeviceLocation, !locationManager.isDenied {
            await useCurrentLocation()
            if case .loaded = phase { return }
            // The device place resolved but its fetch failed (network blip).
            // Keep it selected while there's content on screen, because refresh()
            // recovers it when the network returns.
            if isShowingDeviceLocation, bundle != nil { return }
            // Anything else here means we asked for the device location and
            // have no working page for it. Whatever is shown below is a
            // stand-in, not a choice, so it must not stick.
            wantedDeviceLocation = true
        }
        if let first = savedPlaces.first {
            await select(first)
        } else {
            // Sensible default so the app is never empty.
            await select(Place(name: "San Francisco", admin1: "California",
                               country: "United States", countryCode: "US",
                               latitude: 37.7749, longitude: -122.4194, timezone: nil))
        }
        // After `select`, which clears the flag for a deliberate pick.
        isStandingInForDeviceLocation = wantedDeviceLocation
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

    /// `userInitiated` is only true on the explicit refresh path (see
    /// `refresh`); a location fix on its own is not a request for new numbers.
    /// Returns true when the fix itself resolved, so callers can tell a
    /// location failure from a forecast failure.
    @discardableResult
    func useCurrentLocation(userInitiated: Bool = false) async -> Bool {
        if bundle == nil { phase = .loading }
        do {
            let place = try await locationManager.requestCurrentPlace()
            isShowingDeviceLocation = true
            isStandingInForDeviceLocation = false
            deviceSummary = nil
            await load(place: place, persist: false, userInitiated: userInitiated)
            return true
        } catch {
            // A failed fix with a page already up is not worth an error
            // screen: those numbers are still good and the next refresh tries
            // again. Only an empty screen has nothing better to show.
            if bundle == nil { phase = .failed(error.localizedDescription) }
            return false
        }
    }

    func select(_ place: Place) async {
        isShowingDeviceLocation = false
        // A deliberate pick, so the stand-in retry stops here.
        isStandingInForDeviceLocation = false
        await load(place: place, persist: true)
        await refreshDeviceSummary()
    }

    /// Re-fetch the selected place. Every settings didSet above calls this
    /// with the default, and so does pull to refresh, which must pass
    /// `userInitiated: true`: only a deliberate pull bypasses the WeatherNext
    /// snapshot, a settings change re-runs the adapter on the stored one.
    func reload(userInitiated: Bool = false) async {
        guard let place = selectedPlace else { return }
        await load(place: place, persist: false, showSpinner: bundle == nil,
                   userInitiated: userInitiated)
    }

    /// Foreground / periodic refresh. When the screen is the device location,
    /// re-resolve the location itself first, so moving cities never leaves the
    /// app (or widget) showing where you used to be. The scene and timer
    /// callers take the default; the Refresh command and menu bar button pass
    /// `userInitiated: true` so the page really goes to Google.
    func refresh(userInitiated: Bool = false) async {
        if isShowingDeviceLocation || isStandingInForDeviceLocation,
           !locationManager.isDenied {
            if await useCurrentLocation(userInitiated: userInitiated) { return }
            // The fix failed again. On a stand-in page, fall through so those
            // numbers still refresh; the next tick retries the fix.
            guard isStandingInForDeviceLocation else { return }
        }
        await reload(userInitiated: userInitiated)
        await refreshDeviceSummary()
    }

    /// Fetch (or re-fetch) the device location's current conditions for the
    /// return panel. Cheap single call, cached for 15 minutes, and only runs
    /// when permission is already granted so browsing never triggers a prompt.
    func refreshDeviceSummary() async {
        guard !isShowingDeviceLocation else { return }
        guard locationManager.authorizationStatus.isAuthorizedForApp else { return }
        if let summary = deviceSummary,
           Date().timeIntervalSince(summary.fetchedAt) < 15 * 60 { return }
        // Never user-initiated: the panel is a glance, so a fresh-enough
        // snapshot (or the page's own recent fetch) is always good enough.
        guard let place = try? await locationManager.requestCurrentPlace(),
              let current = try? await weatherService.fetchCurrentSummary(
                  for: place, temperatureUnit: temperatureUnit, source: effectiveSource,
                  maxAge: automaticSnapshotMaxAge) else { return }
        deviceSummary = DeviceSummary(
            place: place,
            temperature: current.temperature,
            condition: WeatherCondition(code: current.code, isDay: current.isDay),
            fetchedAt: Date())
    }

    private func load(place: Place, persist: Bool, showSpinner: Bool = true,
                      userInitiated: Bool = false) async {
        selectedPlace = place
        // Everything after an await checks against these: if a newer selection,
        // a unit change or a source switch happened while this request was in flight, its
        // response is stale and must not repaint the screen, retarget the
        // widgets, or become the launch cache.
        let requestedID = place.id
        let requestedUnits = cacheUnits
        // A previous load's enrich must not outlive this newer request.
        enrichTask?.cancel()
        // Switching places, or switching the source on the same place: show
        // that place's last reading under the requested stamp immediately
        // rather than an empty screen while the network answers. Without one,
        // a same-place source switch clears the screen instead of leaving the
        // other model's numbers under the new attribution; the spinner (and,
        // if the fetch fails, the error) then say what is happening.
        //
        // A Classic Haze page carrying a `sourceNotice` is what a WeatherNext
        // request produced (the fallback path in WeatherService.fetchForecast),
        // so it counts as matching a WeatherNext stamp: a refresh must not
        // blank it to a spinner while Google is retried.
        let displayedMatches = bundle.map {
            $0.place.id == place.id
                && (($0.source ?? .classic) == requestedUnits.source
                    || ($0.sourceNotice != nil && requestedUnits.source == .weatherNext))
        } ?? false
        // Toggling back to Classic Haze makes a fallback's notice meaningless
        // (the page is now the source that was asked for), so it goes at once
        // rather than lingering until the network answers.
        if requestedUnits.source == .classic, bundle?.sourceNotice != nil {
            bundle?.sourceNotice = nil
        }
        if !displayedMatches {
            if let cached = await WeatherCache.shared.bundle(for: place, units: requestedUnits),
               selectedPlace?.id == requestedID {
                bundle = cached
                phase = .loaded
            } else if bundle?.place.id == place.id {
                bundle = nil
                phase = .loading
            } else if showSpinner, bundle == nil {
                phase = .loading
            }
        }
        do {
            var result = try await weatherService.fetchForecast(
                for: place,
                temperatureUnit: temperatureUnit,
                speedUnit: speedUnit,
                precipUnit: precipUnit,
                source: effectiveSource,
                // The bundle cache above is keyed by units, so a unit flip is
                // always a miss there; the Google snapshot is not, and it is
                // what keeps that flip free of network calls.
                weatherNextMaxAge: userInitiated ? 0 : automaticSnapshotMaxAge
            )
            guard selectedPlace?.id == requestedID, cacheUnits == requestedUnits else { return }
            // Alerts arrive via enrich, not the forecast, so carry the on-screen
            // ones forward (dropping any that have expired) so a reload doesn't
            // blink the banner out, and a failed alerts re-fetch doesn't lose a
            // warning that's still in force. A successful empty answer from
            // enrich still clears it.
            if bundle?.place.id == result.place.id {
                result.alerts = bundle?.alerts?.filter { ($0.ends ?? .distantFuture) > Date() }
            }
            // `result` may be Classic Haze with a `sourceNotice` when WeatherNext
            // was requested and failed: that is still a forecast, so it is shown
            // and marked .loaded (never .failed), and it is cached under the
            // requested (WeatherNext) stamp below so the next launch, and
            // openingBundle, draw it immediately. A later WeatherNext success
            // lands here the same way and simply replaces it.
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
                                            observation: extras.observation,
                                            observedCode: extras.observedCode,
                                            alerts: extras.alerts,
                                            temperatureUnit: temperatureUnit,
                                            speedUnit: speedUnit)
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
        let cloudSource = ForecastSource(rawValue: defaults.string(forKey: Self.forecastSourceKey) ?? "")
        // The didSets hold their reloads while these land, then one reload
        // covers every setting that moved.
        isAdoptingCloudSettings = true
        var unitsMoved = false
        if let cloudTemp, cloudTemp != temperatureUnit { temperatureUnit = cloudTemp; unitsMoved = true }
        if let cloudSpeed, cloudSpeed != speedUnit { speedUnit = cloudSpeed; unitsMoved = true }
        if let cloudPrecip, cloudPrecip != precipUnit { precipUnit = cloudPrecip; unitsMoved = true }
        if let cloudSource, cloudSource != forecastSource { forecastSource = cloudSource; unitsMoved = true }
        isAdoptingCloudSettings = false
        // The voice is prose, not a unit: adopting it recomposes the brief in
        // place rather than kicking a reload.
        let cloudWhimsy = defaults.bool(forKey: Self.whimsyKey)
        if cloudWhimsy != whimsyEnabled { whimsyEnabled = cloudWhimsy }
        if unitsMoved { Task { await reload() } }
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
        // The Google snapshot is hundreds of kilobytes a place and nothing
        // else would ever reclaim it.
        WeatherNextRawCache.shared.remove(for: place)
    }

    func moveSavedPlace(from offsets: IndexSet, to destination: Int) {
        savedPlaces.move(fromOffsets: offsets, toOffset: destination)
        persistSavedPlaces()
    }

    func isSaved(_ place: Place) -> Bool {
        savedPlaces.contains { $0.id == place.id }
    }
}
