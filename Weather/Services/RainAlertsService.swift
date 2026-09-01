//
//  RainAlertsService.swift
//  Weather
//
//  Background awareness: while the app is closed, a periodic BGAppRefresh
//  check fetches one cheap nowcast (+ NWS alerts) for the remembered device
//  place and posts a local notification when rain is about to start or a new
//  advisory lands. Each rain window and each alert id notifies once.
//
//  iOS decides when (and whether) background refreshes actually run: this is
//  best-effort by platform design, not a guaranteed schedule.
//

import Foundation
import BackgroundTasks
import UserNotifications
import CoreLocation

@MainActor
enum RainAlertsService {
    static let taskIdentifier = "com.aniketh.Weather.refresh"

    private static let enabledKey = "notifications_enabled"
    private static let notifiedRainKey = "notified_rain_window_v1"
    private static let notifiedAlertsKey = "notified_alert_ids_v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: - Lifecycle

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier,
                                        using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            handle(refresh)
        }
    }

    /// Asks for notification permission; reports whether it was granted.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        return granted
    }

    /// Queue the next background check. Called when the app backgrounds and
    /// after each background run.
    static func scheduleNextCheck() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelScheduledChecks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - The background check

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextCheck()
        let work = Task {
            await runCheck()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// One cheap fetch for the device place; fires at most one rain and one
    /// alert notification per run.
    static func runCheck() async {
        guard isEnabled,
              let place = LocationManager.rememberedDevicePlace() else { return }

        // Exactly two requests: the minimal nowcast and the alerts feed, not
        // the full extras fetch, whose AQI + station chain would be discarded.
        async let minutely = fetchMinutely(place: place)
        async let alerts = WeatherService().fetchAlerts(place: place)

        if let minutely = await minutely {
            await notifyRainIfNeeded(minutely: minutely, place: place)
        }
        if let alerts = await alerts {
            await notifyAlertsIfNeeded(alerts, place: place)
        }

        // Rebuild the scheduled digest / golden-hour from the freshest cached
        // forecast, so an overnight background run keeps tomorrow's digest
        // current. (Raw-string unit keys mirror WeatherViewModel's storage.)
        let d = UserDefaults.standard
        let units = WeatherCache.Units(
            temperature: TemperatureUnit(rawValue: d.string(forKey: "temp_unit") ?? "") ?? .fahrenheit,
            speed: SpeedUnit(rawValue: d.string(forKey: "speed_unit") ?? "") ?? .mph,
            precip: PrecipUnit(rawValue: d.string(forKey: "precip_unit") ?? "") ?? .auto)
        if let cached = await WeatherCache.shared.bundle(for: place, units: units) {
            NotificationPlanner.refresh(bundle: cached,
                                        usesFahrenheit: units.temperature == .fahrenheit)
        }
    }

    // MARK: Rain

    private static func notifyRainIfNeeded(minutely: [MinutePoint], place: Place) async {
        // Fixed mm threshold: this fetch always requests millimetres.
        guard let nowcast = RainNowcast.compute(minutely: minutely, wetThreshold: 0.12),
              case .starting(let start) = leadPhase(nowcast.phase),
              start.timeIntervalSinceNow > 0,
              start.timeIntervalSinceNow < 45 * 60 else { return }

        // One notification per rain window: windows within 30 min of the last
        // notified one count as the same shower.
        let last = UserDefaults.standard.double(forKey: notifiedRainKey)
        guard abs(start.timeIntervalSince1970 - last) > 30 * 60 else { return }
        UserDefaults.standard.set(start.timeIntervalSince1970, forKey: notifiedRainKey)

        let timezone = place.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let voice = Voice.current
        let at = Fmt.time(start, timezone: timezone)
        let content = UNMutableNotificationContent()
        content.title = voice.pick("Rain on the way", whimsy: "Rain's about to turn up")
        content.body = voice.pick(
            "Starting around \(at) near \(place.name).",
            whimsy: "It arrives around \(at) near \(place.name), so take an umbrella.")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "rain-\(Int(start.timeIntervalSince1970))",
                                  content: content, trigger: nil))
    }

    /// Collapses the phases to "does rain begin, and when".
    private static func leadPhase(_ phase: RainNowcast.Phase) -> RainNowcast.Phase {
        switch phase {
        case .startingAndEnding(let start, _): .starting(start)
        default: phase
        }
    }

    // MARK: Alerts

    private static func notifyAlertsIfNeeded(_ alerts: [WeatherAlert], place: Place) async {
        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedAlertsKey) ?? [])
        // Prune to what's still in force: expired ids fall out naturally,
        // active ones stay deduped, and the set is bounded by the number of
        // concurrent alerts. (A hard cap-and-wipe re-notified everything mid-
        // storm, exactly when duplicates are most annoying.)
        notified.formIntersection(alerts.map(\.id))

        guard let fresh = alerts.first(where: { !notified.contains($0.id) && $0.isUrgent })
            ?? alerts.first(where: { !notified.contains($0.id) }) else {
            UserDefaults.standard.set(Array(notified), forKey: notifiedAlertsKey)
            return
        }
        notified.insert(fresh.id)
        UserDefaults.standard.set(Array(notified), forKey: notifiedAlertsKey)

        // Advisories are the one place the whimsical voice never reaches: a
        // severe-weather headline is not the place for a softer register.
        let content = UNMutableNotificationContent()
        content.title = fresh.event
        content.body = fresh.headline ?? "Active advisory for \(place.name). Open Haze for details."
        // Critical sound needs an Apple-approved entitlement we don't have, so
        // it would be silently downgraded. Time-sensitive is the honest tier.
        content.sound = .default
        if fresh.isUrgent { content.interruptionLevel = .timeSensitive }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "alert-\(fresh.id)",
                                  content: content, trigger: nil))
    }

    // MARK: Minimal nowcast fetch

    /// The smallest possible Open-Meteo request: 15-minute precipitation only,
    /// always in millimetres so the wet threshold is unit-stable.
    private static func fetchMinutely(place: Place) async -> [MinutePoint]? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "12"),
            .init(name: "precipitation_unit", value: "mm"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }

        struct Response: Decodable {
            struct M: Decodable { let time: [String]; let precipitation: [Double] }
            let minutely_15: M?
            let timezone: String
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let m = decoded.minutely_15 else { return nil }

        let tz = TimeZone(identifier: decoded.timezone) ?? .current
        let parser = LocalTimeParser(timezone: tz)
        return zip(m.time, m.precipitation).compactMap { time, precip in
            parser.date(from: time).map { MinutePoint(date: $0, precipitation: precip) }
        }
    }
}
