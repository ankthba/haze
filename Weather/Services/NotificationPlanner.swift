//
//  NotificationPlanner.swift
//  Weather
//
//  Scheduled, quiet notifications: the morning digest (the daily brief as a
//  notification, at a time the user chooses) and the golden-hour heads-up.
//  Content is rebuilt from the freshest forecast every time the app runs or a
//  background check fires, so the scheduled copy is as current as it can be —
//  and honestly no more: a digest scheduled overnight describes the forecast
//  as of the last refresh before it fires.
//

import Foundation
import UserNotifications

@MainActor
enum NotificationPlanner {
    private static let digestEnabledKey = "digest_enabled"
    private static let digestMinutesKey = "digest_minutes_from_midnight"
    private static let goldenEnabledKey = "golden_hour_enabled"

    private static let digestID = "morning-digest"
    private static let goldenID = "golden-hour"

    static var digestEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: digestEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: digestEnabledKey) }
    }

    /// Minutes from local midnight; default 7:30 AM.
    static var digestMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: digestMinutesKey)
            return stored > 0 ? stored : 7 * 60 + 30
        }
        set { UserDefaults.standard.set(newValue, forKey: digestMinutesKey) }
    }

    static var goldenHourEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: goldenEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: goldenEnabledKey) }
    }

    // MARK: - Sunrise/sunset alert settings

    private static let sunsetAlertEnabledKey = "sunset_alert_enabled"
    private static let sunriseAlertEnabledKey = "sunrise_alert_enabled"
    private static let sunsetLeadKey = "sunset_alert_lead_minutes"
    private static let sunriseLeadKey = "sunrise_alert_lead_minutes"
    private static let sunsetGateKey = "sunset_alert_gate"
    private static let sunriseGateKey = "sunrise_alert_gate"

    private static let sunsetID = "sunset-alert"
    private static let sunriseID = "sunrise-alert"

    /// Both alerts default on with quality gates chosen so they only speak
    /// when the sky is worth it — the setting most people would pick.
    static var sunsetAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: sunsetAlertEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: sunsetAlertEnabledKey) }
    }

    static var sunriseAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: sunriseAlertEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: sunriseAlertEnabledKey) }
    }

    /// Minutes of warning; half an hour reaches a west-facing spot.
    static var sunsetAlertLeadMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: sunsetLeadKey)
            return stored > 0 ? stored : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: sunsetLeadKey) }
    }

    /// Sunrises need waking-up time on top of getting-out time.
    static var sunriseAlertLeadMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: sunriseLeadKey)
            return stored > 0 ? stored : 45
        }
        set { UserDefaults.standard.set(newValue, forKey: sunriseLeadKey) }
    }

    /// Sunsets speak for anything Good; a sunrise has to earn the alarm.
    static var sunsetAlertGate: SunQuality.AlertGate {
        get { SunQuality.AlertGate(rawValue:
                UserDefaults.standard.string(forKey: sunsetGateKey) ?? "") ?? .good }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sunsetGateKey) }
    }

    static var sunriseAlertGate: SunQuality.AlertGate {
        get { SunQuality.AlertGate(rawValue:
                UserDefaults.standard.string(forKey: sunriseGateKey) ?? "") ?? .great }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sunriseGateKey) }
    }

    /// Reconcile every scheduled notification with the newest forecast. Called
    /// after every successful device-place load and from the background check.
    static func refresh(bundle: WeatherBundle, usesFahrenheit: Bool) {
        refreshDigest(bundle: bundle, usesFahrenheit: usesFahrenheit)
        refreshGoldenHour(bundle: bundle)
        refreshSunAlert(kind: .sunset, bundle: bundle)
        refreshSunAlert(kind: .sunrise, bundle: bundle)
    }

    static func cancelDigest() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [digestID])
    }

    static func cancelGoldenHour() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [goldenID])
    }

    static func cancelSunAlert(kind: SunEvent.Kind) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [kind == .sunset ? sunsetID : sunriseID])
    }

    // MARK: - Morning digest

    private static func refreshDigest(bundle: WeatherBundle, usesFahrenheit: Bool) {
        guard digestEnabled else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        let now = Date()
        let todayFire = cal.startOfDay(for: now)
            .addingTimeInterval(TimeInterval(digestMinutes * 60))
        let fireDate = todayFire > now ? todayFire : todayFire.addingTimeInterval(86_400)

        // The day the digest will describe.
        guard let day = bundle.daily.first(where: { cal.isDate($0.date, inSameDayAs: fireDate) })
        else { return }

        var lines = ["High \(Fmt.tempDegree(day.tempMax)), low \(Fmt.tempDegree(day.tempMin)) — \(day.condition.description.lowercased())."]
        let dayHours = bundle.hours(on: fireDate).filter { $0.date > fireDate }
        if let firstRain = dayHours.first(where: { $0.precipitationProbability >= 55 }) {
            lines.append("Rain likely near \(Fmt.hour(firstRain.date, timezone: bundle.timezone)) — take the umbrella.")
        } else if day.precipitationProbabilityMax >= 40 {
            lines.append("A \(Fmt.percent(day.precipitationProbabilityMax)) chance of rain at some point.")
        }
        if let snow = day.snowfallSum, snow > 0.2 {
            lines.append(usesFahrenheit
                ? String(format: "Snow totals near %.1f in.", snow)
                : String(format: "Snow totals near %.0f cm.", snow))
        }

        let content = UNMutableNotificationContent()
        content.title = "This morning in \(bundle.place.name)"
        content.body = lines.joined(separator: " ")
        content.sound = .default

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Replacing the pending request by id keeps exactly one queued digest,
        // always built from the freshest forecast we've seen.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: digestID, content: content, trigger: trigger))
    }

    // MARK: - Sunrise/sunset alerts

    /// Queue the next qualifying event of this kind: the soonest one, within
    /// the next few days, whose rating clears the user's gate. One pending
    /// request per kind, replaced wholesale on every refresh so a forecast
    /// that turns (a cloud deck arriving, a rating collapsing) reschedules or
    /// silences the alert on the next check.
    private static func refreshSunAlert(kind: SunEvent.Kind, bundle: WeatherBundle) {
        let enabled = kind == .sunset ? sunsetAlertEnabled : sunriseAlertEnabled
        let lead = kind == .sunset ? sunsetAlertLeadMinutes : sunriseAlertLeadMinutes
        let gate = kind == .sunset ? sunsetAlertGate : sunriseAlertGate
        let id = kind == .sunset ? sunsetID : sunriseID
        guard enabled else { return }

        let now = Date()
        // Ratings lose meaning past a couple of days; look that far, no more.
        let candidates = bundle.daily.prefix(3)
            .compactMap { kind == .sunset ? $0.sunset : $0.sunrise }
            .filter { $0.addingTimeInterval(TimeInterval(-lead * 60)) > now }
            .sorted()

        for event in candidates {
            guard let rating = SunQuality.rate(kind: kind, at: event, in: bundle) else {
                continue
            }
            guard rating.score >= gate.minScore else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(kind.rawValue) at \(Fmt.time(event, timezone: bundle.timezone))"
            content.body = "Rates \(rating.score), \(rating.tier.rawValue.lowercased()). \(rating.tier.blurb)"
            content.sound = .default

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = bundle.timezone
            let fire = event.addingTimeInterval(TimeInterval(-lead * 60))
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                                from: fire)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content,
                                      trigger: UNCalendarNotificationTrigger(
                                          dateMatching: components, repeats: false)))
            return
        }
        // Nothing qualifies in the window; make sure no stale alert lingers.
        cancelSunAlert(kind: kind)
    }

    // MARK: - Golden hour

    private static func refreshGoldenHour(bundle: WeatherBundle) {
        guard goldenHourEnabled,
              let sunset = bundle.today?.sunset else { return }
        let fireDate = sunset.addingTimeInterval(-80 * 60)   // 20 min before the hour begins
        guard fireDate > Date() else { return }

        // Not worth waking anyone for a sky that's a gray lid.
        switch bundle.current.condition.kind {
        case .overcast, .fog, .rain, .drizzle, .showers, .thunderstorm, .thunderstormHail:
            return
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "Golden hour soon"
        content.body = "The light turns at \(Fmt.time(sunset.addingTimeInterval(-3600), timezone: bundle.timezone)) in \(bundle.place.name)."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(fireDate.timeIntervalSinceNow, 60), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: goldenID, content: content, trigger: trigger))
    }
}
