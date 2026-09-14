//
//  StationObservation.swift
//  Weather
//
//  What a real weather station is reporting right now, rather than what a
//  model thinks is happening in your grid cell. The forecast pipeline is very
//  good at the next ten days and structurally incapable of knowing that it is
//  raining on you at this minute: a grid cell is kilometres wide and its
//  "current" hour is an analysis, not a measurement.
//
//  The NWS publishes the raw ASOS/AWOS reports, so in the US the hero reading
//  can be an actual observation. The rules are deliberately conservative,
//  because a wrong observation is worse than an honest model value:
//
//   * Stations are sorted by true distance and tried in order — the list the
//     NWS returns is *roughly* proximity-ordered, and the old code took
//     `features.first` on faith.
//   * Anything beyond `maxDistance` is discarded outright. A station 60 km
//     away is not your weather.
//   * Reports older than `maxAge` are discarded: a stale METAR is a lie about
//     "now".
//   * Values flagged as failing the NWS's own quality control are dropped
//     field by field, so one bad sensor doesn't cost the whole report.
//   * Sky cover stays with the model. A ceilometer sees the column directly
//     above the airport; the model sees the sky you're standing under.
//

import CoreLocation
import Foundation

nonisolated struct StationObservation: Codable, Equatable {
    let stationID: String
    let stationName: String
    let distanceMeters: Double
    let observedAt: Date

    /// SI, exactly as the NWS reports it. Conversion happens once, in
    /// `applied(to:…)`, against the same unit choice the forecast was fetched
    /// with — so a station value can never land in the wrong unit.
    let temperatureC: Double?
    let apparentC: Double?
    let dewPointC: Double?
    let humidityPercent: Double?
    let windSpeedKPH: Double?
    let windGustKPH: Double?
    let windDirectionDegrees: Double?
    /// Sea-level pressure only. A station's own `barometricPressure` is
    /// uncorrected for its elevation, so in Denver it reads ~840 hPa against
    /// the model's ~1015 — the app shows MSL everywhere, and mixing the two
    /// would put a wild number under an unchanged label.
    let pressurePa: Double?
    let visibilityMeters: Double?
    let textDescription: String?

    /// Beyond this, the nearest station is reporting someone else's weather.
    static let maxDistance: CLLocationDistance = 40_000
    /// Stations report hourly, and file extra reports when the weather turns;
    /// anything older than this is not "now".
    static let maxAge: TimeInterval = 75 * 60
    /// A guard against a broken sensor, not a smoothing band: a station that
    /// disagrees with the model by more than this is not reporting a real
    /// inversion, it is reporting nonsense, and the model is the safer value.
    /// Wide on purpose — genuine valley inversions and lake effects run
    /// several degrees, and clamping those would defeat the point.
    static let sanityBandC: Double = 10

    /// Whether this report is worth trusting over the model at all. Checked
    /// before anything is applied, because trust here is all-or-nothing: a
    /// station good enough for the temperature is good enough for the wind,
    /// and one that fails is not a station to take humidity from either.
    /// Half-applying a bad report is how a page ends up self-contradictory.
    func isPlausible(against current: CurrentWeather,
                     temperatureUnit: TemperatureUnit) -> Bool {
        guard let temperatureC else { return false }
        let modelC = temperatureUnit == .fahrenheit
            ? (current.temperature - 32) * 5 / 9
            : current.temperature
        return abs(temperatureC - modelC) <= Self.sanityBandC
    }

    var age: TimeInterval { Date().timeIntervalSince(observedAt) }
    var isFresh: Bool { age < Self.maxAge }

    /// "Observed at KDCA, 3.2 mi away, 14 minutes ago" — the provenance line
    /// under the reading, so numbers that came off a real instrument say so.
    /// Deliberately plain rather than voiced: like the attribution and the
    /// updated stamp, this is a label on the data, not prose about it.
    func provenance(usesImperial: Bool) -> String {
        let distance = usesImperial
            ? String(format: "%.1f mi", distanceMeters / 1609.344)
            : String(format: "%.1f km", distanceMeters / 1000)
        let minutes = max(0, Int(age / 60))
        let when: String
        switch minutes {
        case 0: when = "just now"
        case 1: when = "1 minute ago"
        case ..<60: when = "\(minutes) minutes ago"
        case ..<120: when = "over an hour ago"
        default: when = "\(minutes / 60) hours ago"
        }
        return "Observed at \(stationID), \(distance) away, \(when)"
    }
}

// MARK: - Applying to the current reading

