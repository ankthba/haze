//
//  OpenMeteoResponse.swift
//  Weather
//
//  Decodable mirrors of the Open-Meteo JSON wire format.
//

import Foundation

struct ForecastResponse: Decodable {
    let timezone: String
    let utcOffsetSeconds: Int
    let current: Current
    let hourly: Hourly
    let daily: Daily
    /// 15-minute precipitation for the next ~3 h; optional because the model
    /// only covers some regions and the key is absent elsewhere.
    let minutely15: Minutely15?

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
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

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let humidity: [Double]
        let apparentTemperature: [Double]
        let precipitationProbability: [Int]
        let precipitation: [Double]
        let weatherCode: [Int]
        let windSpeed: [Double]
        let windDirection: [Double]
        let uvIndex: [Double]
        let isDay: [Int]
        /// Optional: these joined the request later, and absence must not
        /// fail the whole decode.
        let dewPoint: [Double]?
        let visibility: [Double]?
        let cloudCoverLow: [Double]?
        let cloudCoverMid: [Double]?
        let cloudCoverHigh: [Double]?

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
            case uvIndex = "uv_index"
            case isDay = "is_day"
            case dewPoint = "dew_point_2m"
            case visibility
            case cloudCoverLow = "cloud_cover_low"
            case cloudCoverMid = "cloud_cover_mid"
            case cloudCoverHigh = "cloud_cover_high"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let tempMax: [Double]
        let tempMin: [Double]
        let apparentMax: [Double]
        let apparentMin: [Double]
        let sunrise: [String]
        let sunset: [String]
        let uvIndexMax: [Double]
        let precipitationSum: [Double]
        let precipitationProbabilityMax: [Int]
        let windSpeedMax: [Double]
        let windGustMax: [Double]
        let windDirectionDominant: [Double]
        /// Optional for the same forward-compatibility reason as the hourly pair.
        let snowfallSum: [Double]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case tempMax = "temperature_2m_max"
            case tempMin = "temperature_2m_min"
            case apparentMax = "apparent_temperature_max"
            case apparentMin = "apparent_temperature_min"
            case sunrise, sunset
            case uvIndexMax = "uv_index_max"
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
