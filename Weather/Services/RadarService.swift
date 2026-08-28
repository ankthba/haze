//
//  RadarService.swift
//  Weather
//
//  Builds a detailed radar timeline from free, no-key tile services:
//
//   • US (CONUS): the Iowa Environmental Mesonet (IEM) — observed NEXRAD
//     composite (N0Q) for the past ~12h, and HRRR simulated-reflectivity
//     forecast for the next ~12h. Both are real-radar-detailed 3 km tiles.
//   • Elsewhere: RainViewer global radar (observed, ~past 2h) as a fallback.
//
//  All frames are XYZ tile layers, so nothing here touches Open-Meteo (the main
//  app's API) and a radar session can't rate-limit the rest of the app.
//

import Foundation
import CoreLocation

/// One time-step of the radar timeline — an XYZ tile template ({z}/{x}/{y}).
struct RadarFrame: Identifiable {
    let time: Date
    let isForecast: Bool
    let urlTemplate: String
    var id: TimeInterval { time.timeIntervalSince1970 }
}

struct RadarField {
    let center: CLLocationCoordinate2D
    let frames: [RadarFrame]

    /// First forecast frame — the "now" boundary.
    var nowIndex: Int { frames.firstIndex(where: { $0.isForecast }) ?? max(0, frames.count - 1) }
    /// Latest observed frame — what the preview thumbnail shows.
    var latestObservedIndex: Int { frames.lastIndex(where: { !$0.isForecast }) ?? nowIndex }

    var token: String {
        "\(center.latitude),\(center.longitude),\(frames.first?.id ?? 0),\(frames.count)"
    }
}

nonisolated struct RadarService {
    private static let iemBase = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0"
    /// RainViewer palette for the non-US fallback (6 = NEXRAD Level-III).
    private static let rainViewerScheme = 6

    enum RadarError: Error { case noData }

    /// `includeForecast` is false for the cheap home-screen preview (it only needs
    /// the current observed frame).
    func buildField(center: CLLocationCoordinate2D, includeForecast: Bool = true) async throws -> RadarField {
        if Self.isCONUS(center) {
            // Pure template generation — no network here; tiles load lazily.
            return Self.buildIEM(center: center, includeForecast: includeForecast)
        }
        guard let field = await Self.buildRainViewer(center: center) else { throw RadarError.noData }
        return field
    }

    // MARK: - US: IEM observed (past) + HRRR forecast (future)

    private static func buildIEM(center: CLLocationCoordinate2D, includeForecast: Bool) -> RadarField {
        var frames: [RadarFrame] = []
        let now = Date()

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: "GMT")
        stamp.dateFormat = "yyyyMMddHHmm"

        // Past 12h of observed NEXRAD, every 30 min (most recent product is a few
        // minutes old, so step back from now-5min).
        let latest = floorToFiveMin(now).addingTimeInterval(-300)
        var t = latest.addingTimeInterval(-12 * 3600)
        while t <= latest {
            let ts = stamp.string(from: floorToFiveMin(t))
            let template = "\(iemBase)/ridge::USCOMP-N0Q-\(ts)/{z}/{x}/{y}.png"
            frames.append(RadarFrame(time: t, isForecast: false, urlTemplate: template))
            t = t.addingTimeInterval(30 * 60)
        }

        // Next 12h of HRRR simulated-reflectivity forecast, hourly. "-0" selects
        // the latest model run; its early hours sit ~now, so label from +1h.
        if includeForecast {
            for hour in 1...12 {
                let minutes = hour * 60
                let layer = String(format: "REFD-F%04d-0", minutes)
                let template = "\(iemBase)/hrrr::\(layer)/{z}/{x}/{y}.png"
                frames.append(RadarFrame(time: now.addingTimeInterval(Double(minutes) * 60),
                                         isForecast: true, urlTemplate: template))
            }
        }

        return RadarField(center: center, frames: frames)
    }

    // MARK: - Fallback: RainViewer global observed radar

    private static func buildRainViewer(center: CLLocationCoordinate2D) async -> RadarField? {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(RVMaps.self, from: data) else { return nil }

        let now = Date()
        let frames = (decoded.radar.past + (decoded.radar.nowcast ?? [])).map { f -> RadarFrame in
            let t = Date(timeIntervalSince1970: f.time)
            let template = "\(decoded.host)\(f.path)/256/{z}/{x}/{y}/\(rainViewerScheme)/1_1.png"
            return RadarFrame(time: t, isForecast: t > now, urlTemplate: template)
        }
        guard !frames.isEmpty else { return nil }
        return RadarField(center: center, frames: frames.sorted { $0.time < $1.time })
    }

    // MARK: - Helpers

    private static func isCONUS(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= 21 && c.latitude <= 50 && c.longitude >= -125 && c.longitude <= -66
    }

    private static func floorToFiveMin(_ d: Date) -> Date {
        let s = d.timeIntervalSince1970
        return Date(timeIntervalSince1970: (s / 300).rounded(.down) * 300)
    }

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
}
