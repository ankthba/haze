//
//  WeatherNextRawCache.swift
//  Weather
//
//  The raw Google WeatherNext payload for each place, kept on disk beside the
//  forecast bundle cache but apart from it. The bundle cache is stamped with
//  the units it was rendered in, so a unit change is always a miss there. On
//  the classic path that is right: Open-Meteo formats the numbers server side
//  and a new unit needs a new request. WeatherNext is different. Google always
//  answers in METRIC and the adapter converts locally, yet one refresh costs a
//  dozen quota-counted calls (ten hourly pages alone), and re-fetching because
//  the user flipped Celsius to Fahrenheit is exactly what used up the day's
//  hourly quota. Keeping the wire objects themselves means a unit change, or a
//  relaunch inside the refresh window, re-runs the adapter and touches Google
//  not at all. One JSON file per place, never UserDefaults: a snapshot with
//  240 hours plus history runs to hundreds of kilobytes. The Open-Meteo gap
//  fill that rode with the snapshot sits in a second file beside it, so a
//  load served from the snapshot sends no Open-Meteo request either.
//

import Foundation

nonisolated struct WeatherNextRawCache: Sendable {
    static let shared = WeatherNextRawCache(directory: defaultDirectory)

    private let directory: URL

    /// A sibling of the bundle cache's "Forecasts" folder, so the two caches
    /// live and get cleared together. Caches is fine here: losing a snapshot
    /// to storage pressure costs one Google refresh, nothing the user typed.
    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WeatherNextRaw", isDirectory: true)
    }

    /// Tests point this at a temporary directory.
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Freshness is the caller's decision: the service compares `fetchedAt`
    /// against the refresh window it was handed, so the same snapshot can be
    /// good enough for a unit change and too old for a timer reload.
    func snapshot(for place: Place) -> WeatherNextService.RawSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: place)) else { return nil }
        return try? Self.decoder.decode(WeatherNextService.RawSnapshot.self, from: data)
    }

    /// Every failure is swallowed: a cache that cannot write must never turn
    /// a successful fetch into an error.
    func save(_ snapshot: WeatherNextService.RawSnapshot, for place: Place) {
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        // The folder can vanish under storage pressure while the app runs.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: place), options: .atomic)
    }

    /// Both files: a place the user removed leaves nothing behind.
    func remove(for place: Place) {
        try? FileManager.default.removeItem(at: fileURL(for: place))
        try? FileManager.default.removeItem(at: gapFillURL(for: place))
    }

    // MARK: - Gap fill

    /// The Open-Meteo gap fill that went with the place's snapshot, kept so a
    /// load served from the snapshot does not send an Open-Meteo request
    /// either (Open-Meteo's rate limit has taken the whole app down before).
    /// Freshness and the units it was formatted in are the caller's to check,
    /// as with the snapshot.
    func gapFill(for place: Place) -> OpenMeteoGapFill.Stored? {
        guard let data = try? Data(contentsOf: gapFillURL(for: place)) else { return nil }
        return try? Self.decoder.decode(OpenMeteoGapFill.Stored.self, from: data)
    }

    func save(gapFill: OpenMeteoGapFill.Stored, for place: Place) {
        guard let data = try? Self.encoder.encode(gapFill) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: gapFillURL(for: place), options: .atomic)
    }

    // MARK: - Coding

    /// ISO 8601 rather than the default seconds-since-2001 double, so a file
    /// opened by hand reads as a date and a strategy change later can still
    /// parse what is already on disk.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Place ids are coordinate pairs ("37.775,-122.419"); the same character
    /// swap `WeatherCache` uses keeps them to safe filename territory.
    private func fileURL(for place: Place) -> URL {
        directory.appendingPathComponent("\(fileStem(for: place)).json")
    }

    /// Beside the snapshot, under the same stem, so the two are found and
    /// removed together.
    private func gapFillURL(for place: Place) -> URL {
        directory.appendingPathComponent("\(fileStem(for: place)).fill.json")
    }

    private func fileStem(for place: Place) -> String {
        place.id
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
