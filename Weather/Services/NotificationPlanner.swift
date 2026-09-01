//
//  NotificationPlanner.swift
//  Weather
//
//  Scheduled, quiet notifications: the morning digest (the daily brief as a
//  notification, at a time the user chooses) and the golden-hour heads-up.
//  Content is rebuilt from the freshest forecast every time the app runs or a
//  background check fires, so the scheduled copy is as current as it can be,
//  and honestly no more: a digest scheduled overnight describes the forecast
//  as of the last refresh before it fires.
//
//  Copy is composed in whichever register `Voice.current` names, read at the
//  moment each request is built so a background rebuild speaks the same way
//  the app on screen does.
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

    private static let sunriseEveningEnabledKey = "sunrise_evening_enabled"
    private static let sunriseEveningMinutesKey = "sunrise_evening_minutes_from_midnight"

    private static let sunsetID = "sunset-alert"
    private static let sunriseID = "sunrise-alert"
    private static let sunriseEveningID = "sunrise-evening"

    /// Both alerts default on with quality gates chosen so they only speak
    /// when the sky is worth it, the setting most people would pick.
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

    /// The night-before heads-up. A sunrise alert forty-five minutes ahead of
    /// the event is useless if you are asleep; this one lands while you still
    /// have the phone in your hand and can set an alarm. Off by default, and
    /// it rides on the sunrise alert's own quality bar.
    static var sunriseEveningEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sunriseEveningEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: sunriseEveningEnabledKey) }
    }

    /// Minutes from local midnight; default 9 PM.
    static var sunriseEveningMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: sunriseEveningMinutesKey)
            return stored > 0 ? stored : 21 * 60
        }
        set { UserDefaults.standard.set(newValue, forKey: sunriseEveningMinutesKey) }
    }

    /// Reconcile every scheduled notification with the newest forecast. Called
    /// after every successful device-place load and from the background check.
    static func refresh(bundle: WeatherBundle, usesFahrenheit: Bool) {
        refreshDigest(bundle: bundle, usesFahrenheit: usesFahrenheit)
        refreshGoldenHour(bundle: bundle)
        refreshSunAlert(kind: .sunset, bundle: bundle)
        refreshSunAlert(kind: .sunrise, bundle: bundle)
        refreshSunriseEvening(bundle: bundle)
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

    static func cancelSunriseEvening() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [sunriseEveningID])
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

        let voice = Voice.current
        let high = Fmt.tempDegree(day.tempMax)
        let low = Fmt.tempDegree(day.tempMin)
        let sky = day.condition.description.lowercased()
        var lines = [voice.pick("High \(high), low \(low), \(sky).",
                                whimsy: "A high of \(high) and a low of \(low), under a \(sky) sky.")]
        let dayHours = bundle.hours(on: fireDate).filter { $0.date > fireDate }
        if let firstRain = dayHours.first(where: { $0.precipitationProbability >= 55 }) {
            let near = Fmt.hour(firstRain.date, timezone: bundle.timezone)
            lines.append(voice.pick("Rain likely near \(near), so take the umbrella.",
                                    whimsy: "Rain should find you near \(near), so take the umbrella."))
        } else if day.precipitationProbabilityMax >= 40 {
            let odds = Fmt.percent(day.precipitationProbabilityMax)
            lines.append(voice.pick("A \(odds) chance of rain at some point.",
                                    whimsy: "A \(odds) chance of rain wandering through at some point."))
        }
        if let snow = day.snowfallSum, snow > 0.2 {
            let amount = usesFahrenheit
                ? String(format: "%.1f in", snow)
                : String(format: "%.0f cm", snow)
            lines.append(voice.pick("Snow totals near \(amount).",
                                    whimsy: "About \(amount) of snow piling up."))
        }

        let content = UNMutableNotificationContent()
        content.title = voice.pick("This morning in \(bundle.place.name)",
                                   whimsy: "Good morning, \(bundle.place.name)")
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

            let voice = Voice.current
            let at = Fmt.time(event, timezone: bundle.timezone)
            let tier = rating.tier.rawValue.lowercased()
            let content = UNMutableNotificationContent()
            content.title = voice.pick("\(kind.rawValue) at \(at)",
                                       whimsy: "A \(kind.rawValue.lowercased()) worth seeing, at \(at)")
            content.body = voice.pick(
                "Rates \(rating.score), \(tier). \(rating.tier.blurb(voice))",
                whimsy: "\(rating.score) out of 100, which is \(tier). \(rating.tier.blurb(voice))")
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

    // MARK: - The night before

    /// Tonight's heads-up about tomorrow morning. Describes the first sunrise
    /// after the heads-up itself fires, so the copy is never about a sunrise
    /// that has already happened, and only when that sunrise clears the same
    /// bar the morning alert uses. One pending request, replaced on every
    /// refresh, so a deck of cloud rolling in overnight silences it.
    private static func refreshSunriseEvening(bundle: WeatherBundle) {
        guard sunriseAlertEnabled, sunriseEveningEnabled else {
            cancelSunriseEvening()
            return
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        let now = Date()
        let tonight = cal.startOfDay(for: now)
            .addingTimeInterval(TimeInterval(sunriseEveningMinutes * 60))
        let fireDate = tonight > now ? tonight : tonight.addingTimeInterval(86_400)

        guard let sunrise = bundle.daily.prefix(3).compactMap(\.sunrise)
                .sorted().first(where: { $0 > fireDate }),
              let rating = SunQuality.rate(kind: .sunrise, at: sunrise, in: bundle),
              rating.score >= sunriseAlertGate.minScore
        else {
            cancelSunriseEvening()
            return
        }

        let voice = Voice.current
        let at = Fmt.time(sunrise, timezone: bundle.timezone)
        let tier = rating.tier.rawValue.lowercased()
        let content = UNMutableNotificationContent()
        content.title = voice.pick("Tomorrow's sunrise at \(at)",
                                   whimsy: "Set an alarm for tomorrow's sunrise")
        content.body = voice.pick(
            "Rates \(rating.score), \(tier). \(rating.tier.blurb(voice)) Worth setting an alarm.",
            whimsy: "\(rating.score) out of 100, which is \(tier). \(rating.tier.blurb(voice)) It's up at \(at).")
        content.sound = .default

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: fireDate)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: sunriseEveningID, content: content,
                                  trigger: UNCalendarNotificationTrigger(
                                      dateMatching: components, repeats: false)))
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

        let voice = Voice.current
        let turns = Fmt.time(sunset.addingTimeInterval(-3600), timezone: bundle.timezone)
        let content = UNMutableNotificationContent()
        content.title = voice.pick("Golden hour soon", whimsy: "The light is about to turn")
        content.body = voice.pick(
            "The light turns at \(turns) in \(bundle.place.name).",
            whimsy: "The golden hour begins at \(turns) in \(bundle.place.name). Find a window facing west.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(fireDate.timeIntervalSinceNow, 60), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: goldenID, content: content, trigger: trigger))
    }
}
