//
//  RadarService.swift
//  Weather
//
//  Builds a hybrid radar timeline:
//   • DETAILED, real observed radar (RainViewer tiles) for the recent past up to
//     now — the crisp, NEXRAD-style look.
//   • COARSE precipitation forecast (Open-Meteo grid, drawn as a heatmap) for the
//     hours ahead, since detailed radar of the future doesn't exist.
//  The two are merged into one scrubbable timeline; the renderer switches layer
//  type at the "now" boundary.
//

import Foundation
import CoreLocation

/// What a frame is drawn from.
enum RadarLayer {
    case tiles(urlTemplate: String)   // RainViewer XYZ tiles ({z}/{x}/{y})
    case grid([Double])               // Open-Meteo mm/h values, row-major north-first
}

/// One time-step of the radar timeline.
struct RadarFrame: Identifiable {
    let time: Date
    let isForecast: Bool
    let layer: RadarLayer
    var id: TimeInterval { time.timeIntervalSince1970 }
    var isTiles: Bool { if case .tiles = layer { return true } else { return false } }
}

struct RadarField {
    let center: CLLocationCoordinate2D
    let halfSpan: CLLocationDegrees
    let cols: Int
    let rows: Int
    let frames: [RadarFrame]

    /// First forecast frame — the boundary drawn as "now".
    var nowIndex: Int {
        frames.firstIndex(where: { $0.isForecast }) ?? max(0, frames.count - 1)
    }

    /// Latest detailed (observed-radar) frame — what the preview thumbnail shows.
    var latestRadarIndex: Int {
        frames.lastIndex(where: { $0.isTiles && !$0.isForecast }) ?? nowIndex
    }

    var token: String {
        "\(center.latitude),\(center.longitude),\(frames.first?.id ?? 0),\(frames.count)"
    }
}

struct RadarService {
    /// Forecast-grid resolution and half-width of the sampled box (deg). Kept
    /// modest: each grid point is a weighted Open-Meteo call, and the main app
    /// shares that quota — an over-large grid can rate-limit the whole app.
    static let grid = 16
    static let halfSpan: CLLocationDegrees = 2.0
    static let forecastHours = 12
    static let maxPerRequest = 290
    /// RainViewer palette — 6 is "NEXRAD Level-III", closest to the NWS look.
    static let radarColorScheme = 6

    enum RadarError: Error { case noData }

    /// Build the timeline. `includeForecast` is false for the home-screen preview
    /// so it shows the cheap detailed-radar frame without the costly grid fetch.
    func buildField(center: CLLocationCoordinate2D, includeForecast: Bool = true) async throws -> RadarField {
        // Fetch the (cheap) detailed radar always; only fetch the (expensive)
        // forecast grid when asked. RainViewer runs concurrently meanwhile.
        async let radarTask = Self.fetchRainViewer(scheme: Self.radarColorScheme)
        let forecast = includeForecast ? await Self.fetchForecast(center: center) : nil
        let radarFrames = await radarTask

        let cutoff = radarFrames.map(\.time).max() ?? Date()
        var frames = radarFrames
        if let forecast {
            // Keep only forecast frames beyond where detailed radar ends.
            frames.append(contentsOf: forecast.frames.filter { $0.time > cutoff })
        }
        frames.sort { $0.time < $1.time }
        guard !frames.isEmpty else { throw RadarError.noData }

        return RadarField(center: center, halfSpan: Self.halfSpan,
                          cols: forecast?.cols ?? Self.grid,
                          rows: forecast?.rows ?? Self.grid,
                          frames: frames)
    }

    // MARK: - Detailed observed radar (RainViewer)

    private static func fetchRainViewer(scheme: Int) async -> [RadarFrame] {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(RVMaps.self, from: data) else { return [] }

        let now = Date()
        func frame(_ f: RVFrame) -> RadarFrame {
            let t = Date(timeIntervalSince1970: f.time)
            let template = "\(decoded.host)\(f.path)/256/{z}/{x}/{y}/\(scheme)/1_1.png"
            return RadarFrame(time: t, isForecast: t > now, layer: .tiles(urlTemplate: template))
        }
        return (decoded.radar.past + (decoded.radar.nowcast ?? [])).map(frame)
    }

    // MARK: - Coarse precipitation forecast (Open-Meteo grid)

    private static func fetchForecast(center: CLLocationCoordinate2D)
        async -> (frames: [RadarFrame], cols: Int, rows: Int)? {
        let g = grid, h = halfSpan
        var lats: [String] = [], lons: [String] = []
        lats.reserveCapacity(g * g); lons.reserveCapacity(g * g)
        for j in 0..<g {
            let lat = min(max(center.latitude + h - (2 * h) * Double(j) / Double(g - 1), -89), 89)
            for i in 0..<g {
                var lon = center.longitude - h + (2 * h) * Double(i) / Double(g - 1)
                lon = lon.truncatingRemainder(dividingBy: 360)
                if lon > 180 { lon -= 360 } else if lon < -180 { lon += 360 }
                lats.append(String(format: "%.3f", lat))
                lons.append(String(format: "%.3f", lon))
            }
        }

        let n = g * g
        var ranges: [Range<Int>] = []
        var s = 0
        while s < n { ranges.append(s..<min(s + maxPerRequest, n)); s += maxPerRequest }

        var chunks = [[PointResponse]?](repeating: nil, count: ranges.count)
        await withTaskGroup(of: (Int, [PointResponse]?).self) { group in
            for (ci, r) in ranges.enumerated() {
                let la = Array(lats[r]), lo = Array(lons[r])
                group.addTask { (ci, await fetchChunk(lats: la, lons: lo)) }
            }
            for await (ci, res) in group { chunks[ci] = res }
        }
        let points = chunks.compactMap { $0 }.flatMap { $0 }
        guard points.count == n, let first = points.first else { return nil }

        let formatter = makeFormatter()
        let times = first.hourly.time.map { formatter.date(from: $0) ?? Date(timeIntervalSince1970: 0) }
        let now = Date()
        let upper = now.addingTimeInterval(Double(forecastHours) * 3600 + 1800)
        let window = times.indices.filter { times[$0] >= now.addingTimeInterval(-3600) && times[$0] <= upper }
        guard !window.isEmpty else { return nil }

        var frames: [RadarFrame] = []
        frames.reserveCapacity(window.count)
        for k in window {
            let t = times[k]
            var values = [Double](repeating: 0, count: n)
            for p in 0..<n {
                let arr = points[p].hourly.precipitation
                values[p] = (k < arr.count ? arr[k] : nil).flatMap { $0 } ?? 0
            }
            frames.append(RadarFrame(time: t, isForecast: t > now, layer: .grid(values)))
        }
        return (frames, g, g)
    }

    private static func fetchChunk(lats: [String], lons: [String]) async -> [PointResponse]? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.percentEncodedQuery =
            "latitude=\(lats.joined(separator: ","))"
            + "&longitude=\(lons.joined(separator: ","))"
            + "&hourly=precipitation&timezone=GMT&forecast_days=2&precipitation_unit=mm"
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode([PointResponse].self, from: data) else { return nil }
        return decoded
    }

    private static func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }

    // MARK: - Wire models

    private struct RVMaps: Decodable {
        let host: String
        let radar: RVRadar
    }
    private struct RVRadar: Decodable {
        let past: [RVFrame]
        let nowcast: [RVFrame]?
    }
    private struct RVFrame: Decodable {
        let time: TimeInterval
        let path: String
    }
    private struct PointResponse: Decodable {
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let precipitation: [Double?]
        }
    }
}
