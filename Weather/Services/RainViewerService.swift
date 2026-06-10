//
//  RainViewerService.swift
//  Weather
//
//  Precipitation-radar frames from RainViewer's free public API (no key). Open-Meteo
//  doesn't serve radar imagery, so the live map is sourced separately. RainViewer
//  returns a rolling window of observed ("past") frames plus a short nowcast, each
//  addressable as map tiles.
//
//  API: https://api.rainviewer.com/public/weather-maps.json
//

import Foundation

/// One radar frame: a moment in time and the RainViewer path used to build its
/// tiles. `past` frames are observed; `isForecast` frames are short-range nowcast.
struct RadarFrame: Identifiable, Equatable {
    let time: Date
    let path: String
    let isForecast: Bool
    var id: TimeInterval { time.timeIntervalSince1970 }
}

struct RainViewerService {
    /// A fetched set of frames plus the tile host they resolve against.
    struct Maps: Equatable {
        let host: String
        let frames: [RadarFrame]   // past then nowcast, chronological

        /// Index of the first forecast frame — the boundary drawn as "now".
        var nowIndex: Int {
            frames.firstIndex(where: { $0.isForecast }) ?? max(0, frames.count - 1)
        }
    }

    /// RainViewer palette used throughout the app. Scheme 8 ("Dark Sky") is a
    /// smooth, desaturated blue→green→yellow→red ramp that reads cleanly on both
    /// light and dark maps — gentler than the harsher default schemes.
    static let colorScheme = 8

    enum RainViewerError: Error { case badResponse, noFrames }

    private let endpoint = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!

    func fetchFrames() async throws -> Maps {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RainViewerError.badResponse
        }

        let decoded = try JSONDecoder().decode(WeatherMaps.self, from: data)
        let past = decoded.radar.past.map {
            RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path, isForecast: false)
        }
        let nowcast = (decoded.radar.nowcast ?? []).map {
            RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path, isForecast: true)
        }
        let frames = (past + nowcast).sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw RainViewerError.noFrames }
        return Maps(host: decoded.host, frames: frames)
    }

    /// MapKit tile-URL template for a frame, with `{z}/{x}/{y}` filled in by
    /// `MKTileOverlay`. `color` selects a RainViewer palette (0–8); `size` is
    /// 256 or 512; smoothing and snow rendering are on by default.
    static func tileTemplate(host: String,
                             frame: RadarFrame,
                             color: Int,
                             size: Int = 256,
                             smooth: Bool = true,
                             showSnow: Bool = true) -> String {
        "\(host)\(frame.path)/\(size)/{z}/{x}/{y}/\(color)/\(smooth ? 1 : 0)_\(showSnow ? 1 : 0).png"
    }

    // MARK: - Wire models

    private struct WeatherMaps: Decodable {
        let host: String
        let radar: Radar
    }
    private struct Radar: Decodable {
        let past: [Frame]
        let nowcast: [Frame]?
    }
    private struct Frame: Decodable {
        let time: TimeInterval
        let path: String
    }
}
