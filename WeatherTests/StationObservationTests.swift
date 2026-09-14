//
//  StationObservationTests.swift
//  WeatherTests
//
//  The rules that decide whether a real instrument's report replaces the
//  model's current reading, and what happens to the values that come with it.
//  Each of these pins a mistake that is easy to reintroduce: pressure read
//  from the wrong field, a gust printed below the sustained wind it belongs
//  to, a "feels like" left behind by the temperature it derives from, or a
//  broken sensor half-applied over a perfectly good forecast.
//

import Testing
import Foundation
@testable import Haze_Weather

struct StationObservationTests {

    /// A modelled current reading in Fahrenheit/mph, the units the app fetches
    /// for a US reader.
    private func modelCurrent(temperatureF: Double = 70,
                              apparentF: Double = 70,
                              windMPH: Double = 8,
                              gustMPH: Double = 14,
                              pressureHPa: Double = 1013,
                              humidity: Double = 50) -> CurrentWeather {
        CurrentWeather(date: Date(), temperature: temperatureF, apparentTemperature: apparentF,
                       code: 3, isDay: true, humidity: humidity, precipitation: 0,
                       cloudCover: 60, pressure: pressureHPa, windSpeed: windMPH,
                       windGust: gustMPH, windDirection: 180, uvIndex: 3,
                       visibility: 16000, dewPoint: 50)
    }

    private func observation(temperatureC: Double? = 20,
                             apparentC: Double? = nil,
                             dewPointC: Double? = 10,
                             humidity: Double? = 55,
                             windKPH: Double? = 16.1,
                             gustKPH: Double? = nil,
                             direction: Double? = 270,
                             pressurePa: Double? = 101_500,
                             visibility: Double? = 12_000,
                             text: String? = "Clear",
                             distance: Double = 5_000,
                             age: TimeInterval = 600) -> StationObservation {
        StationObservation(stationID: "KTST", stationName: "Test Field",
                           distanceMeters: distance,
                           observedAt: Date().addingTimeInterval(-age),
                           temperatureC: temperatureC, apparentC: apparentC,
                           dewPointC: dewPointC, humidityPercent: humidity,
                           windSpeedKPH: windKPH, windGustKPH: gustKPH,
                           windDirectionDegrees: direction, pressurePa: pressurePa,
                           visibilityMeters: visibility, textDescription: text)
    }

    // MARK: - Unit conversion

    @Test func convertsStationSIIntoTheReadersUnits() {
        let result = observation(temperatureC: 20, windKPH: 16.09344)
            .applied(to: modelCurrent(), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(result.temperature - 68) < 0.01)
        #expect(abs(result.windSpeed - 10) < 0.01)
        // Pascals to hectopascals, which is what the pressure row prints.
        #expect(abs(result.pressure - 1015) < 0.01)
    }

    @Test func leavesCelsiusAndMetricSpeedsAlone() {
        let result = observation(temperatureC: 20, windKPH: 16)
            .applied(to: modelCurrent(), observedCode: nil,
                     temperatureUnit: .celsius, speedUnit: .kmh)
        #expect(abs(result.temperature - 20) < 0.01)
        #expect(abs(result.windSpeed - 16) < 0.01)
    }

    // MARK: - Pressure

    @Test func keepsTheModelPressureWhenTheStationFilesNoSeaLevelReport() {
        // A station that sends no MSL value must not silently leave its own
        // uncorrected reading, nor zero: the model's value stands.
        let result = observation(pressurePa: nil)
            .applied(to: modelCurrent(pressureHPa: 1013), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(result.pressure - 1013) < 0.01)
    }

    // MARK: - Wind

