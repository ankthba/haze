//
//  WeatherCache.swift
//  Weather
//
//  The last forecast for each place, kept on disk so a launch has something
//  real to draw immediately instead of a spinner: the screen comes up with the
//  previous reading (and its "Updated …" stamp), and the live fetch replaces it
//  a moment later. One small file per place, so opening costs a single read.
//

import Foundation

actor WeatherCache {
    static let shared = WeatherCache()

    /// Older than this and the cached reading isn't worth showing even briefly.
    private static let maxAge: TimeInterval = 24 * 3600
    private static let lastPlaceKey = "last_cached_place_v1"

    private let directory: URL?

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = base?.appendingPathComponent("Forecasts", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Readings are stored in the units they were fetched in, so a unit change
    /// can't briefly redraw the old numbers under the new symbol.
    struct Units: Codable, Equatable {
        let temperature: TemperatureUnit
        let speed: SpeedUnit
        let precip: PrecipUnit

        init(temperature: TemperatureUnit, speed: SpeedUnit, precip: PrecipUnit) {
            self.temperature = temperature
            self.speed = speed
            self.precip = precip
        }
    }

    private struct Entry: Codable {
        let bundle: WeatherBundle
        let units: Units
    }

    /// The place shown last — what a cold launch draws before location and
    /// network have had a chance to answer.
    func mostRecent(units: Units) -> WeatherBundle? {
        guard let id = UserDefaults.standard.string(forKey: Self.lastPlaceKey) else { return nil }
        return bundle(forPlaceID: id, units: units)
    }

    func bundle(for place: Place, units: Units) -> WeatherBundle? {
        bundle(forPlaceID: place.id, units: units)
    }

    func save(_ bundle: WeatherBundle, units: Units) {
        guard let url = fileURL(for: bundle.place.id),
              let data = try? JSONEncoder().encode(Entry(bundle: bundle, units: units))
        else { return }
        try? data.write(to: url, options: .atomic)
        UserDefaults.standard.set(bundle.place.id, forKey: Self.lastPlaceKey)
    }

    private func bundle(forPlaceID id: String, units: Units) -> WeatherBundle? {
        guard let url = fileURL(for: id),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.units == units,
              Date().timeIntervalSince(entry.bundle.fetchedAt) < Self.maxAge
        else { return nil }
        return entry.bundle
    }

    /// Place ids are coordinate pairs ("37.775,-122.419"); the character swap
    /// just keeps them to safe filename territory.
    private func fileURL(for placeID: String) -> URL? {
        let name = placeID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory?.appendingPathComponent("\(name).json")
    }
}
