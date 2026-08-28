//
//  NBMOverlay.swift
//  Weather
//
//  Open-Meteo's default "best_match" model is raw GFS for US locations beyond
//  the ~48 h HRRR window, and GFS runs hot — summer daily highs came in 10 °F+
//  over the NWS forecast. The NBM (National Blend of Models) is the calibrated
//  blend the official NWS forecast tracks, so for US locations its temperatures,
//  humidity, winds and precipitation probabilities are spliced over the
//  best-match numbers. Everything NBM can't provide (weather codes, UV, layered
//  cloud cover, pressure, precipitation amounts, the 15-minute nowcast) stays
//  best-match.
//

import Foundation

/// The calibrated slice of an NBM forecast, spliced into a `ForecastResponse`
/// by matching wall-clock time strings. Every value array is element-optional:
/// Open-Meteo returns null for hours or fields the blend doesn't cover, and a
/// null must fall back to the best-match value, not zero.
nonisolated struct NBMOverlay: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double?]?
        let humidity: [Double?]?
        let apparentTemperature: [Double?]?
        let precipitationProbability: [Int?]?
        let windSpeed: [Double?]?
        let windDirection: [Double?]?
        let dewPoint: [Double?]?
        let visibility: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitationProbability = "precipitation_probability"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case dewPoint = "dew_point_2m"
            case visibility
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let tempMax: [Double?]?
        let tempMin: [Double?]?
        let apparentMax: [Double?]?
        let apparentMin: [Double?]?
        let precipitationProbabilityMax: [Int?]?
        let windSpeedMax: [Double?]?
        let windGustMax: [Double?]?
        let windDirectionDominant: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case tempMax = "temperature_2m_max"
            case tempMin = "temperature_2m_min"
            case apparentMax = "apparent_temperature_max"
            case apparentMin = "apparent_temperature_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeedMax = "wind_speed_10m_max"
            case windGustMax = "wind_gusts_10m_max"
            case windDirectionDominant = "wind_direction_10m_dominant"
        }
    }

    let hourly: Hourly
    let daily: Daily

    /// Rough NBM grid bounds — a gate to skip a pointless request for places
    /// that can't be covered, not the source of truth. Open-Meteo answers
    /// "no data" for uncovered spots inside the box and the overlay silently
    /// stands down.
    static func covers(_ place: Place) -> Bool {
        if let cc = place.countryCode?.uppercased(), cc != "US" { return false }
        return (23.0...51.0).contains(place.latitude)
            && ((-127.0)...(-65.0)).contains(place.longitude)
    }

    /// Nil on any failure — the overlay is an accuracy upgrade, never a reason
    /// to lose the forecast. Unit and span parameters mirror the main request
    /// exactly (visibility's unit, for one, follows the imperial/metric choice)
    /// so a spliced value can never arrive in a different unit or day grid.
    static func fetch(place: Place,
                      temperatureUnit: TemperatureUnit,
                      speedUnit: SpeedUnit,
                      precipUnit: PrecipUnit,
                      session: URLSession) async -> NBMOverlay? {
        guard covers(place) else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "models", value: "ncep_nbm_conus"),
            .init(name: "hourly", value: [
                "temperature_2m", "relative_humidity_2m", "apparent_temperature",
                "precipitation_probability", "wind_speed_10m",
                "wind_direction_10m", "dew_point_2m", "visibility"
            ].joined(separator: ",")),
            .init(name: "daily", value: [
                "temperature_2m_max", "temperature_2m_min",
                "apparent_temperature_max", "apparent_temperature_min",
                "precipitation_probability_max", "wind_speed_10m_max",
                "wind_gusts_10m_max", "wind_direction_10m_dominant"
            ].joined(separator: ",")),
            .init(name: "past_days", value: "1"),
            .init(name: "forecast_days", value: "10"),
            .init(name: "temperature_unit", value: temperatureUnit.apiValue),
            .init(name: "wind_speed_unit", value: speedUnit.apiValue),
            .init(name: "precipitation_unit", value: precipUnit.apiValue(temperatureUnit: temperatureUnit)),
            .init(name: "timezone", value: "auto")
        ]
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(NBMOverlay.self, from: data)
    }
}

extension ForecastResponse {
    /// Splices NBM values over the best-match arrays wherever both models
    /// carry the same wall-clock stamp. Null elements, missing fields and
    /// unmatched stamps leave the best-match value in place.
    nonisolated mutating func applyNBM(_ nbm: NBMOverlay) {
        let hourlyIndex = Self.indexByTime(hourly.time)
        func mergeHourly<T>(_ dst: inout [T], _ src: [T?]?) {
            Self.merge(&dst, src, times: nbm.hourly.time, index: hourlyIndex)
        }
        mergeHourly(&hourly.temperature, nbm.hourly.temperature)
        mergeHourly(&hourly.humidity, nbm.hourly.humidity)
        mergeHourly(&hourly.apparentTemperature, nbm.hourly.apparentTemperature)
        mergeHourly(&hourly.precipitationProbability, nbm.hourly.precipitationProbability)
        mergeHourly(&hourly.windSpeed, nbm.hourly.windSpeed)
        mergeHourly(&hourly.windDirection, nbm.hourly.windDirection)
        if var dewPoint = hourly.dewPoint {
            mergeHourly(&dewPoint, nbm.hourly.dewPoint)
            hourly.dewPoint = dewPoint
        }
        if var visibility = hourly.visibility {
            mergeHourly(&visibility, nbm.hourly.visibility)
            hourly.visibility = visibility
        }

        let dailyIndex = Self.indexByTime(daily.time)
        func mergeDaily<T>(_ dst: inout [T], _ src: [T?]?) {
            Self.merge(&dst, src, times: nbm.daily.time, index: dailyIndex)
        }
        mergeDaily(&daily.tempMax, nbm.daily.tempMax)
        mergeDaily(&daily.tempMin, nbm.daily.tempMin)
        mergeDaily(&daily.apparentMax, nbm.daily.apparentMax)
        mergeDaily(&daily.apparentMin, nbm.daily.apparentMin)
        mergeDaily(&daily.precipitationProbabilityMax, nbm.daily.precipitationProbabilityMax)
        mergeDaily(&daily.windSpeedMax, nbm.daily.windSpeedMax)
        mergeDaily(&daily.windGustMax, nbm.daily.windGustMax)
        mergeDaily(&daily.windDirectionDominant, nbm.daily.windDirectionDominant)
    }

    private nonisolated static func indexByTime(_ times: [String]) -> [String: Int] {
        var index: [String: Int] = [:]
        index.reserveCapacity(times.count)
        for (i, t) in times.enumerated() where index[t] == nil { index[t] = i }
        return index
    }

    private nonisolated static func merge<T>(_ dst: inout [T], _ src: [T?]?,
                                             times: [String], index: [String: Int]) {
        guard let src else { return }
        for (j, stamp) in times.enumerated() {
            guard j < src.count, let value = src[j],
                  let i = index[stamp], dst.indices.contains(i) else { continue }
            dst[i] = value
        }
    }
}
