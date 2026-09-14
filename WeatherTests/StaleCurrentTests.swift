//
//  StaleCurrentTests.swift
//  WeatherTests
//
//  The hero and the hourly strip must agree about what "now" is.
//
//  They didn't. A cached bundle is served for up to 24 hours, and while
//  `upcomingHours` recomputed its window against the wall clock on every read,
//  the current reading stayed frozen at `fetchedAt`. Opening the app on a hot
//  afternoon with a bundle fetched that morning showed 83° in the hero beside
//  a "Now" column reading 98°, and a brief that agreed with the hero. These
//  pin the rule that ended it.
//

import Testing
import Foundation
@testable import Haze_Weather

struct StaleCurrentTests {

    private func hour(_ date: Date, temp: Double, humidity: Double = 50,
                      code: Int = 0, wind: Double = 5) -> HourPoint {
        HourPoint(date: date, temperature: temp, apparentTemperature: temp + 2,
                  code: code, isDay: true, precipitationProbability: 0,
                  precipitation: 0, windSpeed: wind, windDirection: 180,
                  humidity: humidity, uvIndex: 4)
    }

    /// A morning fetch, an afternoon that gets much hotter: the exact shape of
    /// the reported screenshot.
    private func bundle(fetchedAgo: TimeInterval,
                        fetchedTemp: Double = 83,
                        nowTemp: Double = 98) -> WeatherBundle {
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-fetchedAgo)
        let current = CurrentWeather(
            date: fetchedAt, temperature: fetchedTemp, apparentTemperature: 86,
            code: 2, isDay: true, humidity: 72, precipitation: 0, cloudCover: 40,
            pressure: 1013, windSpeed: 6, windGust: 12, windDirection: 200,
            uvIndex: 3, visibility: 16000, dewPoint: 73)
        // Hours on the hour either side of the present.
        let hours = (-6...6).map { offset in
            hour(now.addingTimeInterval(Double(offset) * 3600),
                 temp: offset == 0 ? nowTemp : nowTemp - Double(abs(offset)))
        }
        return WeatherBundle(place: Place(name: "Test", admin1: nil, country: "United States",
                                          countryCode: "US", latitude: 32.7, longitude: -96.8,
                                          timezone: nil),
                             timezone: TimeZone(identifier: "America/Chicago")!,
                             current: current, hourly: hours, daily: [],
                             airQuality: nil, fetchedAt: fetchedAt)
    }

    // MARK: - The reported bug

    @Test func aStaleHeroFollowsTheHourlyStripInsteadOfTheFetch() {
        let stale = bundle(fetchedAgo: 8 * 3600)
        #expect(stale.isCurrentStale)
        // Not the 83° it was fetched with.
        #expect(stale.current.temperature != 83)
        // The hour the strip is showing.
        #expect(abs(stale.current.temperature - 98) < 0.01)
    }

    @Test func theHeroAndTheNowColumnAgree() {
        let stale = bundle(fetchedAgo: 8 * 3600)
        let nowColumn = stale.upcomingHours.first
        #expect(nowColumn != nil)
        #expect(abs(stale.current.temperature - (nowColumn?.temperature ?? -1)) < 0.01)
    }

    @Test func aFreshFetchIsLeftExactlyAlone() {
        let fresh = bundle(fetchedAgo: 5 * 60)
        #expect(!fresh.isCurrentStale)
        #expect(abs(fresh.current.temperature - 83) < 0.01)
        // Every fetched value survives untouched, not just the temperature.
        #expect(abs(fresh.current.dewPoint! - 73) < 0.01)
        #expect(fresh.current.code == 2)
    }

    @Test func theBoundaryIsTheDeclaredFreshnessWindow() {
        let justInside = bundle(fetchedAgo: WeatherBundle.currentFreshness - 60)
        let justOutside = bundle(fetchedAgo: WeatherBundle.currentFreshness + 60)
        #expect(!justInside.isCurrentStale)
        #expect(justOutside.isCurrentStale)
    }

    // MARK: - What the advance carries

    @Test func derivedValuesMoveWithTheTemperatureTheyDependOn() {
        // A stale dew point beside a fresh temperature is the same class of
        // disagreement, so it is recomputed rather than carried over.
        let stale = bundle(fetchedAgo: 8 * 3600)
        #expect(stale.current.dewPoint != 73)
        // 98 °F at 50% RH is roughly 76 °F dew point.
        #expect(abs((stale.current.dewPoint ?? 0) - 76) < 3)
    }

    @Test func gustIsNeverLeftBelowTheWindItAccompanies() {
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-8 * 3600)
        let current = CurrentWeather(
            date: fetchedAt, temperature: 60, apparentTemperature: 60, code: 0,
            isDay: true, humidity: 50, precipitation: 0, cloudCover: 0,
            pressure: 1013, windSpeed: 3, windGust: 4, windDirection: 180,
            uvIndex: 1, visibility: 16000, dewPoint: 40)
        let hours = [hour(now, temp: 60, wind: 35)]
        let stale = WeatherBundle(place: Place(name: "T", admin1: nil, country: nil,
                                               countryCode: nil, latitude: 0, longitude: 0,
                                               timezone: nil),
                                  timezone: .gmt, current: current, hourly: hours,
                                  daily: [], airQuality: nil, fetchedAt: fetchedAt)
        #expect(stale.current.windGust >= stale.current.windSpeed)
    }

    @Test func aBundleWhoseHoursNoLongerReachNowKeepsWhatItHas() {
        // Nothing better is available, so the fetched reading stands rather
        // than being replaced by an hour from yesterday.
        let fetchedAt = Date().addingTimeInterval(-30 * 3600)
        let current = CurrentWeather(
            date: fetchedAt, temperature: 55, apparentTemperature: 55, code: 1,
            isDay: true, humidity: 50, precipitation: 0, cloudCover: 10,
            pressure: 1013, windSpeed: 4, windGust: 8, windDirection: 90,
            uvIndex: 2, visibility: 16000, dewPoint: 38)
        let old = [hour(fetchedAt, temp: 55)]
        let bundle = WeatherBundle(place: Place(name: "T", admin1: nil, country: nil,
                                                countryCode: nil, latitude: 0, longitude: 0,
                                                timezone: nil),
                                   timezone: .gmt, current: current, hourly: old,
                                   daily: [], airQuality: nil, fetchedAt: fetchedAt)
        #expect(bundle.isCurrentStale)
        #expect(abs(bundle.current.temperature - 55) < 0.01)
    }

    // MARK: - Provenance

    @Test func aStalePageStopsCreditingTheStation() {
        // Otherwise the page reads "Observed at KDCA" over numbers that came
        // from the hourly model instead.
        var stale = bundle(fetchedAgo: 8 * 3600)
        stale.observation = StationObservation(
            stationID: "KTST", stationName: "Test", distanceMeters: 4000,
            observedAt: Date().addingTimeInterval(-8 * 3600),
            temperatureC: 28, apparentC: nil, dewPointC: 20, humidityPercent: 60,
            windSpeedKPH: 10, windGustKPH: nil, windDirectionDegrees: 180,
            pressurePa: nil, visibilityMeters: 16000, textDescription: "Clear")
        #expect(stale.observation != nil)
        #expect(stale.displayedObservation == nil)
    }

    @Test func aFreshPageStillCreditsIt() {
        var fresh = bundle(fetchedAgo: 60)
        fresh.observation = StationObservation(
            stationID: "KTST", stationName: "Test", distanceMeters: 4000,
            observedAt: Date().addingTimeInterval(-600),
            temperatureC: 28, apparentC: nil, dewPointC: 20, humidityPercent: 60,
            windSpeedKPH: 10, windGustKPH: nil, windDirectionDegrees: 180,
            pressurePa: nil, visibilityMeters: 16000, textDescription: "Clear")
        #expect(fresh.displayedObservation?.stationID == "KTST")
    }

    // MARK: - Round trip

    @Test func anOldCacheEntryStillDecodes() {
        // The stored key stayed "current" precisely so bundles written before
        // this split keep working; a wrong key here would silently empty every
        // reader's cache on update.
        let original = bundle(fetchedAgo: 60)
        let data = try! JSONEncoder().encode(original)
        #expect(String(data: data, encoding: .utf8)!.contains("\"current\""))
        let decoded = try! JSONDecoder().decode(WeatherBundle.self, from: data)
        #expect(abs(decoded.current.temperature - 83) < 0.01)
    }
}
