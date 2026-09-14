//
//  OpenMeteoResponse.swift
//  Weather
//
//  Decodable mirrors of the Open-Meteo JSON wire format. WeatherNextService
//  builds the same shape from Google's answer, and OpenMeteoGapFill splices
//  into it, which is why several fields are `var` rather than `let`.
//

import Foundation

struct ForecastResponse: Decodable {
    let timezone: String
    let utcOffsetSeconds: Int
    /// Metres above sea level at the grid cell; the UV model adds a little
    /// per kilometre of thinner air. `var`: WeatherNext has no elevation and
    /// the gap fill supplies it (see OpenMeteoGapFill.swift).
    var elevation: Double?
    let current: Current
    // `var`: the NBM overlay and the gap fill splice into these; see
    // NBMOverlay.swift and OpenMeteoGapFill.swift.
    var hourly: Hourly
    var daily: Daily
    /// 15-minute precipitation for the next ~3 h; optional because the model
    /// only covers some regions and the key is absent elsewhere. `var`: under
    /// WeatherNext the gap fill provides it.
    var minutely15: Minutely15?

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case elevation
        case current, hourly, daily
        case minutely15 = "minutely_15"
    }

    struct Minutely15: Decodable {
        let time: [String]
        let precipitation: [Double]
    }

    struct Current: Decodable {
        let time: String
        let temperature: Double
        let humidity: Double
        let apparentTemperature: Double
        let isDay: Int
        let precipitation: Double
        let weatherCode: Int
        let cloudCover: Double
        let pressure: Double
        let windSpeed: Double
        let windDirection: Double
        let windGust: Double

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case precipitation
            case weatherCode = "weather_code"
            case cloudCover = "cloud_cover"
            case pressure = "pressure_msl"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case windGust = "wind_gusts_10m"
        }
    }

    /// `var` fields are the ones the NBM overlay may splice calibrated values
    /// into for US locations (see NBMOverlay.swift), plus the cloud columns
    /// the gap fill completes under WeatherNext (see OpenMeteoGapFill.swift).
    /// The time axis and the remaining columns are `var` for one reason only:
    /// under WeatherNext the gap fill appends whole Open-Meteo hours wherever
    /// Google's series has none (quota, a shorter horizon, a failed page),
    /// and an appended row has to reach every column at once.
    struct Hourly: Decodable {
        var time: [String]
        var temperature: [Double]
        var humidity: [Double]
        var apparentTemperature: [Double]
        var precipitationProbability: [Int]
        var precipitation: [Double]
        var weatherCode: [Int]
        var windSpeed: [Double]
        var windDirection: [Double]
        var isDay: [Int]
        /// Total cloud cover, percent. The classic request does not ask for
        /// it (the layers below carry more information), so it is absent
        /// there; the WeatherNext adapter fills it with Google's per-hour
        /// total, which the gap fill scales Open-Meteo's layers against.
        var cloudCover: [Double]?
        /// Optional: these joined the request later, and absence must not
        /// fail the whole decode.
        var dewPoint: [Double]?
        var visibility: [Double]?
        /// Element-optional: under WeatherNext the layers are spliced in hour
        /// by hour from Open-Meteo, and an hour with no usable layer data must
        /// read as "unknown" for that hour alone, not sink the whole column.
        var cloudCoverLow: [Double?]?
        var cloudCoverMid: [Double?]?
        var cloudCoverHigh: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitationProbability = "precipitation_probability"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case isDay = "is_day"
            case cloudCover = "cloud_cover"
            case dewPoint = "dew_point_2m"
            case visibility
            case cloudCoverLow = "cloud_cover_low"
            case cloudCoverMid = "cloud_cover_mid"
            case cloudCoverHigh = "cloud_cover_high"
        }
    }

    /// Everything here is `var`: the NBM overlay splices calibrated values
    /// into the temperature, probability and wind columns for US locations
    /// (see NBMOverlay.swift), and under WeatherNext the gap fill prepends a
    /// whole pre-today row to every column at once (see OpenMeteoGapFill.swift).
    struct Daily: Decodable {
        var time: [String]
        var weatherCode: [Int]
        var tempMax: [Double]
        var tempMin: [Double]
        var apparentMax: [Double]
        var apparentMin: [Double]
        var sunrise: [String]
        var sunset: [String]
        var precipitationSum: [Double]
        var precipitationProbabilityMax: [Int]
        var windSpeedMax: [Double]
        var windGustMax: [Double]
        var windDirectionDominant: [Double]
        /// Optional for the same forward-compatibility reason as the hourly pair.
        var snowfallSum: [Double]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case tempMax = "temperature_2m_max"
            case tempMin = "temperature_2m_min"
            case apparentMax = "apparent_temperature_max"
            case apparentMin = "apparent_temperature_min"
            case sunrise, sunset
            case precipitationSum = "precipitation_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeedMax = "wind_speed_10m_max"
            case windGustMax = "wind_gusts_10m_max"
            case windDirectionDominant = "wind_direction_10m_dominant"
            case snowfallSum = "snowfall_sum"
        }
    }
}

struct AirQualityResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let usAQI: Double?
        let pm25: Double?
        let pm10: Double?
        let ozone: Double?
        let no2: Double?

        enum CodingKeys: String, CodingKey {
            case usAQI = "us_aqi"
            case pm25 = "pm2_5"
            case pm10
            case ozone
            case no2 = "nitrogen_dioxide"
        }
    }
}
