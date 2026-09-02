//
//  NBMOverlayTests.swift
//  WeatherTests
//
//  The NBM splice. These go through real JSON on both sides, so the coding
//  keys and the element-optional decoding are exercised along with the merge
//  rules: match by wall-clock stamp, let nulls and unknown stamps fall back
//  to best-match, and never trust the two responses to be the same shape.
//

import Testing
import Foundation
@testable import Haze_Weather

struct NBMOverlayTests {

    // MARK: Fixtures

    /// The smallest ForecastResponse the decoder accepts: one current block,
    /// three hourly stamps, two daily stamps (yesterday + today).
    private func baseResponse() throws -> ForecastResponse {
        let json = """
        {
          "timezone": "America/New_York",
          "utc_offset_seconds": -14400,
          "current": {
            "time": "2026-08-28T17:00", "temperature_2m": 82.0,
            "relative_humidity_2m": 60.0, "apparent_temperature": 86.0,
            "is_day": 1, "precipitation": 0.0, "weather_code": 3,
            "cloud_cover": 80.0, "pressure_msl": 1015.0,
            "wind_speed_10m": 5.0, "wind_direction_10m": 180.0,
            "wind_gusts_10m": 10.0
          },
          "hourly": {
            "time": ["2026-08-28T00:00", "2026-08-28T01:00", "2026-08-28T02:00"],
            "temperature_2m": [80.0, 81.0, 82.0],
            "relative_humidity_2m": [50.0, 51.0, 52.0],
            "apparent_temperature": [84.0, 85.0, 86.0],
            "precipitation_probability": [10, 20, 30],
            "precipitation": [0.0, 0.1, 0.2],
            "weather_code": [1, 2, 3],
            "wind_speed_10m": [4.0, 5.0, 6.0],
            "wind_direction_10m": [90.0, 100.0, 110.0],
            "is_day": [0, 0, 0],
            "dew_point_2m": [60.0, 61.0, 62.0]
          },
          "daily": {
            "time": ["2026-08-27", "2026-08-28"],
            "weather_code": [3, 61],
            "temperature_2m_max": [85.0, 102.0],
            "temperature_2m_min": [65.0, 70.0],
            "apparent_temperature_max": [90.0, 108.0],
            "apparent_temperature_min": [68.0, 74.0],
            "sunrise": ["2026-08-27T06:40", "2026-08-28T06:41"],
            "sunset": ["2026-08-27T19:50", "2026-08-28T19:49"],
            "precipitation_sum": [0.0, 0.5],
            "precipitation_probability_max": [15, 60],
            "wind_speed_10m_max": [12.0, 14.0],
            "wind_gusts_10m_max": [20.0, 25.0],
            "wind_direction_10m_dominant": [200.0, 210.0]
          }
        }
        """
        return try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
    }

    private func overlay(_ json: String) throws -> NBMOverlay {
        try JSONDecoder().decode(NBMOverlay.self, from: Data(json.utf8))
    }

    // MARK: Merge rules

    @Test func matchedStampsAreSpliced() throws {
        var base = try baseResponse()
        let nbm = try overlay("""
        {
          "hourly": {
            "time": ["2026-08-28T01:00", "2026-08-28T02:00"],
            "temperature_2m": [78.5, 79.5],
            "apparent_temperature": [82.5, 83.5],
            "precipitation_probability": [44, 55]
          },
          "daily": {
            "time": ["2026-08-28"],
            "temperature_2m_max": [93.5],
            "temperature_2m_min": [69.0],
            "precipitation_probability_max": [40]
          }
        }
        """)
        base.applyNBM(nbm)

        #expect(base.hourly.temperature == [80.0, 78.5, 79.5])
        #expect(base.hourly.apparentTemperature == [84.0, 82.5, 83.5])
        #expect(base.hourly.precipitationProbability == [10, 44, 55])
        // Yesterday (unmatched stamp) stays best-match; today is NBM.
        #expect(base.daily.tempMax == [85.0, 93.5])
        #expect(base.daily.tempMin == [65.0, 69.0])
        #expect(base.daily.precipitationProbabilityMax == [15, 40])
    }

    @Test func nullsAndMissingFieldsKeepBestMatch() throws {
        var base = try baseResponse()
        let nbm = try overlay("""
        {
          "hourly": {
            "time": ["2026-08-28T00:00", "2026-08-28T01:00"],
            "temperature_2m": [null, 77.0],
            "dew_point_2m": [63.5, null]
          },
          "daily": {
            "time": ["2026-08-28"],
            "temperature_2m_max": [null]
          }
        }
        """)
        base.applyNBM(nbm)

        // A null element keeps the best-match value; a present one wins.
        #expect(base.hourly.temperature == [80.0, 77.0, 82.0])
        #expect(base.hourly.dewPoint == [63.5, 61.0, 62.0])
        // Fields the NBM response didn't carry at all are untouched.
        #expect(base.hourly.humidity == [50.0, 51.0, 52.0])
        #expect(base.hourly.windSpeed == [4.0, 5.0, 6.0])
        #expect(base.daily.tempMax == [85.0, 102.0])
        #expect(base.daily.windGustMax == [20.0, 25.0])
    }

    @Test func unknownStampsAndShortArraysAreSafe() throws {
        var base = try baseResponse()
        // Stamps the base doesn't know, plus a value array shorter than the
        // time array — neither may crash or corrupt anything.
        let nbm = try overlay("""
        {
          "hourly": {
            "time": ["2026-08-28T02:00", "2026-08-28T03:00", "2026-08-28T04:00"],
            "temperature_2m": [79.0]
          },
          "daily": {
            "time": ["2026-09-15"],
            "temperature_2m_max": [50.0]
          }
        }
        """)
        base.applyNBM(nbm)

        #expect(base.hourly.temperature == [80.0, 81.0, 79.0])
        #expect(base.daily.tempMax == [85.0, 102.0])
    }

    @Test func untouchedFieldsSurviveUnchanged() throws {
        var base = try baseResponse()
        let nbm = try overlay("""
        {
          "hourly": {
            "time": ["2026-08-28T00:00"],
            "temperature_2m": [70.0]
          },
          "daily": {
            "time": ["2026-08-28"],
            "temperature_2m_max": [90.0]
          }
        }
        """)
        base.applyNBM(nbm)

        // Codes, precipitation amounts and sun times are best-match only.
        #expect(base.hourly.weatherCode == [1, 2, 3])
        #expect(base.hourly.precipitation == [0.0, 0.1, 0.2])
        #expect(base.daily.weatherCode == [3, 61])
        #expect(base.daily.precipitationSum == [0.0, 0.5])
        #expect(base.daily.sunrise == ["2026-08-27T06:40", "2026-08-28T06:41"])
    }

    // MARK: Coverage gate

    private func place(_ name: String, _ cc: String?, _ lat: Double, _ lon: Double) -> Place {
        Place(name: name, admin1: nil, country: nil, countryCode: cc,
              latitude: lat, longitude: lon, timezone: nil)
    }

    @Test func coverageGate() {
        #expect(NBMOverlay.covers(place("Charlottesville", "US", 38.03, -78.48)))
        #expect(NBMOverlay.covers(place("Somewhere", nil, 40.0, -100.0)))
        #expect(!NBMOverlay.covers(place("London", "GB", 51.5, -0.12)))
        #expect(!NBMOverlay.covers(place("Honolulu", "US", 21.3, -157.85)))
        #expect(!NBMOverlay.covers(place("Anchorage", "US", 61.2, -149.9)))
    }
}
