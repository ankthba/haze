//
//  PlaceSummaries.swift
//  HazeMac
//
//  The temperature and condition beside each saved place in the sidebar. Most
//  come free: the forecast cache already holds a recent bundle for any place
//  that's been opened. The rest are the smallest request Open-Meteo answers
//  (current temperature and code only), fetched one at a time and no more
//  than once a quarter hour per place, so a long sidebar never turns into a
//  burst of traffic. The last known values are kept between launches so the
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
        let summaries: [String: Summary]
    }

    private static let key = "mac_sidebar_summaries_v1"
    /// How long a reading stays good enough for a glance in a list.
    private static let freshFor: TimeInterval = 15 * 60

    private(set) var byPlace: [String: Summary] = [:]
    private var unit: TemperatureUnit?
    private var inFlight = false
    private let service = WeatherService()

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        unit = stored.unit
        byPlace = stored.summaries
    }

    func summary(for place: Place) -> Summary? { byPlace[place.id] }

    /// A full bundle just landed for this place; its numbers are the freshest
    /// anyone has.
    func note(_ bundle: WeatherBundle, unit: TemperatureUnit) {
        adopt(unit: unit)
        byPlace[bundle.place.id] = Summary(temperature: bundle.current.temperature,
                                           code: bundle.current.code,
                                           isDay: bundle.current.isDay,
                                           fetchedAt: bundle.fetchedAt)
        persist()
    }

    /// Bring every listed place up to date, cache first, network second.
    func refresh(places: [Place], units: WeatherCache.Units, force: Bool = false) async {
        adopt(unit: units.temperature)
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
                for: place, temperatureUnit: units.temperature) {
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

    /// Readings are in whatever unit was current when they were fetched; a
    /// unit change throws them away rather than showing 72 under a °C label.
    private func adopt(unit newUnit: TemperatureUnit) {
        guard unit != newUnit else { return }
        if unit != nil { byPlace = [:] }
        unit = newUnit
        persist()
    }

    private func persist() {
        guard let unit,
              let data = try? JSONEncoder().encode(Stored(unit: unit, summaries: byPlace))
        else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