    @Test func gustNeverPrintsBelowTheSustainedWind() {
        // The station reports a 30 mph sustained wind and no gust; the model's
        // stale 14 mph gust must not end up under it.
        let result = observation(windKPH: 48.28, gustKPH: nil)
            .applied(to: modelCurrent(windMPH: 8, gustMPH: 14), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(result.windGust >= result.windSpeed)
        #expect(abs(result.windSpeed - 30) < 0.05)
    }

    @Test func usesTheReportedGustWhenThereIsOne() {
        let result = observation(windKPH: 16.09344, gustKPH: 48.28)
            .applied(to: modelCurrent(), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(result.windGust - 30) < 0.05)
    }

    // MARK: - Apparent temperature

    @Test func prefersTheStationsOwnHeatIndex() {
        let result = observation(temperatureC: 32, apparentC: 38)
            .applied(to: modelCurrent(temperatureF: 90, apparentF: 95), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(result.apparentTemperature - 100.4) < 0.1)
    }

    @Test func derivesFeelsLikeSoItCannotStrandTheModelsValue() {
        // No heatIndex/windChill in the report: the derived value must follow
        // the observed temperature, not stay at the model's 95°.
        let result = observation(temperatureC: 20, apparentC: nil, humidity: 50, windKPH: 5)
            .applied(to: modelCurrent(temperatureF: 90, apparentF: 95), observedCode: nil,
                     temperatureUnit: .fahrenheit, speedUnit: .mph)
        // Mild and calm: "feels like" is just the temperature.
        #expect(abs(result.apparentTemperature - 68) < 0.5)
    }

    @Test func heatIndexBandLiftsAHotHumidReading() {
        // 95 °F at 60% RH: the NWS heat index is well above the air temperature.
        let derived = StationObservation.apparentC(temperatureC: 35,
                                                   humidityPercent: 60, windKPH: 5)
        #expect(derived * 9 / 5 + 32 > 100)
    }

    @Test func windChillBandBitesOnAColdWindyReading() {
        // 20 °F with a 20 mph wind chills well below the air temperature.
        let derived = StationObservation.apparentC(temperatureC: -6.7,
                                                   humidityPercent: 50, windKPH: 32.2)
        #expect(derived * 9 / 5 + 32 < 20)
    }

    @Test func noBandAppliesInTheMiddle() {
        let derived = StationObservation.apparentC(temperatureC: 15,
                                                   humidityPercent: 50, windKPH: 10)
        #expect(abs(derived - 15) < 0.01)
    }

    // MARK: - Plausibility

    @Test func acceptsAStationThatAgreesWithTheModel() {
        let current = modelCurrent(temperatureF: 70)          // 21.1 °C
        #expect(observation(temperatureC: 20).isPlausible(against: current,
                                                          temperatureUnit: .fahrenheit))
    }

    @Test func acceptsARealInversionInsideTheBand() {
        // 8 °C colder than the model is a valley inversion, not a fault; the
        // band is deliberately wide enough to let it through.
        let current = modelCurrent(temperatureF: 70)          // 21.1 °C
        #expect(observation(temperatureC: 13).isPlausible(against: current,
                                                          temperatureUnit: .fahrenheit))
    }

    @Test func rejectsAStationWithAStuckSensor() {
        let current = modelCurrent(temperatureF: 70)          // 21.1 °C
        #expect(!observation(temperatureC: -40).isPlausible(against: current,
                                                            temperatureUnit: .fahrenheit))
    }

    @Test func rejectsAReportWithNoTemperatureAtAll() {
        #expect(!observation(temperatureC: nil).isPlausible(against: modelCurrent(),
                                                            temperatureUnit: .fahrenheit))
    }

    @Test func plausibilityWorksInCelsiusToo() {
        let current = modelCurrent(temperatureF: 21)          // already °C here
        #expect(observation(temperatureC: 20).isPlausible(against: current,
                                                          temperatureUnit: .celsius))
        #expect(!observation(temperatureC: 45).isPlausible(against: current,
                                                           temperatureUnit: .celsius))
    }

    // MARK: - Freshness

    @Test func aStaleReportIsNotFresh() {
        #expect(!observation(age: 3 * 3600).isFresh)
        #expect(observation(age: 600).isFresh)
    }

    // MARK: - Provenance

    @Test func provenanceNamesTheStationDistanceAndAge() {
        let line = observation(distance: 8046.72, age: 14 * 60)
            .provenance(usesImperial: true)
        #expect(line.contains("KTST"))
        #expect(line.contains("5.0 mi"))
        #expect(line.contains("14 minutes ago"))
    }

    @Test func provenanceGoesMetricForCelsiusReaders() {
        let line = observation(distance: 5000, age: 60).provenance(usesImperial: false)
        #expect(line.contains("5.0 km"))
        #expect(line.contains("1 minute ago"))
    }

    // MARK: - Bundle integration

    @Test func aTrustedObservationReplacesTheHeroAndIsCredited() {
        let bundle = Self.bundle(current: modelCurrent(temperatureF: 70))
        let enriched = bundle.applying(airQuality: nil,
                                       observation: observation(temperatureC: 20),
                                       observedCode: nil, alerts: nil,
                                       temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(enriched.current.temperature - 68) < 0.01)
        #expect(enriched.observation?.stationID == "KTST")
    }

    @Test func animplausibleObservationIsDroppedWholesaleAndNotCredited() {
        // The page must not show model numbers under a line crediting a station.
        let bundle = Self.bundle(current: modelCurrent(temperatureF: 70, humidity: 50))
        let enriched = bundle.applying(airQuality: nil,
                                       observation: observation(temperatureC: -40, humidity: 99),
                                       observedCode: nil, alerts: nil,
                                       temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(abs(enriched.current.temperature - 70) < 0.01)
        #expect(enriched.current.humidity == 50)   // not half-applied
        #expect(enriched.observation == nil)
    }

    @Test func anObservedCodeStillOverridesWithoutAUsableStationReport() {
        let bundle = Self.bundle(current: modelCurrent())
        let enriched = bundle.applying(airQuality: nil, observation: nil,
                                       observedCode: 61, alerts: nil,
                                       temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(enriched.current.code == 61)
        #expect(enriched.observation == nil)
    }

    private static func bundle(current: CurrentWeather) -> WeatherBundle {
        WeatherBundle(place: Place(name: "Test", admin1: nil, country: "United States",
                                   countryCode: "US", latitude: 38.9, longitude: -77.0,
                                   timezone: nil),
                      timezone: TimeZone(identifier: "America/New_York")!,
                      current: current, hourly: [], daily: [], airQuality: nil,
                      fetchedAt: Date())
    }
}
