//
//  WeatherServiceTests.swift
//  WeatherTests
//
//  The classic path's last step before transform: Open-Meteo switches hourly
//  visibility to feet whenever the precipitation unit is "inch", and every
//  reader in the app (Fmt.visibility, SunQuality) takes metres. Imperial
//  users saw feet divided by 1609 before this ran; the rule is pinned here so
//  it is not removed later as unrelated to the WeatherNext work it landed with.
//

import Testing
import Foundation
@testable import Haze_Weather

struct WeatherServiceVisibilityTests {
    private func response(visibility: [Double]?) -> ForecastResponse {
        ForecastResponse(
            timezone: "America/Los_Angeles",
            utcOffsetSeconds: -25200,
            elevation: nil,
            current: ForecastResponse.Current(
                time: "2026-09-08T14:00", temperature: 22, humidity: 55, apparentTemperature: 23,
                isDay: 1, precipitation: 0, weatherCode: 2, cloudCover: 40, pressure: 1013.2,
                windSpeed: 12, windDirection: 270, windGust: 20),
            hourly: ForecastResponse.Hourly(
                time: ["2026-09-08T13:00", "2026-09-08T14:00"],
                temperature: [21, 22], humidity: [58, 55], apparentTemperature: [21, 23],
                precipitationProbability: [10, 20], precipitation: [0.5, 1.0], weatherCode: [3, 61],
                windSpeed: [10, 12], windDirection: [250, 270], isDay: [1, 1],
                cloudCover: [40, 50], dewPoint: [12, 13], visibility: visibility,
                cloudCoverLow: nil, cloudCoverMid: nil, cloudCoverHigh: nil),
            daily: ForecastResponse.Daily(
                time: ["2026-09-08"], weatherCode: [61], tempMax: [25], tempMin: [15],
                apparentMax: [26], apparentMin: [14],
                sunrise: ["2026-09-08T06:35"], sunset: ["2026-09-08T19:10"],
                precipitationSum: [4], precipitationProbabilityMax: [60],
                windSpeedMax: [20], windGustMax: [35], windDirectionDominant: [270],
                snowfallSum: nil),
            minutely15: nil)
    }

    @Test("Under an inch preference the feet Open-Meteo sends become metres")
    func feetBecomeMetres() throws {
        var raw = response(visibility: [32808.4, 10000])
        raw.normaliseVisibility(precipAPI: "inch")
        let visibility = try #require(raw.hourly.visibility)
        #expect(abs(visibility[0] - 10000) < 0.1)
        #expect(abs(visibility[1] - 3048) < 0.01)
    }

    @Test("Under a millimetre preference the column is already metres and is left alone")
    func metresUntouched() {
        var raw = response(visibility: [16000, 10000])
        raw.normaliseVisibility(precipAPI: "mm")
        #expect(raw.hourly.visibility == [16000, 10000])
    }

    @Test("An absent column stays absent rather than becoming an empty one")
    func absentStaysAbsent() {
        var raw = response(visibility: nil)
        raw.normaliseVisibility(precipAPI: "inch")
        #expect(raw.hourly.visibility == nil)
    }
}
