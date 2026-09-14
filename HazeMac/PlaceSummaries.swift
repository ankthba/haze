//
//  PlaceSummaries.swift
//  HazeMac
//
//  The temperature and condition beside each saved place in the sidebar. Most
//  come free: the forecast cache already holds a recent bundle for any place
//  that's been opened. The rest are the smallest request the current source
//  answers (current temperature and code only), fetched one at a time and no
//  more than once a quarter hour per place, so a long sidebar never turns into
//  a burst of traffic. The last known values are kept between launches so the
//  sidebar is never blank on opening.
//

import Foundation
import Observation

@MainActor
@Observable
final class PlaceSummaries {
    struct Summary: Codable {
        let temperature: Double
        let code: Int
        let isDay: Bool
        let fetchedAt: Date

        var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }
    }

    private struct Stored: Codable {
        let unit: TemperatureUnit
        /// Absent in files written before the source could change; those
        /// were all Open-Meteo.
        var source: ForecastSource?
        let summaries: [String: Summary]
    }

    private static let key = "mac_sidebar_summaries_v1"
    /// How long a reading stays good enough for a glance in a list. Not
    /// private only because it is the default `snapshotMaxAge`.
    static let freshFor: TimeInterval = 15 * 60

    private(set) var byPlace: [String: Summary] = [:]
    private var unit: TemperatureUnit?
    private var source: ForecastSource = .classic
    private var inFlight = false
    private let service = WeatherService()

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        unit = stored.unit
        source = stored.source ?? .classic
        byPlace = stored.summaries
    }

    func summary(for place: Place) -> Summary? { byPlace[place.id] }

    /// A full bundle just landed for this place; its numbers are the freshest
    /// anyone has.
    func note(_ bundle: WeatherBundle, unit: TemperatureUnit) {
        adopt(unit: unit, source: bundle.source ?? .classic)
        byPlace[bundle.place.id] = Summary(temperature: bundle.current.temperature,
                                           code: bundle.current.code,
                                           isDay: bundle.current.isDay,
                                           fetchedAt: bundle.fetchedAt)
        persist()
    }

    /// Bring every listed place up to date, cache first, network second.
    ///
    /// `snapshotMaxAge` is passed through to the WeatherNext path: a stored
    /// Google snapshot no older than this answers with no call at all. It is
    /// deliberately not tied to `force`, which means "the unit or source
    /// changed, so the known values are wrong"; a unit change is exactly the
    /// case the snapshot exists for, since the adapter converts locally.
    func refresh(places: [Place], units: WeatherCache.Units, force: Bool = false,
                 snapshotMaxAge: TimeInterval = PlaceSummaries.freshFor) async {
        adopt(unit: units.temperature, source: units.source)
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        for place in places {
            if Task.isCancelled { return }
            if !force, let known = byPlace[place.id],
               Date().timeIntervalSince(known.fetchedAt) < Self.freshFor { continue }

            if let cached = await WeatherCache.shared.bundle(for: place, units: units),
               Date().timeIntervalSince(cached.fetchedAt) < 2 * Self.freshFor {
                note(cached, unit: units.temperature)
                continue
            }

            if let current = try? await service.fetchCurrentSummary(
                for: place, temperatureUnit: units.temperature, source: units.source,
                maxAge: snapshotMaxAge) {
                byPlace[place.id] = Summary(temperature: current.temperature,
                                            code: current.code,
                                            isDay: current.isDay,
                                            fetchedAt: Date())
                persist()
            }
            // Spaced out on purpose; the sidebar is a glance, not a dashboard.
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Readings are in whatever unit, and from whatever source, was current
    /// when they were fetched; a change of either throws them away rather
    /// than showing 72 under a °C label or Open-Meteo's number beside a
    /// WeatherNext page.
    private func adopt(unit newUnit: TemperatureUnit, source newSource: ForecastSource) {
        guard unit != newUnit || source != newSource else { return }
        if unit != nil { byPlace = [:] }
        unit = newUnit
        source = newSource
        persist()
    }

    private func persist() {
        guard let unit,
              let data = try? JSONEncoder().encode(Stored(unit: unit, source: source, summaries: byPlace))
        else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
