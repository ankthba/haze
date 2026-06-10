//
//  OpenMeteoRadarService.swift
//  Weather
//
//  A forecast "radar" built from Open-Meteo. Observed radar tiles (RainViewer
//  etc.) only cover the recent past + a ~30-minute nowcast, so they can't show
//  where rain is headed over the next several hours. Instead we sample hourly
//  precipitation across a dense grid of points around the location and render
//  each hour as a smooth heatmap — a loop running from ~1 hour ago to ~12 hours
//  ahead.
//
//  Open-Meteo caps request-URL length (a few hundred points), so the grid is
//  fetched in a few concurrent chunks and reassembled in order.
//

import Foundation
import CoreLocation

/// One time-step of the precipitation field: a grid of mm/h values (row-major,
/// north row first) at `time`. `isForecast` marks steps in the future.
struct RadarFrame: Identifiable {
    let time: Date
    let isForecast: Bool
    let values: [Double]
    var id: TimeInterval { time.timeIntervalSince1970 }
}

/// A precipitation field over a square region: a stack of hourly frames.
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

    /// Identity token so the map can tell when a new field has arrived.
    var token: String {
        "\(center.latitude),\(center.longitude),\(frames.first?.id ?? 0),\(frames.count)"
    }
}

struct OpenMeteoRadarService {
    /// Grid resolution (points per side) and half-width of the sampled box (deg).
    static let grid = 24
    static let halfSpan: CLLocationDegrees = 2.0
    static let pastHours = 1
    static let forecastHours = 12
    /// Max points per request — Open-Meteo rejects long URLs (~8k chars) and
    /// rate-limits bursts, so we keep to a couple of modest chunks.
    static let maxPerRequest = 290

    enum RadarError: Error { case badResponse, noData }

    func fetchField(center: CLLocationCoordinate2D) async throws -> RadarField {
        let g = Self.grid
        let h = Self.halfSpan

        var lats: [String] = []
        var lons: [String] = []
        lats.reserveCapacity(g * g)
        lons.reserveCapacity(g * g)
        // Row-major, north (top) row first.
        for j in 0..<g {
            let lat = clampLat(center.latitude + h - (2 * h) * Double(j) / Double(g - 1))
            for i in 0..<g {
                let lon = wrapLon(center.longitude - h + (2 * h) * Double(i) / Double(g - 1))
                lats.append(String(format: "%.3f", lat))
                lons.append(String(format: "%.3f", lon))
            }
        }

        // Fetch the grid in concurrent chunks, then reassemble in order.
        let n = g * g
        var ranges: [Range<Int>] = []
        var s = 0
        while s < n { ranges.append(s..<min(s + Self.maxPerRequest, n)); s += Self.maxPerRequest }

        var chunks = [[PointResponse]](repeating: [], count: ranges.count)
        try await withThrowingTaskGroup(of: (Int, [PointResponse]).self) { group in
            for (ci, r) in ranges.enumerated() {
                let la = Array(lats[r]), lo = Array(lons[r])
                group.addTask { (ci, try await self.fetchChunk(lats: la, lons: lo)) }
            }
            for try await (ci, res) in group { chunks[ci] = res }
        }
        let points = chunks.flatMap { $0 }
        guard points.count == n, let first = points.first else { throw RadarError.noData }

        // All points share one time axis; parse it once and pick the window.
        let formatter = Self.makeFormatter()
        let times = first.hourly.time.map { formatter.date(from: $0) ?? Date(timeIntervalSince1970: 0) }
        let now = Date()
        let lower = now.addingTimeInterval(-Double(Self.pastHours) * 3600 - 1800)
        let upper = now.addingTimeInterval(Double(Self.forecastHours) * 3600 + 1800)
        let window = times.indices.filter { times[$0] >= lower && times[$0] <= upper }
        guard !window.isEmpty else { throw RadarError.noData }

        var frames: [RadarFrame] = []
        frames.reserveCapacity(window.count)
        for k in window {
            let t = times[k]
            var values = [Double](repeating: 0, count: n)
            for p in 0..<n {
                let arr = points[p].hourly.precipitation
                values[p] = (k < arr.count ? arr[k] : nil).flatMap { $0 } ?? 0
            }
            frames.append(RadarFrame(time: t, isForecast: t > now, values: values))
        }

        return RadarField(center: center, halfSpan: h, cols: g, rows: g, frames: frames)
    }

    private func fetchChunk(lats: [String], lons: [String]) async throws -> [PointResponse] {
        // Raw (unencoded) commas keep the URL short enough to fit more points;
        // the values are plain numbers so nothing needs escaping.
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.percentEncodedQuery =
            "latitude=\(lats.joined(separator: ","))"
            + "&longitude=\(lons.joined(separator: ","))"
            + "&hourly=precipitation&timezone=GMT&past_days=1&forecast_days=2&precipitation_unit=mm"
        guard let url = comps.url else { throw RadarError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RadarError.badResponse
        }
        return try JSONDecoder().decode([PointResponse].self, from: data)
    }

    private func clampLat(_ v: Double) -> Double { min(max(v, -89), 89) }
    private func wrapLon(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 } else if x < -180 { x += 360 }
        return x
    }

    private static func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }

    private struct PointResponse: Decodable {
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let precipitation: [Double?]
        }
    }
}