extension StationObservation {
    /// The model's current reading with every value this station actually
    /// measured swapped in. Sky cover, precipitation amount, UV and `isDay`
    /// stay with the model: the station either doesn't measure them or
    /// measures them only for the column above itself.
    ///
    /// `observedCode` is passed separately because the caller applies the
    /// existing "only override for *active* weather" rule to it.
    func applied(to current: CurrentWeather,
                 observedCode: Int?,
                 temperatureUnit: TemperatureUnit,
                 speedUnit: SpeedUnit) -> CurrentWeather {
        func temp(_ celsius: Double?) -> Double? {
            guard let celsius else { return nil }
            return temperatureUnit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        }
        func speed(_ kph: Double?) -> Double? {
            guard let kph else { return nil }
            switch speedUnit {
            case .mph: return kph / 1.609344
            case .kmh: return kph
            case .ms: return kph / 3.6
            }
        }

        let newTemperature = temp(temperatureC) ?? current.temperature
        // Apparent temperature has to move with the temperature it is derived
        // from, or the hero says 68° and "feels like 81°" from two different
        // worlds. That mismatch is the whole reason this is computed here
        // rather than left as the model's.
        let newApparent: Double = {
            if let reported = temp(apparentC) { return reported }
            guard let c = temperatureC else { return current.apparentTemperature }
            let derived = Self.apparentC(temperatureC: c,
                                         humidityPercent: humidityPercent ?? current.humidity,
                                         windKPH: windSpeedKPH ?? 0)
            return temp(derived) ?? current.apparentTemperature
        }()

        let newWindSpeed = speed(windSpeedKPH) ?? current.windSpeed
        // Stations often file a sustained wind and no gust at all. Keeping the
        // model's gust beside an observed sustained speed can print a gust
        // *below* the steady wind, which reads as a bug; the floor keeps the
        // pair coherent whichever half is missing.
        let newWindGust = max(speed(windGustKPH) ?? current.windGust, newWindSpeed)

        return CurrentWeather(
            date: current.date,
            temperature: newTemperature,
            apparentTemperature: newApparent,
            code: observedCode ?? current.code,
            isDay: current.isDay,
            humidity: humidityPercent ?? current.humidity,
            precipitation: current.precipitation,
            cloudCover: current.cloudCover,
            // Pascals to hectopascals; nil leaves the model's MSL value, which
            // is the right answer when the station files no sea-level report.
            pressure: pressurePa.map { $0 / 100 } ?? current.pressure,
            windSpeed: newWindSpeed,
            windGust: newWindGust,
            windDirection: windDirectionDegrees ?? current.windDirection,
            uvIndex: current.uvIndex,
            visibility: visibilityMeters ?? current.visibility,
            dewPoint: temp(dewPointC) ?? current.dewPoint
        )
    }

    /// NWS heat index above 80 °F, NWS wind chill below 50 °F, the temperature
    /// itself in between — the same bands the service uses, so a derived
    /// "feels like" matches what the station would have reported had it sent
    /// one. Works in Fahrenheit because both formulas are defined there.
    static func apparentC(temperatureC: Double, humidityPercent: Double, windKPH: Double) -> Double {
        let f = temperatureC * 9 / 5 + 32
        let mph = windKPH / 1.609344
        let result: Double
        if f >= 80, humidityPercent >= 40 {
            let r = humidityPercent
            result = -42.379 + 2.04901523 * f + 10.14333127 * r
                - 0.22475541 * f * r - 0.00683783 * f * f
                - 0.05481717 * r * r + 0.00122874 * f * f * r
                + 0.00085282 * f * r * r - 0.00000199 * f * f * r * r
        } else if f <= 50, mph > 3 {
            let v = pow(mph, 0.16)
            result = 35.74 + 0.6215 * f - 35.75 * v + 0.4275 * f * v
        } else {
            result = f
        }
        return (result - 32) * 5 / 9
    }
}

// MARK: - Wire format

/// The NWS observation payload. Every measurement is `{value, unitCode,
/// qualityControl}` with a frequently-null value, so each one is unwrapped
/// through `Measurement` rather than trusted.
nonisolated struct NWSObservationResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let timestamp: String
        let textDescription: String?
        let temperature: Measurement?
        let dewpoint: Measurement?
        let windDirection: Measurement?
        let windSpeed: Measurement?
        let windGust: Measurement?
        let barometricPressure: Measurement?
        let seaLevelPressure: Measurement?
        let visibility: Measurement?
        let relativeHumidity: Measurement?
        let heatIndex: Measurement?
        let windChill: Measurement?
    }

    struct Measurement: Decodable {
        let value: Double?
        let unitCode: String?
        let qualityControl: String?

        /// "X" is the NWS's own "failed quality control"; "Z" means no QC was
        /// applied, which is common and fine. A null value is simply absent.
        var trusted: Double? {
            guard let value, qualityControl != "X" else { return nil }
            return value
        }

        /// Wind and visibility arrive in whichever unit the station files in,
        /// so normalise by the declared unitCode rather than assuming.
        var asKPH: Double? {
            guard let v = trusted else { return nil }
            guard let unit = unitCode else { return v }
            if unit.contains("km_h") { return v }
            if unit.contains("m_s") { return v * 3.6 }
            if unit.contains("mi_h") { return v * 1.609344 }
            return v
        }

        var asMetres: Double? {
            guard let v = trusted else { return nil }
            guard let unit = unitCode else { return v }
            return unit.contains("km") ? v * 1000 : v
        }
    }
}

/// The station list for a gridpoint. `features` carries the geometry, which is
/// what lets the caller sort by true distance instead of trusting the order.
nonisolated struct NWSStationsResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let id: String
        let geometry: Geometry?
        let properties: Properties

        struct Geometry: Decodable { let coordinates: [Double] }
        struct Properties: Decodable {
            let stationIdentifier: String?
            let name: String?
        }

        /// GeoJSON order is [longitude, latitude].
        var coordinate: CLLocationCoordinate2D? {
            guard let c = geometry?.coordinates, c.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: c[1], longitude: c[0])
        }
    }
}
