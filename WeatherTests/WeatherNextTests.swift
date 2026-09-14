//
//  WeatherNextTests.swift
//  WeatherTests
//
//  The Google Weather adapter has one job: hand the rest of Haze a
//  ForecastResponse it cannot tell apart from an Open-Meteo one. These tests
//  pin the seams where that illusion could crack: condition names to WMO
//  codes, RFC 3339 instants to local wall-clock strings, wire units to the
//  user's units, proto3's habit of dropping every zero and false, and the
//  reshaping of day parts and history hours into the arrays transform()
//  expects, the fog Google's enum cannot name, and the slots left for the
//  Open-Meteo gap fill. No network anywhere; the adapter is fed decoded wire
//  objects.
//

import Testing
import Foundation
@testable import Haze_Weather

private typealias Wire = WeatherNextService.Wire

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

private func approx(_ a: Double, _ b: Double, within tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

private func approx(_ a: [Double], _ b: [Double], within tolerance: Double = 0.01) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

// MARK: - Fixture builders

private func celsius(_ degrees: Double) -> Wire.Temperature {
    Wire.Temperature(degrees: degrees, unit: "CELSIUS")
}

private func kmh(_ value: Double) -> Wire.Speed {
    Wire.Speed(value: value, unit: "KILOMETERS_PER_HOUR")
}

private func millimetres(_ quantity: Double) -> Wire.Depth {
    Wire.Depth(quantity: quantity, unit: "MILLIMETERS")
}

private func kilometres(_ distance: Double) -> Wire.Visibility {
    Wire.Visibility(distance: distance, unit: "KILOMETERS")
}

private func condition(_ type: String) -> Wire.Condition {
    Wire.Condition(type: type)
}

private func interval(_ start: String) -> Wire.Interval {
    Wire.Interval(startTime: start)
}

/// A nil `from` is a wind from due north, which proto3 sends as no direction.
private func wind(_ speed: Double, from degrees: Double? = nil, gust: Double? = nil) -> Wire.Wind {
    Wire.Wind(direction: degrees.map { Wire.Direction(degrees: $0) },
              speed: kmh(speed),
              gust: gust.map(kmh))
}

/// Nil percent and qpf are a dry spell as the wire sends it: keys absent.
private func precipitation(percent: Double? = nil, qpf: Double? = nil, snow: Double? = nil) -> Wire.Precipitation {
    Wire.Precipitation(probability: Wire.Probability(percent: percent, type: "RAIN"),
                       qpf: qpf.map(millimetres),
                       snowQpf: snow.map(millimetres))
}

/// One afternoon in the San Bernardino mountains: a current block, an hour of
/// history, two forecast hours (deliberately out of order) and two days, the
/// second of them a snow day with a 0 °C minimum so the zero-omission path is
/// exercised end to end.
private enum Fixture {
    static let place = Place(name: "Big Bear Lake", admin1: "California", country: "United States",
                             countryCode: "US", latitude: 34.24, longitude: -116.91,
                             timezone: "America/Los_Angeles")

    /// 14:00 PDT on 8 September 2026.
    static let current = Wire.CurrentConditions(
        currentTime: "2026-09-08T21:00:00Z",
        timeZone: Wire.TimeZoneInfo(id: "America/Los_Angeles"),
        isDaytime: true,
        weatherCondition: condition("PARTLY_CLOUDY"),
        temperature: celsius(22),
        feelsLikeTemperature: celsius(23),
        relativeHumidity: 55,
        airPressure: Wire.AirPressure(meanSeaLevelMillibars: 1013.2),
        wind: wind(12, from: 270, gust: 20),
        cloudCover: 40
    )

    /// The hour before now, as history/hours returns it: no feels-like.
    static let historyHour = Wire.Hour(
        interval: interval("2026-09-08T20:00:00Z"),
        weatherCondition: condition("CLOUDY"),
        temperature: celsius(21),
        dewPoint: celsius(12),
        precipitation: precipitation(percent: 10, qpf: 0.5),
        wind: wind(10, from: 250),
        visibility: kilometres(16),
        relativeHumidity: 58,
        cloudCover: 90,
        isDaytime: true
    )

    static let forecastHours: [Wire.Hour] = [
        Wire.Hour(
            interval: interval("2026-09-08T22:00:00Z"),
            weatherCondition: condition("CLEAR"),
            temperature: celsius(23),
            dewPoint: celsius(14),
            precipitation: precipitation(),
            wind: wind(36),
            visibility: kilometres(16),
            relativeHumidity: 50,
            cloudCover: 5,
            isDaytime: true
        ),
        Wire.Hour(
            interval: interval("2026-09-08T21:00:00Z"),
            weatherCondition: condition("LIGHT_RAIN"),
            temperature: celsius(22),
            feelsLikeTemperature: celsius(23),
            dewPoint: celsius(13),
            precipitation: precipitation(percent: 20, qpf: 1.0),
            wind: wind(12, from: 270, gust: 18),
            visibility: kilometres(10),
            relativeHumidity: 55,
            cloudCover: 80,
            isDaytime: true
        )
    ]

    static let days: [Wire.Day] = [
        Wire.Day(
            displayDate: Wire.DisplayDate(year: 2026, month: 9, day: 8),
            daytimeForecast: Wire.DayPart(
                weatherCondition: condition("PARTLY_CLOUDY"),
                precipitation: precipitation(percent: 20, qpf: 1.5),
                wind: wind(20, from: 270, gust: 30),
                cloudCover: 40),
            nighttimeForecast: Wire.DayPart(
                weatherCondition: condition("LIGHT_RAIN"),
                precipitation: precipitation(percent: 60, qpf: 2.5),
                wind: wind(15, from: 260, gust: 35),
                cloudCover: 85),
            maxTemperature: celsius(25),
            minTemperature: celsius(15),
            feelsLikeMaxTemperature: celsius(26),
            feelsLikeMinTemperature: celsius(14),
            sunEvents: Wire.SunEvents(sunriseTime: "2026-09-08T13:35:00Z",
                                      sunsetTime: "2026-09-09T02:10:00Z")
        ),
        Wire.Day(
            displayDate: Wire.DisplayDate(year: 2026, month: 9, day: 9),
            daytimeForecast: Wire.DayPart(
                weatherCondition: condition("SNOW"),
                precipitation: precipitation(percent: 80, qpf: 4, snow: 20),
                wind: wind(30, from: 10, gust: 45)),
            nighttimeForecast: Wire.DayPart(
                weatherCondition: condition("LIGHT_SNOW"),
                precipitation: precipitation(percent: 50, qpf: 6, snow: 30),
                wind: wind(25, from: 20, gust: 40)),
            maxTemperature: celsius(2),
            // Exactly 0 °C: proto3 drops `degrees` and leaves only the unit.
            minTemperature: Wire.Temperature(unit: "CELSIUS"),
            sunEvents: Wire.SunEvents(sunriseTime: "2026-09-09T13:36:00Z",
                                      sunsetTime: "2026-09-10T02:08:00Z")
        )
    ]

    static func build(temperatureUnit: TemperatureUnit = .celsius,
                      speedUnit: SpeedUnit = .kmh,
                      precipUnit: PrecipUnit = .mm,
                      timeZoneID: String? = "America/Los_Angeles",
                      current: Wire.CurrentConditions = Fixture.current,
                      hours: [Wire.Hour] = Fixture.forecastHours,
                      days: [Wire.Day] = Fixture.days,
                      history: [Wire.Hour] = [Fixture.historyHour],
                      place: Place = Fixture.place) -> (ForecastResponse, TimeZone) {
        WeatherNextService.makeForecastResponse(
            current: current, hours: hours, days: days, history: history,
            timeZoneID: timeZoneID, place: place,
            temperatureUnit: temperatureUnit, speedUnit: speedUnit, precipUnit: precipUnit)
    }
}

// MARK: - Condition mapping

struct WeatherNextConditionTests {
    @Test("Known condition types land on the WMO code the app draws", arguments: [
        ("CLEAR", 0), ("MOSTLY_CLEAR", 1), ("PARTLY_CLOUDY", 2), ("MOSTLY_CLOUDY", 3), ("CLOUDY", 3),
        ("WINDY", 2), ("WIND_AND_RAIN", 63),
        ("LIGHT_RAIN", 61), ("RAIN", 63), ("HEAVY_RAIN", 65), ("RAIN_PERIODICALLY_HEAVY", 65),
        ("LIGHT_RAIN_SHOWERS", 80), ("SCATTERED_SHOWERS", 80), ("RAIN_SHOWERS", 81), ("HEAVY_RAIN_SHOWERS", 82),
        ("LIGHT_SNOW", 71), ("SNOW", 73), ("HEAVY_SNOW", 75), ("BLOWING_SNOW", 75), ("SNOWSTORM", 75),
        ("SNOW_SHOWERS", 85), ("HEAVY_SNOW_SHOWERS", 86), ("RAIN_AND_SNOW", 66),
        ("HAIL", 96), ("HAIL_SHOWERS", 96),
        ("THUNDERSTORM", 95), ("THUNDERSHOWER", 95), ("SCATTERED_THUNDERSTORMS", 95), ("HEAVY_THUNDERSTORM", 99)
    ])
    func knownTypes(type: String, code: Int) {
        #expect(WeatherNextService.wmoCode(for: type, cloudCover: nil) == code)
    }

    @Test("A known type ignores cloud cover")
    func knownTypeIgnoresCloudCover() {
        #expect(WeatherNextService.wmoCode(for: "CLEAR", cloudCover: 100) == 0)
        #expect(WeatherNextService.wmoCode(for: "HEAVY_RAIN", cloudCover: 0) == 65)
    }

    @Test("Unspecified and unknown types read the sky from cloud cover, overcast without it")
    func fallbackFromCloudCover() {
        #expect(WeatherNextService.wmoCode(for: "TYPE_UNSPECIFIED", cloudCover: 5) == 0)
        #expect(WeatherNextService.wmoCode(for: "TYPE_UNSPECIFIED", cloudCover: 50) == 2)
        #expect(WeatherNextService.wmoCode(for: "TYPE_UNSPECIFIED", cloudCover: nil) == 3)
        #expect(WeatherNextService.wmoCode(for: "FROGS", cloudCover: nil) == 3)
        #expect(WeatherNextService.wmoCode(for: "FROGS", cloudCover: 20) == 1)
        #expect(WeatherNextService.wmoCode(for: "", cloudCover: 100) == 3)
    }

    @Test("The cloud cover thresholds sit at 12, 37 and 75 percent")
    func cloudCoverBoundaries() {
        let sky = { WeatherNextService.wmoCode(for: "TYPE_UNSPECIFIED", cloudCover: $0) }
        #expect(sky(0) == 0)
        #expect(sky(12) == 0)
        #expect(sky(13) == 1)
        #expect(sky(37) == 1)
        #expect(sky(38) == 2)
        #expect(sky(75) == 2)
        #expect(sky(76) == 3)
        #expect(sky(100) == 3)
    }
}

// MARK: - Time

struct WeatherNextTimeTests {
    @Test("A UTC instant becomes Open-Meteo's local wall-clock string")
    func utcToLocal() {
        #expect(WeatherNextService.localTimeString("2026-09-08T21:00:00Z", in: losAngeles) == "2026-09-08T14:00")
    }

    @Test("Fractional seconds are accepted and dropped")
    func fractionalSeconds() {
        #expect(WeatherNextService.localTimeString("2026-09-08T21:00:00.000Z", in: losAngeles) == "2026-09-08T14:00")
        #expect(WeatherNextService.localTimeString("2026-09-08T21:00:00.123456Z", in: losAngeles) == "2026-09-08T14:00")
    }

    @Test("Midnight formats as 00:00 and rolls the date")
    func midnight() {
        #expect(WeatherNextService.localTimeString("2026-09-09T07:00:00Z", in: losAngeles) == "2026-09-09T00:00")
    }

    @Test("A half-hour zone keeps its minutes")
    func halfHourOffset() {
        #expect(WeatherNextService.localTimeString("2026-09-08T21:00:00Z", in: kolkata) == "2026-09-09T02:30")
    }

    @Test("An explicit offset in the instant is honoured")
    func explicitOffset() {
        #expect(WeatherNextService.localTimeString("2026-09-08T14:00:00-07:00", in: losAngeles) == "2026-09-08T14:00")
        #expect(WeatherNextService.localTimeString("2026-09-08T14:00:00-07:00", in: kolkata) == "2026-09-09T02:30")
    }

    @Test("Garbage is nil rather than a crash or a bogus date")
    func unparseable() {
        #expect(WeatherNextService.localTimeString("yesterday-ish", in: losAngeles) == nil)
        #expect(WeatherNextService.localTimeString("2026-09-08T14:00", in: losAngeles) == nil)
        #expect(WeatherNextService.localTimeString("", in: losAngeles) == nil)
    }

    @Test("LocalClock gives date-only strings in the same zone")
    func clockDateOnly() throws {
        let clock = WeatherNextService.LocalClock(timeZone: losAngeles)
        let date = try #require(clock.date("2026-09-09T06:59:00Z"))
        #expect(clock.dateString(date) == "2026-09-08")
        #expect(clock.dateTimeString(date) == "2026-09-08T23:59")
    }

    @Test("An hour label keeps a start on the hour and snaps an off-hour start to the hour holding its midpoint")
    func hourLabel() throws {
        let la = WeatherNextService.LocalClock(timeZone: losAngeles)
        #expect(la.hourLabel(try #require(la.date("2026-09-08T21:00:00Z"))) == "2026-09-08T14:00")

        // Kolkata is UTC+5:30, so a UTC-hour interval starts at :30 local and
        // runs 01:30 to 02:30; its midpoint is 02:00.
        let india = WeatherNextService.LocalClock(timeZone: kolkata)
        #expect(india.hourLabel(try #require(india.date("2026-09-08T20:00:00Z"))) == "2026-09-09T02:00")
        #expect(india.hourLabel(try #require(india.date("2026-09-08T18:00:00Z"))) == "2026-09-09T00:00")
        #expect(india.hourLabel(try #require(india.date("2026-09-08T17:00:00Z"))) == "2026-09-08T23:00")

        // Kathmandu is UTC+5:45: 01:45 to 02:45 is filed under 02:00.
        let nepal = WeatherNextService.LocalClock(timeZone: TimeZone(identifier: "Asia/Kathmandu")!)
        #expect(nepal.hourLabel(try #require(nepal.date("2026-09-08T20:00:00Z"))) == "2026-09-09T02:00")
    }
}

// MARK: - Units

struct WeatherNextUnitTests {
    @Test("Temperature converts from either wire unit to the preference")
    func temperature() {
        #expect(WeatherNextService.temperature(10, unit: "CELSIUS", to: .fahrenheit) == 50)
        #expect(WeatherNextService.temperature(10, unit: "CELSIUS", to: .celsius) == 10)
        #expect(WeatherNextService.temperature(50, unit: "FAHRENHEIT", to: .celsius) == 10)
        #expect(WeatherNextService.temperature(0, unit: nil, to: .fahrenheit) == 32)
    }

    @Test("Speed converts km/h to m/s and mph, and reads mph on the wire")
    func speed() {
        #expect(WeatherNextService.speed(36, unit: "KILOMETERS_PER_HOUR", to: .ms) == 10)
        #expect(approx(WeatherNextService.speed(36, unit: "KILOMETERS_PER_HOUR", to: .mph), 22.37))
        #expect(WeatherNextService.speed(36, unit: "KILOMETERS_PER_HOUR", to: .kmh) == 36)
        #expect(approx(WeatherNextService.speed(10, unit: "MILES_PER_HOUR", to: .kmh), 16.09))
    }

    @Test("Depths go through millimetres to the precipitation unit")
    func depth() {
        #expect(WeatherNextService.depthMillimetres(1, unit: "INCHES") == 25.4)
        #expect(WeatherNextService.depthMillimetres(7, unit: "MILLIMETERS") == 7)
        #expect(WeatherNextService.precipitationDepth(millimetres: 25.4, precipUnitAPI: "inch") == 1)
        #expect(WeatherNextService.precipitationDepth(millimetres: 25.4, precipUnitAPI: "mm") == 25.4)
    }

    @Test("Snow water equivalent becomes depth at 7:1, in centimetres under metric and inches under imperial")
    func snowfall() {
        // 10 mm of water is 7 cm of snow, Open-Meteo's own ratio.
        #expect(WeatherNextService.snowfallDepth(waterEquivalentMillimetres: 10, precipUnitAPI: "mm") == 7)
        #expect(WeatherNextService.snowfallDepth(waterEquivalentMillimetres: 50, precipUnitAPI: "mm") == 35)
        #expect(approx(WeatherNextService.snowfallDepth(waterEquivalentMillimetres: 25.4, precipUnitAPI: "inch"), 7))
        #expect(approx(WeatherNextService.snowfallDepth(waterEquivalentMillimetres: 3.6286, precipUnitAPI: "inch"), 1.0, within: 0.001))
    }

    @Test("Visibility is metres whatever the precipitation unit")
    func visibility() {
        #expect(WeatherNextService.distanceMetres(16, unit: "KILOMETERS") == 16000)
        #expect(approx(WeatherNextService.distanceMetres(1, unit: "MILES"), 1609.344, within: 0.001))
        let (metric, _) = Fixture.build(precipUnit: .mm)
        let (imperial, _) = Fixture.build(temperatureUnit: .fahrenheit, precipUnit: .inch)
        #expect(metric.hourly.visibility == [16000, 10000, 16000])
        #expect(imperial.hourly.visibility == [16000, 10000, 16000])
    }
}

// MARK: - Wire decoding

struct WeatherNextWireTests {
    @Test("An hour with every zero dropped decodes to nils, and the adapter restores the zeros")
    func hourWithOmittedZeros() throws {
        // Midnight, 0 °C, calm from due north, dry, no cloud: proto3 sends none
        // of those values. `displayDateTime` has no `hours` for the same reason.
        let json = """
        {
          "interval": {"startTime": "2026-09-09T07:00:00Z", "endTime": "2026-09-09T08:00:00Z"},
          "displayDateTime": {"year": 2026, "month": 9, "day": 9, "utcOffset": "-25200s"},
          "weatherCondition": {
            "iconBaseUri": "https://maps.gstatic.com/weather/v1/clear_night",
            "description": {"text": "Clear", "languageCode": "en"},
            "type": "CLEAR"
          },
          "temperature": {"unit": "CELSIUS"},
          "feelsLikeTemperature": {"degrees": -1.5, "unit": "CELSIUS"},
          "dewPoint": {"degrees": -3, "unit": "CELSIUS"},
          "precipitation": {
            "probability": {"type": "RAIN"},
            "qpf": {"unit": "MILLIMETERS"},
            "snowQpf": {"unit": "MILLIMETERS"}
          },
          "airPressure": {"meanSeaLevelMillibars": 1021.4},
          "wind": {
            "speed": {"value": 5, "unit": "KILOMETERS_PER_HOUR"},
            "gust": {"value": 9, "unit": "KILOMETERS_PER_HOUR"}
          },
          "visibility": {"distance": 16, "unit": "KILOMETERS"},
          "relativeHumidity": 78
        }
        """
        let hour = try JSONDecoder().decode(Wire.Hour.self, from: Data(json.utf8))
        #expect(hour.temperature?.unit == "CELSIUS")
        #expect(hour.temperature?.degrees == nil)
        #expect(hour.feelsLikeTemperature?.degrees == -1.5)
        #expect(hour.cloudCover == nil)
        #expect(hour.wind?.direction == nil)
        #expect(hour.wind?.speed?.value == 5)
        #expect(hour.isDaytime == nil)
        #expect(hour.uvIndex == nil)
        #expect(hour.precipitation?.probability?.percent == nil)
        #expect(hour.precipitation?.qpf?.quantity == nil)
        #expect(hour.relativeHumidity == 78)

        let (metric, _) = Fixture.build(hours: [hour], days: [], history: [])
        #expect(metric.hourly.time == ["2026-09-09T00:00"])
        #expect(metric.hourly.temperature == [0])
        #expect(metric.hourly.apparentTemperature == [-1.5])
        #expect(metric.hourly.dewPoint == [-3])
        #expect(metric.hourly.precipitationProbability == [0])
        #expect(metric.hourly.precipitation == [0])
        #expect(metric.hourly.weatherCode == [0])
        #expect(metric.hourly.windSpeed == [5])
        #expect(metric.hourly.windDirection == [0])
        #expect(metric.hourly.isDay == [0])
        #expect(metric.hourly.humidity == [78])
        #expect(metric.hourly.visibility == [16000])

        // The zero is applied before conversion: an absent 0 °C is 32 °F.
        let (imperial, _) = Fixture.build(temperatureUnit: .fahrenheit, speedUnit: .mph, precipUnit: .inch,
                                          hours: [hour], days: [], history: [])
        #expect(imperial.hourly.temperature == [32])
        #expect(approx(imperial.hourly.apparentTemperature, [29.3]))
    }

    @Test("An hours page carries its zone and continuation token")
    func hoursPage() throws {
        let json = """
        {
          "forecastHours": [
            {
              "interval": {"startTime": "2026-09-08T21:00:00Z", "endTime": "2026-09-08T22:00:00Z"},
              "temperature": {"degrees": 22.3, "unit": "CELSIUS"},
              "isDaytime": true
            }
          ],
          "timeZone": {"id": "America/Los_Angeles"},
          "nextPageToken": "ChQKEgoQ"
        }
        """
        let page = try JSONDecoder().decode(Wire.HoursPage.self, from: Data(json.utf8))
        #expect(page.forecastHours?.count == 1)
        #expect(page.forecastHours?.first?.temperature?.degrees == 22.3)
        #expect(page.forecastHours?.first?.isDaytime == true)
        #expect(page.timeZone?.id == "America/Los_Angeles")
        #expect(page.nextPageToken == "ChQKEgoQ")

        let history = try JSONDecoder().decode(Wire.HistoryPage.self, from: Data("""
        {"historyHours": [], "timeZone": {"id": "America/Los_Angeles"}}
        """.utf8))
        #expect(history.historyHours?.isEmpty == true)
        #expect(history.nextPageToken == nil)
    }

    @Test("A night-time current block with omitted flags reads as night, 0 °C and calm")
    func currentWithOmissions() throws {
        let json = """
        {
          "currentTime": "2026-09-09T07:00:00Z",
          "timeZone": {"id": "America/Los_Angeles"},
          "weatherCondition": {"type": "CLEAR"},
          "temperature": {"unit": "CELSIUS"},
          "relativeHumidity": 90,
          "wind": {"speed": {"unit": "KILOMETERS_PER_HOUR"}},
          "airPressure": {"meanSeaLevelMillibars": 1018}
        }
        """
        let current = try JSONDecoder().decode(Wire.CurrentConditions.self, from: Data(json.utf8))
        #expect(current.isDaytime == nil)
        #expect(current.cloudCover == nil)
        #expect(current.temperature?.degrees == nil)

        let (response, _) = Fixture.build(timeZoneID: nil, current: current, hours: [], days: [], history: [])
        #expect(response.timezone == "America/Los_Angeles")
        #expect(response.current.time == "2026-09-09T00:00")
        #expect(response.current.isDay == 0)
        #expect(response.current.temperature == 0)
        #expect(response.current.apparentTemperature == 0)
        #expect(response.current.windSpeed == 0)
        #expect(response.current.windGust == 0)
        #expect(response.current.cloudCover == 0)
        #expect(response.current.weatherCode == 0)
        #expect(response.current.pressure == 1018)
        #expect(response.current.humidity == 90)
    }

    @Test("A days page decodes and a dry, still day with a 0 °C low comes out all zeros")
    func daysPageWithOmissions() throws {
        let json = """
        {
          "forecastDays": [{
            "interval": {"startTime": "2026-09-08T14:00:00Z", "endTime": "2026-09-09T14:00:00Z"},
            "displayDate": {"year": 2026, "month": 9, "day": 8},
            "daytimeForecast": {
              "weatherCondition": {"type": "MOSTLY_CLEAR"},
              "precipitation": {"probability": {"type": "RAIN"}, "qpf": {"unit": "MILLIMETERS"}},
              "wind": {"speed": {"unit": "KILOMETERS_PER_HOUR"}}
            },
            "nighttimeForecast": {"weatherCondition": {"type": "CLEAR"}},
            "maxTemperature": {"degrees": 9, "unit": "CELSIUS"},
            "minTemperature": {"unit": "CELSIUS"},
            "sunEvents": {"sunriseTime": "2026-09-08T13:35:00Z", "sunsetTime": "2026-09-09T02:10:00Z"}
          }],
          "timeZone": {"id": "America/Los_Angeles"}
        }
        """
        let page = try JSONDecoder().decode(Wire.DaysPage.self, from: Data(json.utf8))
        #expect(page.nextPageToken == nil)
        #expect(page.forecastDays?.count == 1)

        let (response, _) = Fixture.build(hours: [], days: page.forecastDays ?? [], history: [])
        #expect(response.daily.time == ["2026-09-08"])
        #expect(response.daily.weatherCode == [1])
        #expect(response.daily.tempMax == [9])
        #expect(response.daily.tempMin == [0])
        #expect(response.daily.apparentMax == [9])
        #expect(response.daily.apparentMin == [0])
        #expect(response.daily.precipitationSum == [0])
        #expect(response.daily.precipitationProbabilityMax == [0])
        #expect(response.daily.windSpeedMax == [0])
        #expect(response.daily.windGustMax == [0])
        #expect(response.daily.windDirectionDominant == [0])
        #expect(response.daily.snowfallSum == [0])
        #expect(response.daily.sunrise == ["2026-09-08T06:35"])
        #expect(response.daily.sunset == ["2026-09-08T19:10"])
    }
}

// MARK: - Adapter

struct WeatherNextAdapterTests {
    @Test("The zone passes through and the current block is local, metric and complete")
    func currentBlock() {
        let (response, tz) = Fixture.build()
        #expect(tz.identifier == "America/Los_Angeles")
        #expect(response.timezone == "America/Los_Angeles")
        // Pacific time is -7 h in summer, -8 h in winter; the offset is taken now.
        #expect([-25200, -28800].contains(response.utcOffsetSeconds))
        #expect(response.elevation == nil)
        #expect(response.minutely15 == nil)

        let current = response.current
        #expect(current.time == "2026-09-08T14:00")
        #expect(current.temperature == 22)
        #expect(current.apparentTemperature == 23)
        #expect(current.humidity == 55)
        #expect(current.isDay == 1)
        #expect(current.precipitation == 0)
        #expect(current.weatherCode == 2)
        #expect(current.cloudCover == 40)
        #expect(current.pressure == 1013.2)
        #expect(current.windSpeed == 12)
        #expect(current.windDirection == 270)
        #expect(current.windGust == 20)
    }

    @Test("Hourly merges history before forecast, sorted by instant, as local strings")
    func hourlyArrays() {
        let (response, _) = Fixture.build()
        let hourly = response.hourly
        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(hourly.temperature == [21, 22, 23])
        // No feels-like on the history hour falls back to its temperature.
        #expect(hourly.apparentTemperature == [21, 23, 23])
        #expect(hourly.humidity == [58, 55, 50])
        #expect(hourly.precipitationProbability == [10, 20, 0])
        #expect(hourly.precipitation == [0.5, 1.0, 0])
        #expect(hourly.weatherCode == [3, 61, 0])
        #expect(hourly.windSpeed == [10, 12, 36])
        #expect(hourly.windDirection == [250, 270, 0])
        #expect(hourly.isDay == [1, 1, 1])
        #expect(hourly.dewPoint == [12, 13, 14])
        #expect(hourly.visibility == [16000, 10000, 16000])
        // Google has no per-layer cloud cover; nil tells UVIndex and SunQuality so.
        #expect(hourly.cloudCoverLow == nil)
        #expect(hourly.cloudCoverMid == nil)
        #expect(hourly.cloudCoverHigh == nil)
    }

    @Test("Daily sums the day and night parts and keeps the worst probability")
    func dailyArrays() {
        let (response, _) = Fixture.build()
        let daily = response.daily
        #expect(daily.time == ["2026-09-08", "2026-09-09"])
        // Day 1 is partly cloudy by day and rainy by night: the rain is the headline.
        #expect(daily.weatherCode == [61, 73])
        #expect(daily.tempMax == [25, 2])
        #expect(daily.tempMin == [15, 0])
        #expect(daily.apparentMax == [26, 2])
        #expect(daily.apparentMin == [14, 0])
        #expect(daily.sunrise == ["2026-09-08T06:35", "2026-09-09T06:36"])
        #expect(daily.sunset == ["2026-09-08T19:10", "2026-09-09T19:08"])
        #expect(daily.precipitationSum == [4.0, 10.0])
        #expect(daily.precipitationProbabilityMax == [60, 80])
        #expect(daily.windSpeedMax == [20, 30])
        #expect(daily.windGustMax == [35, 45])
        #expect(daily.windDirectionDominant == [270, 10])
        // 20 mm + 30 mm of snow water is 35 cm of snow under metric.
        #expect(daily.snowfallSum == [0, 35.0])
    }

    @Test("A Fahrenheit, mph and inch preference converts every relevant field and nothing else")
    func imperialPreference() {
        let (response, _) = Fixture.build(temperatureUnit: .fahrenheit, speedUnit: .mph, precipUnit: .inch)

        let current = response.current
        #expect(approx(current.temperature, 71.6))
        #expect(approx(current.apparentTemperature, 73.4))
        #expect(approx(current.windSpeed, 7.46))
        #expect(approx(current.windGust, 12.43))
        #expect(current.humidity == 55)
        #expect(current.pressure == 1013.2)
        #expect(current.windDirection == 270)

        let hourly = response.hourly
        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(approx(hourly.temperature, [69.8, 71.6, 73.4]))
        #expect(approx(hourly.apparentTemperature, [69.8, 73.4, 73.4]))
        #expect(approx(hourly.dewPoint ?? [], [53.6, 55.4, 57.2]))
        #expect(approx(hourly.windSpeed, [6.21, 7.46, 22.37]))
        #expect(approx(hourly.precipitation, [0.0197, 0.0394, 0], within: 0.0001))
        #expect(hourly.visibility == [16000, 10000, 16000])
        #expect(hourly.precipitationProbability == [10, 20, 0])
        #expect(hourly.humidity == [58, 55, 50])
        #expect(hourly.weatherCode == [3, 61, 0])

        let daily = response.daily
        #expect(approx(daily.tempMax, [77, 35.6]))
        #expect(approx(daily.tempMin, [59, 32]))
        #expect(approx(daily.apparentMax, [78.8, 35.6]))
        #expect(approx(daily.apparentMin, [57.2, 32]))
        #expect(approx(daily.precipitationSum, [0.1575, 0.3937], within: 0.0001))
        #expect(approx(daily.snowfallSum ?? [], [0, 13.7795], within: 0.0001))
        #expect(approx(daily.windSpeedMax, [12.43, 18.64]))
        #expect(approx(daily.windGustMax, [21.75, 27.96]))
        #expect(daily.precipitationProbabilityMax == [60, 80])
        #expect(daily.sunrise == ["2026-09-08T06:35", "2026-09-09T06:36"])
    }

    @Test("Auto precipitation follows the temperature unit")
    func autoPrecipitation() {
        let (metric, _) = Fixture.build(temperatureUnit: .celsius, precipUnit: .auto)
        #expect(metric.daily.precipitationSum == [4.0, 10.0])
        #expect(metric.hourly.visibility?.first == 16000)

        let (imperial, _) = Fixture.build(temperatureUnit: .fahrenheit, precipUnit: .auto)
        #expect(approx(imperial.daily.precipitationSum, [0.1575, 0.3937], within: 0.0001))
        #expect(imperial.hourly.visibility?.first == 16000)
    }

    @Test("Where history and forecast share an hour, the forecast record wins")
    func forecastWinsOverlap() {
        var stale = Fixture.historyHour
        stale.interval = interval("2026-09-08T21:00:00Z")
        stale.temperature = celsius(19)
        let (response, _) = Fixture.build(days: [], history: [stale])
        #expect(response.hourly.time == ["2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(response.hourly.temperature == [22, 23])
    }

    @Test("An hour without a start instant is dropped, not misfiled")
    func hourWithoutInterval() {
        var orphan = Fixture.historyHour
        orphan.interval = nil
        let (response, _) = Fixture.build(days: [], history: [orphan])
        #expect(response.hourly.time == ["2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(response.hourly.temperature.count == response.hourly.time.count)
    }

    @Test("A day without a display date takes its date from the interval start, and one with neither is skipped")
    func dayDateFallbacks() {
        var fromInterval = Fixture.days[0]
        fromInterval.displayDate = nil
        fromInterval.interval = interval("2026-09-10T07:00:00Z")
        var dateless = Fixture.days[1]
        dateless.displayDate = nil
        dateless.interval = nil
        let (response, _) = Fixture.build(hours: [], days: [fromInterval, dateless], history: [])
        #expect(response.daily.time == ["2026-09-10"])
        #expect(response.daily.tempMax == [25])
    }

    @Test("The daily code is the more severe half, then whichever half exists, then overcast")
    func dailyCodePreference() {
        var nightOnly = Fixture.days[0]
        nightOnly.daytimeForecast = nil
        var dayOnly = Fixture.days[0]
        dayOnly.nighttimeForecast = nil
        var neither = Fixture.days[1]
        neither.daytimeForecast = nil
        neither.nighttimeForecast = nil
        // Showers by day, snow by night: snow is the worse kind even though 80 > 71.
        var snowNight = Fixture.days[0]
        snowNight.daytimeForecast?.weatherCondition = condition("LIGHT_RAIN_SHOWERS")
        snowNight.nighttimeForecast?.weatherCondition = condition("LIGHT_SNOW")
        // Thunder by day beats heavy snow by night.
        var stormDay = Fixture.days[0]
        stormDay.daytimeForecast?.weatherCondition = condition("THUNDERSTORM")
        stormDay.nighttimeForecast?.weatherCondition = condition("HEAVY_SNOW")
        // Two sky codes: the cloudier one.
        var skies = Fixture.days[0]
        skies.daytimeForecast?.weatherCondition = condition("CLEAR")
        skies.nighttimeForecast?.weatherCondition = condition("MOSTLY_CLOUDY")
        let (response, _) = Fixture.build(
            hours: [], days: [Fixture.days[0], nightOnly, dayOnly, neither, snowNight, stormDay, skies], history: [])
        #expect(response.daily.weatherCode == [61, 61, 2, 3, 71, 95, 3])
    }

    @Test("A day the hourly series covers takes its figures from the hours, calendar-day style")
    func dailyFromHours() {
        // 24 hours of 9 September, Pacific, one record per local hour. The
        // temperature runs 10 °C at midnight up to 33 °C at 23:00 so the
        // hourly max and min are unmistakable against Google's 7-to-7 figures.
        var hours: [Wire.Hour] = []
        for h in 0..<24 {
            let utcHour = (h + 7) % 24
            let utcDay = h + 7 >= 24 ? 10 : 9
            hours.append(Wire.Hour(
                interval: interval(String(format: "2026-09-%02dT%02d:00:00Z", utcDay, utcHour)),
                weatherCondition: condition("CLEAR"),
                temperature: celsius(Double(10 + h)),
                feelsLikeTemperature: celsius(Double(9 + h)),
                precipitation: precipitation(percent: Double(h * 4), qpf: 0.5, snow: h == 12 ? 10 : nil),
                // A steady westerly by day, calm otherwise.
                wind: h < 12 ? wind(Double(h), from: 270, gust: Double(h * 2)) : wind(0),
                visibility: kilometres(16)
            ))
        }
        var day = Fixture.days[1]
        day.displayDate = Wire.DisplayDate(year: 2026, month: 9, day: 9)
        day.maxTemperature = celsius(99)
        day.minTemperature = celsius(-99)

        let (response, _) = Fixture.build(hours: hours, days: [day], history: [])
        let daily = response.daily
        #expect(response.hourly.time.first == "2026-09-09T00:00")
        #expect(response.hourly.time.last == "2026-09-09T23:00")
        #expect(daily.time == ["2026-09-09"])
        #expect(daily.tempMax == [33])
        #expect(daily.tempMin == [10])
        #expect(daily.apparentMax == [32])
        #expect(daily.apparentMin == [9])
        #expect(approx(daily.precipitationSum, [12.0]))
        #expect(daily.precipitationProbabilityMax == [92])
        #expect(daily.windSpeedMax == [11])
        #expect(daily.windGustMax == [22])
        #expect(approx(daily.windDirectionDominant, [270]))
        // 10 mm of snow water in one hour is 7 cm of snow.
        #expect(approx(daily.snowfallSum ?? [], [7.0]))
        // The condition still comes from Google's halves: SNOW by day, LIGHT_SNOW by night.
        #expect(daily.weatherCode == [73])

        // Drop the morning and Google's own figures stand in for the day.
        let (partial, _) = Fixture.build(hours: Array(hours.dropFirst(6)), days: [day], history: [])
        #expect(partial.daily.tempMax == [99])
        #expect(partial.daily.tempMin == [-99])
    }

    @Test("In a half-hour zone every hour is filed under the local hour holding its midpoint")
    func halfHourZoneHours() {
        let (response, _) = Fixture.build(timeZoneID: "Asia/Kolkata")
        // 20:00Z, 21:00Z and 22:00Z are 01:30, 02:30 and 03:30 in Kolkata.
        #expect(response.hourly.time == ["2026-09-09T02:00", "2026-09-09T03:00", "2026-09-09T04:00"])
        #expect(response.hourly.temperature == [21, 22, 23])
        // The current block keeps its true minutes, as Open-Meteo's does.
        #expect(response.current.time == "2026-09-09T02:30")
    }

    @Test("On a fall-back night the two 01:00 hours collapse to the later one, keeping the arrays aligned")
    func fallBackNight() {
        // 1 November 2026, Pacific: 08:00Z is 01:00 PDT, 09:00Z is 01:00 PST.
        var first = Fixture.forecastHours[1]
        first.interval = interval("2026-11-01T07:00:00Z")
        first.temperature = celsius(5)
        var pdt = Fixture.forecastHours[1]
        pdt.interval = interval("2026-11-01T08:00:00Z")
        pdt.temperature = celsius(4)
        var pst = Fixture.forecastHours[1]
        pst.interval = interval("2026-11-01T09:00:00Z")
        pst.temperature = celsius(3)
        var after = Fixture.forecastHours[1]
        after.interval = interval("2026-11-01T10:00:00Z")
        after.temperature = celsius(2)

        let (response, tz) = Fixture.build(hours: [first, pdt, pst, after], days: [], history: [])
        #expect(response.hourly.time == ["2026-11-01T00:00", "2026-11-01T01:00", "2026-11-01T02:00"])
        #expect(response.hourly.temperature == [5, 3, 2])
        #expect(response.hourly.humidity.count == 3)
        // The surviving 01:00 is the instant LocalTimeParser reads back.
        let parser = LocalTimeParser(timezone: tz)
        #expect(parser.date(from: "2026-11-01T01:00") == WeatherNextService.LocalClock(timeZone: tz).date("2026-11-01T09:00:00Z"))

        // Spring forward loses an hour and nothing is dropped or doubled.
        var before = Fixture.forecastHours[1]
        before.interval = interval("2026-03-08T09:00:00Z")
        var leap = Fixture.forecastHours[1]
        leap.interval = interval("2026-03-08T10:00:00Z")
        let (spring, _) = Fixture.build(hours: [before, leap], days: [], history: [])
        #expect(spring.hourly.time == ["2026-03-08T01:00", "2026-03-08T03:00"])
    }

    @Test("An hour without a dew point or visibility object leaves that column absent rather than zero")
    func unsetDewPointAndVisibility() {
        var bare = Fixture.forecastHours[0]
        bare.dewPoint = nil
        let (noDew, _) = Fixture.build(hours: [Fixture.forecastHours[1], bare], days: [])
        #expect(noDew.hourly.dewPoint == nil)
        #expect(noDew.hourly.visibility == [16000, 10000, 16000])

        var blind = Fixture.forecastHours[0]
        blind.visibility = nil
        let (noVis, _) = Fixture.build(hours: [Fixture.forecastHours[1], blind], days: [])
        #expect(noVis.hourly.visibility == nil)
        #expect(noVis.hourly.dewPoint == [12, 13, 14])

        // An object present with its `degrees` dropped is still 0 °C.
        var freezing = Fixture.forecastHours[0]
        freezing.dewPoint = Wire.Temperature(unit: "CELSIUS")
        let (zero, _) = Fixture.build(hours: [Fixture.forecastHours[1], freezing], days: [])
        #expect(zero.hourly.dewPoint == [12, 13, 0])
    }

    @Test("The zone falls back from the pages to current conditions to the place, skipping unknown ids")
    func timeZoneFallbacks() {
        let (fromPages, pagesZone) = Fixture.build(timeZoneID: "Asia/Kolkata")
        #expect(pagesZone.identifier == "Asia/Kolkata")
        #expect(fromPages.timezone == "Asia/Kolkata")
        #expect(fromPages.current.time == "2026-09-09T02:30")
        #expect(fromPages.hourly.time.first == "2026-09-09T02:00")

        // The place says London but the current block says Los Angeles: the
        // current block outranks the place.
        let london = Place(name: "London", admin1: nil, country: "United Kingdom", countryCode: "GB",
                           latitude: 51.5, longitude: -0.12, timezone: "Europe/London")
        let (_, currentZone) = Fixture.build(timeZoneID: nil, place: london)
        #expect(currentZone.identifier == "America/Los_Angeles")

        let (_, unknownSkipped) = Fixture.build(timeZoneID: "Mars/Olympus_Mons")
        #expect(unknownSkipped.identifier == "America/Los_Angeles")

        var current = Fixture.current
        current.timeZone = nil
        let (fromPlace, placeZone) = Fixture.build(timeZoneID: nil, current: current, place: london)
        #expect(placeZone.identifier == "Europe/London")
        // British Summer Time in September.
        #expect(fromPlace.current.time == "2026-09-08T22:00")
    }
}

// MARK: - Fog and the gap-fill slots

/// Google's condition enum has no fog, so `fogCode` reads it off the hour's
/// own visibility and dew point. This section pins that rule, checks the
/// adapter runs every code through it in wire units, and checks the total
/// cloud cover column the gap fill later scales Open-Meteo's layers against.
struct WeatherNextFogTests {
    /// The rule with a foggy default: partly cloudy, 500 m, 10 °C over a
    /// 9.5 °C dew point. Each test moves one input off it.
    private func fog(_ code: Int = 2, visibility: Double? = 500,
                     temperature: Double? = 10, dewPoint: Double? = 9.5) -> Int {
        WeatherNextService.fogCode(mappedCode: code, visibilityMetres: visibility,
                                   temperatureC: temperature, dewPointC: dewPoint)
    }

    @Test("Under 1 km with the air within 1 °C of saturation is fog, rime fog at or below freezing")
    func fogRule() {
        #expect(fog(temperature: 10, dewPoint: 9.5) == 45)
        #expect(fog(temperature: 0, dewPoint: -0.5) == 48)
        #expect(fog(temperature: -2, dewPoint: -2) == 48)
        // The freezing line is inclusive; a hair above it is ordinary fog.
        #expect(fog(temperature: 0.1, dewPoint: 0) == 45)
    }

    @Test("The dew point spread may be exactly 1 °C, not more")
    func spread() {
        #expect(fog(temperature: 10, dewPoint: 9) == 45)
        #expect(fog(temperature: 10, dewPoint: 8.5) == 2)
        // A dew point above the temperature is supersaturated air: still fog.
        #expect(fog(temperature: 10, dewPoint: 10.4) == 45)
    }

    @Test("Visibility of 1 km or more, or none reported, leaves the sky code alone")
    func visibilityGate() {
        #expect(fog(visibility: 1500) == 2)
        #expect(fog(visibility: 1000) == 2)
        #expect(fog(visibility: 999) == 45)
        #expect(fog(visibility: nil) == 2)
    }

    @Test("Only sky codes turn into fog; rain, snow and thunder keep their own")
    func onlySkyCodes() {
        for code in 0...3 { #expect(fog(code) == 45) }
        #expect(fog(61) == 61)
        #expect(fog(71) == 71)
        #expect(fog(80) == 80)
        #expect(fog(95) == 95)
        // An already-foggy code is not re-derived either way.
        #expect(fog(45, temperature: 0) == 45)
    }

    @Test("Without a temperature or dew point there is no fog")
    func missingAir() {
        #expect(fog(temperature: nil) == 2)
        #expect(fog(dewPoint: nil) == 2)
        #expect(fog(temperature: nil, dewPoint: nil) == 2)
    }

    /// A foggy dawn as forecast/hours sends it: cloudy by type, 400 m of
    /// visibility, half a degree of dew point spread, solid cover.
    private static let foggyHourJSON = """
    {
      "interval": {"startTime": "2026-09-09T13:00:00Z", "endTime": "2026-09-09T14:00:00Z"},
      "weatherCondition": {"type": "CLOUDY"},
      "temperature": {"degrees": 12, "unit": "CELSIUS"},
      "dewPoint": {"degrees": 11.5, "unit": "CELSIUS"},
      "visibility": {"distance": 0.4, "unit": "KILOMETERS"},
      "relativeHumidity": 97,
      "cloudCover": 100
    }
    """

    private func foggyHour() throws -> Wire.Hour {
        try JSONDecoder().decode(Wire.Hour.self, from: Data(Self.foggyHourJSON.utf8))
    }

    @Test("A cloudy hour with 400 m of visibility and saturated air comes out as fog, whatever the user's units")
    func adapterDerivesFog() throws {
        let foggy = try foggyHour()
        let (metric, _) = Fixture.build(hours: [foggy], days: [], history: [])
        #expect(metric.hourly.time == ["2026-09-09T06:00"])
        #expect(metric.hourly.weatherCode == [45])
        #expect(metric.hourly.cloudCover == [100])
        #expect(metric.hourly.visibility == [400])
        #expect(metric.hourly.dewPoint == [11.5])

        // The rule reads the wire's Celsius and metres before any conversion,
        // so an imperial preference changes the numbers but not the code.
        let (imperial, _) = Fixture.build(temperatureUnit: .fahrenheit, speedUnit: .mph, precipUnit: .inch,
                                          hours: [foggy], days: [], history: [])
        #expect(imperial.hourly.weatherCode == [45])
        #expect(approx(imperial.hourly.temperature, [53.6]))
        #expect(imperial.hourly.visibility == [400])
    }

    @Test("Current conditions go through the same rule")
    func currentDerivesFog() throws {
        let json = """
        {
          "currentTime": "2026-09-09T13:00:00Z",
          "timeZone": {"id": "America/Los_Angeles"},
          "weatherCondition": {"type": "CLOUDY"},
          "temperature": {"degrees": 12, "unit": "CELSIUS"},
          "feelsLikeTemperature": {"degrees": 11, "unit": "CELSIUS"},
          "dewPoint": {"degrees": 11.5, "unit": "CELSIUS"},
          "relativeHumidity": 97,
          "visibility": {"distance": 0.4, "unit": "KILOMETERS"},
          "cloudCover": 100
        }
        """
        let current = try JSONDecoder().decode(Wire.CurrentConditions.self, from: Data(json.utf8))
        let (response, _) = Fixture.build(current: current, hours: [], days: [], history: [])
        #expect(response.current.time == "2026-09-09T06:00")
        #expect(response.current.weatherCode == 45)
        #expect(response.current.cloudCover == 100)
        #expect(response.current.temperature == 12)
        #expect(response.current.apparentTemperature == 11)

        // The fixture's own current block (partly cloudy, no visibility) is untouched.
        #expect(Fixture.build().0.current.weatherCode == 2)
    }

    @Test("Freezing fog survives proto3 dropping the 0 °C temperature, and a Fahrenheit and miles wire is read in its own units")
    func fogWireUnits() throws {
        // Exactly 0 °C: `degrees` is omitted and must read as freezing, not unset.
        let freezing = try JSONDecoder().decode(Wire.Hour.self, from: Data("""
        {
          "interval": {"startTime": "2026-09-09T13:00:00Z", "endTime": "2026-09-09T14:00:00Z"},
          "weatherCondition": {"type": "MOSTLY_CLOUDY"},
          "temperature": {"unit": "CELSIUS"},
          "dewPoint": {"degrees": -0.5, "unit": "CELSIUS"},
          "visibility": {"distance": 0.2, "unit": "KILOMETERS"},
          "cloudCover": 90
        }
        """.utf8))
        let (rime, _) = Fixture.build(hours: [freezing], days: [], history: [])
        #expect(rime.hourly.weatherCode == [48])
        #expect(rime.hourly.temperature == [0])
        #expect(rime.hourly.cloudCover == [90])

        // 53.6 °F, 52.7 °F and a quarter mile are 12 °C, 11.5 °C and 402 m.
        let imperialWire = try JSONDecoder().decode(Wire.Hour.self, from: Data("""
        {
          "interval": {"startTime": "2026-09-09T13:00:00Z", "endTime": "2026-09-09T14:00:00Z"},
          "weatherCondition": {"type": "CLOUDY"},
          "temperature": {"degrees": 53.6, "unit": "FAHRENHEIT"},
          "dewPoint": {"degrees": 52.7, "unit": "FAHRENHEIT"},
          "visibility": {"distance": 0.25, "unit": "MILES"},
          "cloudCover": 100
        }
        """.utf8))
        let (fromMiles, _) = Fixture.build(hours: [imperialWire], days: [], history: [])
        #expect(fromMiles.hourly.weatherCode == [45])
        #expect(approx(fromMiles.hourly.temperature, [12]))
        #expect(approx(fromMiles.hourly.visibility ?? [], [402.336], within: 0.001))
    }

    @Test("Rain in the fog stays rain, clearer air stays a sky code, and a missing visibility object cannot make fog")
    func fogDoesNotOverrideWeather() throws {
        var rainy = try foggyHour()
        rainy.weatherCondition = condition("LIGHT_RAIN")
        var clearer = try foggyHour()
        clearer.interval = interval("2026-09-09T14:00:00Z")
        clearer.visibility = kilometres(10)
        var blind = try foggyHour()
        blind.interval = interval("2026-09-09T15:00:00Z")
        blind.visibility = nil

        let (response, _) = Fixture.build(hours: [rainy, clearer, blind], days: [], history: [])
        #expect(response.hourly.time == ["2026-09-09T06:00", "2026-09-09T07:00", "2026-09-09T08:00"])
        #expect(response.hourly.weatherCode == [61, 3, 3])
        #expect(response.hourly.visibility == nil)
    }

    @Test("The total cloud cover column carries Google's per-hour total, zero where proto3 dropped it")
    func cloudCoverColumn() {
        let (response, _) = Fixture.build()
        // History hour, then the two forecast hours in instant order.
        #expect(response.hourly.cloudCover == [90, 80, 5])
        #expect(response.hourly.cloudCover?.count == response.hourly.time.count)

        var dropped = Fixture.forecastHours[0]
        dropped.cloudCover = nil
        let (clear, _) = Fixture.build(hours: [dropped], days: [], history: [])
        #expect(clear.hourly.cloudCover == [0])
        // The slots the gap fill completes are left empty by the adapter.
        #expect(clear.hourly.cloudCoverLow == nil)
        #expect(clear.hourly.cloudCoverMid == nil)
        #expect(clear.hourly.cloudCoverHigh == nil)
        #expect(clear.elevation == nil)
        #expect(clear.minutely15 == nil)
    }
}

// MARK: - Source and key

struct WeatherNextSourceTests {
    @Test("The Google attribution phrase survives verbatim")
    func attribution() {
        #expect(ForecastSource.weatherNext.attributionLine.contains("Includes weather data from Google"))
        #expect(ForecastSource.weatherNext.sourceName == "Google Weather")
        #expect(ForecastSource(rawValue: "weatherNext") == .weatherNext)
        #expect(ForecastSource.allCases.count == 2)
    }

    @Test("A pasted key is trimmed, and an unresolved build setting is not a key")
    func keyOverride() {
        let defaults = UserDefaults.standard
        let name = WeatherNextKey.overrideDefaultsKey
        let previous = defaults.string(forKey: name)
        defer {
            if let previous { defaults.set(previous, forKey: name) } else { defaults.removeObject(forKey: name) }
        }

        defaults.set("  AIza-test-key \n", forKey: name)
        #expect(WeatherNextKey.value == "AIza-test-key")
        #expect(WeatherNextKey.isConfigured)

        // Neither of these may be used; whether anything remains depends on
        // whether the test host's plist carries a built-in key.
        defaults.set("$(GOOGLE_WEATHER_API_KEY)", forKey: name)
        #expect(WeatherNextKey.value != "$(GOOGLE_WEATHER_API_KEY)")
        #expect(WeatherNextKey.isConfigured == WeatherNextKey.isBuiltIn)

        defaults.set("   ", forKey: name)
        #expect(WeatherNextKey.value != "   ")
        #expect(WeatherNextKey.isConfigured == WeatherNextKey.isBuiltIn)
    }
}

// MARK: - Failure reasons

/// A failed WeatherNext call must not cost the user the forecast: the service
/// falls back to Open-Meteo for that load and shows `failureReason`'s sentence
/// on the page and beside the key in Settings. So the sentence has to name the
/// one fact the user can act on (the key, the quota, the unenabled API) in
/// Google's own words, read as a finished sentence, and never carry the key.
/// No network: the function is fed canned statuses, bodies and transport errors.
struct WeatherNextFailureTests {
    private let hours = "forecast/hours:lookup"

    private func reason(status: Int?, body: Data? = nil, transportError: Error? = nil) -> String {
        WeatherNextService.failureReason(endpoint: hours, status: status, body: body,
                                         transportError: transportError)
    }

    /// Google's envelopes as the API sends them, `details` included where the
    /// real answer carries it, so the decoder is proven to ignore what it does
    /// not model.
    private static let permissionDenied = Data("""
    {"error": {"code": 403, "message": "Weather API has not been used in project 123 before or it is disabled.", "status": "PERMISSION_DENIED"}}
    """.utf8)

    private static let invalidKey = Data("""
    {
      "error": {
        "code": 400,
        "message": "API key not valid. Please pass a valid API key.",
        "status": "INVALID_ARGUMENT",
        "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "API_KEY_INVALID", "domain": "googleapis.com"}]
      }
    }
    """.utf8)

    private static let badLatitude = Data("""
    {"error": {"code": 400, "message": "Invalid value at 'location.latitude' (TYPE_DOUBLE), \\"north\\"", "status": "INVALID_ARGUMENT"}}
    """.utf8)

    private static let quotaExceeded = Data("""
    {"error": {"code": 429, "message": "Quota exceeded for quota metric 'Requests' and limit 'Requests per minute' of service 'weather.googleapis.com' for consumer 'project_number:123'.", "status": "RESOURCE_EXHAUSTED"}}
    """.utf8)

    @Test("A 403 says Google refused and quotes Google's message, without the key")
    func permissionDenied() {
        let text = reason(status: 403, body: Self.permissionDenied)
        #expect(text.contains("refused"))
        #expect(text.contains("Weather API has not been used in project 123 before or it is disabled."))
        #expect(text.contains("PERMISSION_DENIED"))
        #expect(!text.contains("key="))
        #expect(text.hasSuffix("."))
    }

    @Test("A 400 for an invalid key names the key; a 400 for a bad argument does not")
    func invalidKey() {
        let key = reason(status: 400, body: Self.invalidKey)
        #expect(key.localizedCaseInsensitiveContains("api key"))
        #expect(key.contains("rejected"))
        #expect(key.contains("API key not valid."))

        // The same status and INVALID_ARGUMENT for a malformed coordinate must
        // not send the user off to check a key that is fine.
        let latitude = reason(status: 400, body: Self.badLatitude)
        #expect(!latitude.contains("rejected the API key"))
        #expect(latitude.contains("400"))
        #expect(latitude.contains("Invalid value at 'location.latitude'"))
    }

    @Test("A 429 mentions the quota, with or without Google's body")
    func quota() {
        let detailed = reason(status: 429, body: Self.quotaExceeded)
        #expect(detailed.localizedCaseInsensitiveContains("quota"))
        #expect(detailed.contains("RESOURCE_EXHAUSTED"))
        #expect(detailed.contains("Requests per minute"))

        let bare = reason(status: 429)
        #expect(bare.localizedCaseInsensitiveContains("quota"))
        #expect(bare.contains("429"))
    }

    @Test("A 404 names the endpoint path, never a URL")
    func notFound() {
        let text = reason(status: 404)
        #expect(text.contains("forecast/hours:lookup"))
        #expect(text.contains("no data"))
        #expect(!text.contains("https://"))
        #expect(!text.contains("key="))
    }

    @Test("A 5xx carries its status so the log and the user agree on what Google said",
          arguments: [500, 502, 503, 504])
    func serverError(status: Int) {
        let text = reason(status: status)
        #expect(text.contains(String(status)))
        #expect(text.contains("Google"))
        #expect(text.hasSuffix("."))
    }

    @Test("A transport error is described in the user's terms, not URLError's", arguments: [
        (URLError.Code.notConnectedToInternet, "offline"),
        (URLError.Code.networkConnectionLost, "offline"),
        (URLError.Code.timedOut, "too long"),
        (URLError.Code.cannotFindHost, "could not be reached"),
        (URLError.Code.dnsLookupFailed, "could not be reached")
    ])
    func transportError(code: URLError.Code, phrase: String) {
        let text = reason(status: nil, transportError: URLError(code))
        #expect(text.contains(phrase))
        #expect(text.contains("Google"))
        #expect(!text.contains("NSURLErrorDomain"))
    }

    @Test("An unfamiliar transport error keeps its own description inside the sentence")
    func otherTransportError() {
        let unplugged = NSError(domain: "Test", code: 7,
                                userInfo: [NSLocalizedDescriptionKey: "The cable fell out"])
        #expect(reason(status: nil, transportError: unplugged) == "Google could not be reached (The cable fell out).")
    }

    @Test("A body that is not Google's JSON falls back to the HTTP status and never leaks the body")
    func notJSON() {
        let html = Data("<html><body><h1>403 Forbidden</h1></body></html>".utf8)
        let forbidden = reason(status: 403, body: html)
        #expect(forbidden.contains("refused"))
        #expect(forbidden.contains("HTTP 403"))
        #expect(!forbidden.contains("<"))

        // An unmapped status with an unreadable body still says which call and what status.
        let teapot = reason(status: 418, body: Data("I'm a teapot".utf8))
        #expect(teapot.contains("418"))
        #expect(teapot.contains("forecast/hours:lookup"))
        #expect(!teapot.contains("teapot"))

        #expect(reason(status: 403, body: Data()).contains("HTTP 403"))
    }

    @Test("No status, body or transport error is an unreadable answer naming the call")
    func nilEverything() {
        #expect(reason(status: nil) == "Google's answer could not be read (forecast/hours:lookup).")
    }

    @Test("A key echoed in Google's message is blanked before the reason reaches the screen or log")
    func redactsKey() {
        let echo = Data("""
        {"error": {"code": 403, "message": "Requests to https://weather.googleapis.com/v1/forecast/hours:lookup?key=AIzaSyFAKE1234567890&location.latitude=34 are blocked by the key's referrer restrictions", "status": "PERMISSION_DENIED"}}
        """.utf8)
        let text = reason(status: 403, body: echo)
        #expect(!text.contains("AIzaSyFAKE1234567890"))
        #expect(text.contains("key=redacted"))
        #expect(text.contains("referrer restrictions."))
    }

    @Test("A long Google message is cut at a word, not mid-word, and still ends the sentence")
    func longMessage() {
        let words = Array(repeating: "alpha", count: 80).joined(separator: " ")
        let body = Data("""
        {"error": {"code": 403, "message": "\(words)", "status": "PERMISSION_DENIED"}}
        """.utf8)
        let text = reason(status: 403, body: body)
        #expect(text.hasSuffix("alpha..."))
        #expect(text.count < 260)
        #expect(!text.contains("alph..."))
    }

    @Test("Every reason is one finished sentence, because the page shows it as-is")
    func reasonsAreSentences() {
        let unplugged = NSError(domain: "Test", code: 7,
                                userInfo: [NSLocalizedDescriptionKey: "The cable fell out"])
        let reasons = [
            reason(status: 403, body: Self.permissionDenied),
            reason(status: 400, body: Self.invalidKey),
            reason(status: 400, body: Self.badLatitude),
            reason(status: 429, body: Self.quotaExceeded),
            reason(status: 429),
            reason(status: 404),
            reason(status: 503),
            reason(status: 418, body: Data("<html>".utf8)),
            reason(status: nil),
            reason(status: nil, transportError: URLError(.timedOut)),
            reason(status: nil, transportError: unplugged)
        ]
        for text in reasons {
            #expect(text.hasSuffix("."), "\(text)")
            #expect(!text.contains("\n"), "\(text)")
            #expect(!text.contains("key="), "\(text)")
            #expect(text.first?.isUppercase == true, "\(text)")
        }
    }

    @Test("The error carries the reason verbatim, so the fallback notice is Google's sentence")
    func errorDescriptionIsTheReason() {
        let error = WeatherError.weatherNextFailed(reason: "x")
        #expect(error.errorDescription == "x")
        // WeatherService reads it through LocalizedError when it builds the notice.
        #expect(((error as Error) as? LocalizedError)?.errorDescription == "x")
        #expect(error.localizedDescription == "x")
    }
}

// MARK: - Source notice on the bundle

/// The fallback bundle is Classic Haze wearing a note about why. The note has
/// to survive the enrichments applied after the forecast lands and the trip
/// through the cache, and a cache entry written before the field existed has
/// to decode without it.
struct WeatherNextSourceNoticeTests {
    /// The smallest bundle the model accepts, stamped as a fallback.
    private func fallbackBundle(notice: String?) -> WeatherBundle {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let hour = HourPoint(date: now, temperature: 22, apparentTemperature: 23, code: 2, isDay: true,
                             precipitationProbability: 0, precipitation: 0, windSpeed: 12,
                             windDirection: 270, humidity: 55, uvIndex: 3)
        let day = DayForecast(date: now, code: 2, tempMax: 25, tempMin: 15, apparentMax: 26, apparentMin: 14,
                              sunrise: nil, sunset: nil, uvIndexMax: 5, precipitationSum: 0,
                              precipitationProbabilityMax: 0, windSpeedMax: 20, windGustMax: 30,
                              windDirectionDominant: 270)
        var bundle = WeatherBundle(
            place: Fixture.place,
            timezone: losAngeles,
            current: CurrentWeather(date: now, temperature: 22, apparentTemperature: 23, code: 2,
                                    isDay: true, humidity: 55, precipitation: 0, cloudCover: 40,
                                    pressure: 1013.2, windSpeed: 12, windGust: 20, windDirection: 270,
                                    uvIndex: 3, visibility: 16000, dewPoint: 12),
            hourly: [hour], daily: [day], airQuality: nil, fetchedAt: now)
        bundle.source = .classic
        bundle.sourceNotice = notice
        return bundle
    }

    private let notice = "Google refused the request (PERMISSION_DENIED): Weather API has not been used in project 123 before or it is disabled."

    @Test("applying keeps the notice and the source while it swaps in the observed code")
    func applyingCarriesNotice() {
        let enriched = fallbackBundle(notice: notice).applying(airQuality: nil, observation: nil, observedCode: 61, alerts: nil,
                                                        temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(enriched.sourceNotice == notice)
        #expect(enriched.source == .classic)
        #expect(enriched.current.code == 61)
        #expect(enriched.attributionLine == ForecastSource.classic.attributionLine)

        // A page that is the source the user asked for stays unannotated.
        let plain = fallbackBundle(notice: nil).applying(airQuality: nil, observation: nil, observedCode: nil, alerts: nil,
                                                 temperatureUnit: .fahrenheit, speedUnit: .mph)
        #expect(plain.sourceNotice == nil)
    }

    @Test("The notice survives the cache, and a pre-notice cache entry decodes without one")
    func noticeRoundTrips() throws {
        let data = try JSONEncoder().encode(fallbackBundle(notice: notice))
        let decoded = try JSONDecoder().decode(WeatherBundle.self, from: data)
        #expect(decoded.sourceNotice == notice)
        #expect(decoded.source == .classic)

        // Strip the keys a cache written before this feature never had.
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sourceNotice")
        object.removeValue(forKey: "source")
        let old = try JSONDecoder().decode(WeatherBundle.self,
                                           from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.sourceNotice == nil)
        #expect(old.source == nil)
        #expect(old.attributionLine == ForecastSource.classic.attributionLine)
    }
}

// MARK: - The footer notice

/// The notice is composed once the gap fill is known to have landed or not,
/// because the fill fails on its own (Open-Meteo rate limited, offline) and a
/// page with no hourly series must never say Open-Meteo supplied one. Pure
/// text in, pure text out; the views print it verbatim.
struct WeatherNextNoticeTests {
    private let reason = "Google's daily quota for hourly forecasts is used up until midnight Pacific (about 6 h)."

    @Test("With every hour Google's, there is nothing to say")
    func wholeSeriesIsSilent() {
        #expect(WeatherNextService.Outcome.notice(googleHours: 240, hoursFailure: nil, fillApplied: true) == nil)
        #expect(WeatherNextService.Outcome.notice(googleHours: 240, hoursFailure: nil, fillApplied: false) == nil)
    }

    @Test("No Google hours and a fill: Open-Meteo is credited, then the reason")
    func emptyWithFill() {
        #expect(WeatherNextService.Outcome.notice(googleHours: 0, hoursFailure: reason, fillApplied: true)
                == "Hourly detail is from Open-Meteo for now. \(reason)")
        #expect(WeatherNextService.Outcome.notice(googleHours: 0, hoursFailure: nil, fillApplied: true)
                == "Hourly detail is from Open-Meteo for now. Google returned no hourly forecast.")
    }

    @Test("No Google hours and no fill: the page says it has no hourly detail, never that Open-Meteo supplied it")
    func emptyWithoutFill() throws {
        let notice = try #require(WeatherNextService.Outcome.notice(googleHours: 0, hoursFailure: reason, fillApplied: false))
        #expect(notice.hasPrefix("There is no hourly detail right now"))
        #expect(notice.hasSuffix(reason))
        #expect(!notice.contains("is from Open-Meteo"))
    }

    @Test("A chain cut short names the seam, with or without the fill")
    func cutShort() throws {
        #expect(WeatherNextService.Outcome.notice(googleHours: 48, hoursFailure: reason, fillApplied: true)
                == "Hourly detail past the first 48 hours is from Open-Meteo for now. \(reason)")
        let dry = try #require(WeatherNextService.Outcome.notice(googleHours: 48, hoursFailure: reason, fillApplied: false))
        #expect(dry.hasPrefix("Hourly detail stops after the first 48 hours"))
        #expect(dry.hasSuffix(reason))
        #expect(!dry.contains("is from Open-Meteo"))
    }

    @Test("Every notice is finished sentences, because the footer prints it as is")
    func sentences() {
        let all = [(0, true), (0, false), (48, true), (48, false)].compactMap {
            WeatherNextService.Outcome.notice(googleHours: $0.0, hoursFailure: reason, fillApplied: $0.1)
        }
        #expect(all.count == 4)
        for text in all {
            #expect(text.hasSuffix("."), "\(text)")
            #expect(text.first?.isUppercase == true, "\(text)")
            #expect(!text.contains("\u{2014}"), "\(text)")
        }
    }
}

// MARK: - Zero hours

/// Every hourly column's length, the optional columns included when present,
/// so "every column is the same length" is a single assertion.
private func hourlyCounts(_ h: ForecastResponse.Hourly) -> Set<Int> {
    var counts = [h.time.count, h.temperature.count, h.humidity.count, h.apparentTemperature.count,
                  h.precipitationProbability.count, h.precipitation.count, h.weatherCode.count,
                  h.windSpeed.count, h.windDirection.count, h.isDay.count]
    for column in [h.cloudCover, h.dewPoint, h.visibility] {
        if let column { counts.append(column.count) }
    }
    for column in [h.cloudCoverLow, h.cloudCoverMid, h.cloudCoverHigh] {
        if let column { counts.append(column.count) }
    }
    return Set(counts)
}

/// The hourly quota is the one that runs out, and when it does Google still
/// answers current and days. The adapter then has to build a page with no
/// hours at all, every hourly column empty and aligned and daily from
/// Google's own halves, which the gap fill turns into a full Open-Meteo
/// series. These tests walk that path end to end.
struct WeatherNextZeroHoursTests {
    @Test("With no hours at all every hourly column is empty and aligned, current is built and daily comes from Google's halves")
    func zeroHours() {
        let (response, tz) = Fixture.build(hours: [], history: [])
        #expect(tz.identifier == "America/Los_Angeles")

        let hourly = response.hourly
        #expect(hourly.time.isEmpty)
        #expect(hourlyCounts(hourly) == [0])
        // Dew point and visibility are empty columns, not absent ones: there
        // is nothing unknown about zero hours, and the gap fill extends a
        // column that exists.
        #expect(hourly.dewPoint == [])
        #expect(hourly.visibility == [])
        #expect(hourly.cloudCover == [])
        #expect(hourly.cloudCoverLow == nil)
        #expect(hourly.cloudCoverMid == nil)
        #expect(hourly.cloudCoverHigh == nil)

        let current = response.current
        #expect(current.time == "2026-09-08T14:00")
        #expect(current.temperature == 22)
        #expect(current.apparentTemperature == 23)
        #expect(current.weatherCode == 2)
        #expect(current.cloudCover == 40)

        // No calendar day has 23 hours, so every row is Google's 7-to-7 figures.
        let daily = response.daily
        #expect(daily.time == ["2026-09-08", "2026-09-09"])
        #expect(daily.weatherCode == [61, 73])
        #expect(daily.tempMax == [25, 2])
        #expect(daily.tempMin == [15, 0])
        #expect(daily.apparentMax == [26, 2])
        #expect(daily.apparentMin == [14, 0])
        #expect(daily.precipitationSum == [4.0, 10.0])
        #expect(daily.precipitationProbabilityMax == [60, 80])
        #expect(daily.windSpeedMax == [20, 30])
        #expect(daily.snowfallSum == [0, 35.0])
        #expect(daily.sunrise == ["2026-09-08T06:35", "2026-09-09T06:36"])
    }

    @Test("Zero hours in an imperial preference still converts current and daily")
    func zeroHoursImperial() {
        let (response, _) = Fixture.build(temperatureUnit: .fahrenheit, speedUnit: .mph, precipUnit: .inch,
                                          hours: [], history: [])
        #expect(hourlyCounts(response.hourly) == [0])
        #expect(approx(response.current.temperature, 71.6))
        #expect(approx(response.daily.tempMax, [77, 35.6]))
        #expect(approx(response.daily.precipitationSum, [0.1575, 0.3937], within: 0.0001))
    }

    /// Open-Meteo's answer for the same afternoon with every classic column,
    /// the hours deliberately shuffled, visibility in feet as it arrives
    /// under an imperial precipitation unit. 16:00 is after dusk so the
    /// is_day column carries both values.
    private static let fullColumnFill = """
    {
      "timezone": "America/Los_Angeles",
      "utc_offset_seconds": -25200,
      "elevation": 2058.0,
      "hourly": {
        "time": ["2026-09-08T14:00", "2026-09-08T12:00", "2026-09-08T16:00", "2026-09-08T13:00", "2026-09-08T15:00"],
        "temperature_2m": [22, 20, 24, 21, 23],
        "relative_humidity_2m": [55, 60, 45, 58, 50],
        "apparent_temperature": [23, 20.5, 24, 21.5, 23.5],
        "precipitation_probability": [20, 5, 0, 10, 15],
        "precipitation": [1.0, 0, 0, 0.5, 0.2],
        "weather_code": [61, 1, 3, 2, 0],
        "wind_speed_10m": [12, 8, 15, 10, 14],
        "wind_direction_10m": [270, 260, 280, 250, 275],
        "is_day": [1, 1, 0, 1, 1],
        "dew_point_2m": [13, 11, 14, 11.5, 12.5],
        "visibility": [32808.4, 50000, 10000, 25000, 20000],
        "cloud_cover": [80, 40, 10, 60, 5],
        "cloud_cover_low": [10, 5, 0, 20, 2],
        "cloud_cover_mid": [30, 15, 5, 25, 1],
        "cloud_cover_high": [70, 30, 8, 40, 3]
      }
    }
    """

    @Test("The gap fill then supplies the whole series: sorted, every column one length, visibility in metres, codes and is_day copied")
    func gapFillSuppliesTheSeries() throws {
        let (built, tz) = Fixture.build(hours: [], history: [])
        var response = built
        var fill = try JSONDecoder().decode(OpenMeteoGapFill.self, from: Data(Self.fullColumnFill.utf8))
        fill.visibilityInFeet = true
        response.applyGapFill(fill, timezone: tz)
        let hourly = response.hourly

        #expect(hourly.time == ["2026-09-08T12:00", "2026-09-08T13:00", "2026-09-08T14:00",
                                "2026-09-08T15:00", "2026-09-08T16:00"])
        #expect(hourlyCounts(hourly) == [5])
        #expect(hourly.temperature == [20, 21, 22, 23, 24])
        #expect(hourly.humidity == [60, 58, 55, 50, 45])
        #expect(hourly.apparentTemperature == [20.5, 21.5, 23, 23.5, 24])
        #expect(hourly.precipitationProbability == [5, 10, 20, 15, 0])
        #expect(hourly.precipitation == [0, 0.5, 1.0, 0.2, 0])
        #expect(hourly.weatherCode == [1, 2, 61, 0, 3])
        #expect(hourly.windSpeed == [8, 10, 12, 14, 15])
        #expect(hourly.windDirection == [260, 250, 270, 275, 280])
        #expect(hourly.isDay == [1, 1, 1, 1, 0])
        #expect(hourly.dewPoint == [11, 11.5, 13, 12.5, 14])
        // 50000, 25000, 32808.4, 20000 and 10000 feet, in metres.
        #expect(approx(hourly.visibility ?? [], [15240, 7620, 10000, 6096, 3048]))
        #expect(hourly.cloudCover == [40, 60, 80, 5, 10])
        // No Google total exists for an appended hour, so the layers are
        // Open-Meteo's own, unscaled.
        #expect(hourly.cloudCoverLow == [5, 20, 10, 2, 0])
        #expect(hourly.cloudCoverMid == [15, 25, 30, 1, 5])
        #expect(hourly.cloudCoverHigh == [30, 40, 70, 3, 8])

        #expect(response.elevation == 2058)
        // Five hours make no calendar day, and the fill carried no daily
        // block, so daily stays Google's.
        #expect(response.daily.time == ["2026-09-08", "2026-09-09"])
        #expect(response.daily.tempMax == [25, 2])
    }

    @Test("Without the feet flag the appended visibility is taken as metres")
    func visibilityMetresByDefault() throws {
        let (built, tz) = Fixture.build(hours: [], history: [])
        var response = built
        let fill = try JSONDecoder().decode(OpenMeteoGapFill.self, from: Data(Self.fullColumnFill.utf8))
        #expect(fill.visibilityInFeet == false)
        response.applyGapFill(fill, timezone: tz)
        #expect(response.hourly.visibility == [50000, 25000, 32808.4, 20000, 10000])
    }
}

// MARK: - The raw snapshot

/// One refresh costs a dozen quota-counted calls, so Google's decoded answers
/// are kept as they arrived and the adapter is re-run for a unit change or a
/// relaunch. That only works if the wire objects survive the trip to disk
/// exactly: the keys proto3 dropped stay dropped, the failures that explain a
/// short series stay attached, and the cache tells a corrupt file from a
/// missing one. The cache is pointed at a temporary directory throughout.
struct WeatherNextSnapshotTests {
    /// Whole seconds, because the cache writes ISO 8601 and that has none.
    private static let fetchedAt = Date(timeIntervalSince1970: 1_788_000_000)
    private static let losAngelesZone = Wire.TimeZoneInfo(id: "America/Los_Angeles")
    private static let hoursReason = "Google's daily quota for hourly forecasts is used up until midnight Pacific (about 6 h)."

    /// The fixture afternoon as two hours pages (the chain was cut short
    /// after them), a days page and a history page.
    private static func snapshot() -> WeatherNextService.RawSnapshot {
        WeatherNextService.RawSnapshot(
            fetchedAt: fetchedAt,
            current: Fixture.current,
            hoursPages: [
                Wire.HoursPage(forecastHours: [Fixture.forecastHours[1]], timeZone: losAngelesZone,
                               nextPageToken: "ChQKEgoQ"),
                Wire.HoursPage(forecastHours: [Fixture.forecastHours[0]], timeZone: losAngelesZone,
                               nextPageToken: nil)
            ],
            days: Wire.DaysPage(forecastDays: Fixture.days, timeZone: losAngelesZone, nextPageToken: nil),
            history: Wire.HistoryPage(historyHours: [Fixture.historyHour], timeZone: losAngelesZone,
                                      nextPageToken: nil),
            hoursFailure: hoursReason,
            historyFailure: nil)
    }

    /// The adapter's view of a snapshot, so two snapshots are compared through
    /// what the app would show rather than leaf by leaf.
    private static func adapt(_ snapshot: WeatherNextService.RawSnapshot) throws -> ForecastResponse {
        let current = try #require(snapshot.current)
        let days = try #require(snapshot.days?.forecastDays)
        return Fixture.build(current: current,
                             hours: snapshot.hoursPages.flatMap { $0.forecastHours ?? [] },
                             days: days,
                             history: snapshot.history?.historyHours ?? []).0
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WeatherNextRawCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("A snapshot round-trips through JSON and reads back as if Google had just answered")
    func codableRoundTrip() throws {
        let original = Self.snapshot()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeatherNextService.RawSnapshot.self, from: data)

        #expect(decoded.fetchedAt == original.fetchedAt)
        #expect(decoded.hoursPages.count == 2)
        #expect(decoded.hoursPages[0].nextPageToken == "ChQKEgoQ")
        #expect(decoded.hoursPages[1].nextPageToken == nil)
        #expect(decoded.hoursPages[0].timeZone?.id == "America/Los_Angeles")
        #expect(decoded.hoursFailure == Self.hoursReason)
        #expect(decoded.historyFailure == nil)
        #expect(decoded.current?.temperature?.degrees == 22)
        #expect(decoded.current?.wind?.gust?.value == 20)
        #expect(decoded.days?.forecastDays?.count == 2)
        #expect(decoded.history?.historyHours?.count == 1)

        let before = try Self.adapt(original)
        let after = try Self.adapt(decoded)
        #expect(after.hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(after.hourly.time == before.hourly.time)
        #expect(after.hourly.temperature == before.hourly.temperature)
        #expect(after.hourly.weatherCode == before.hourly.weatherCode)
        #expect(after.hourly.visibility == before.hourly.visibility)
        #expect(after.daily.tempMax == before.daily.tempMax)
        #expect(after.daily.snowfallSum == before.daily.snowfallSum)
        #expect(after.daily.sunrise == before.daily.sunrise)
        #expect(after.current.temperature == before.current.temperature)
        #expect(after.current.weatherCode == before.current.weatherCode)
    }

    @Test("A leaf proto3 dropped stays dropped on disk: the 0 °C low encodes without degrees and still reads as zero")
    func omittedZeroSurvives() throws {
        let data = try JSONEncoder().encode(Self.snapshot())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try #require((object["days"] as? [String: Any])?["forecastDays"] as? [[String: Any]])
        let low = try #require(days[1]["minTemperature"] as? [String: Any])
        #expect(low["degrees"] == nil)
        #expect(low["unit"] as? String == "CELSIUS")
        // A nil failure is an absent key, the same shape a missing leaf has.
        #expect(object["historyFailure"] == nil)
        #expect(object["hoursFailure"] as? String == Self.hoursReason)

        let decoded = try JSONDecoder().decode(WeatherNextService.RawSnapshot.self, from: data)
        #expect(decoded.days?.forecastDays?[1].minTemperature?.degrees == nil)
        #expect(try Self.adapt(decoded).daily.tempMin == [15, 0])
    }

    @Test("A current-only snapshot keeps days nil, so it can never be taken for a forecast")
    func currentOnlySnapshot() throws {
        let summary = WeatherNextService.RawSnapshot(fetchedAt: Self.fetchedAt, current: Fixture.current,
                                                     hoursPages: [], days: nil, history: nil,
                                                     hoursFailure: nil, historyFailure: nil)
        let decoded = try JSONDecoder().decode(WeatherNextService.RawSnapshot.self,
                                               from: try JSONEncoder().encode(summary))
        #expect(decoded.days == nil)
        #expect(decoded.history == nil)
        #expect(decoded.hoursPages.isEmpty)
        #expect(decoded.current?.currentTime == "2026-09-08T21:00:00Z")
    }

    @Test("The current reading has its own clock, and a file written before it had one reads it as absent")
    func currentClock() throws {
        var snapshot = Self.snapshot()
        snapshot.currentFetchedAt = Self.fetchedAt.addingTimeInterval(1200)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeatherNextService.RawSnapshot.self, from: data)
        #expect(decoded.currentFetchedAt == Self.fetchedAt.addingTimeInterval(1200))
        // The forecast clock is untouched by the current one.
        #expect(decoded.fetchedAt == Self.fetchedAt)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "currentFetchedAt")
        let old = try JSONDecoder().decode(WeatherNextService.RawSnapshot.self,
                                           from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.currentFetchedAt == nil)
        #expect(old.fetchedAt == Self.fetchedAt)
    }

    @Test("The cache round-trips a snapshot per place, keeps places apart, removes one at a time and reads a corrupt file as a miss")
    func cacheRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WeatherNextRawCache(directory: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(cache.snapshot(for: Fixture.place) == nil)

        cache.save(Self.snapshot(), for: Fixture.place)
        let read = try #require(cache.snapshot(for: Fixture.place))
        #expect(read.fetchedAt == Self.fetchedAt)
        #expect(read.hoursPages.count == 2)
        #expect(read.hoursPages.flatMap { $0.forecastHours ?? [] }.count == 2)
        #expect(read.hoursPages[0].nextPageToken == "ChQKEgoQ")
        #expect(read.history?.historyHours?.count == 1)
        #expect(read.hoursFailure == Self.hoursReason)
        #expect(read.historyFailure == nil)
        #expect(try Self.adapt(read).hourly.temperature == [21, 22, 23])

        // One JSON file, named by the place id; never UserDefaults.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["\(Fixture.place.id).json"])

        // A second place has its own file and disturbs nothing.
        let london = Place(name: "London", admin1: nil, country: "United Kingdom", countryCode: "GB",
                           latitude: 51.5, longitude: -0.12, timezone: "Europe/London")
        var other = Self.snapshot()
        other.current?.temperature = celsius(5)
        other.hoursFailure = nil
        other.historyFailure = "Google could not be reached."
        cache.save(other, for: london)
        #expect(cache.snapshot(for: Fixture.place)?.current?.temperature?.degrees == 22)
        #expect(cache.snapshot(for: london)?.current?.temperature?.degrees == 5)
        #expect(cache.snapshot(for: london)?.hoursFailure == nil)
        #expect(cache.snapshot(for: london)?.historyFailure == "Google could not be reached.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)

        // Remove is per place and a second remove is a no-op.
        cache.remove(for: Fixture.place)
        #expect(cache.snapshot(for: Fixture.place) == nil)
        #expect(cache.snapshot(for: london) != nil)
        cache.remove(for: Fixture.place)
        #expect(cache.snapshot(for: london) != nil)

        // A file that is not a snapshot reads as a miss, not a crash.
        try Data("{\"fetchedAt\": \"not a date\", \"hoursPages\": [".utf8)
            .write(to: directory.appendingPathComponent("\(london.id).json"))
        #expect(cache.snapshot(for: london) == nil)
    }

    @Test("A save after the folder was purged recreates it, and a rewrite replaces the old snapshot")
    func saveRecreatesFolder() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WeatherNextRawCache(directory: directory)
        try FileManager.default.removeItem(at: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        cache.save(Self.snapshot(), for: Fixture.place)
        #expect(cache.snapshot(for: Fixture.place)?.hoursPages.count == 2)

        var fresher = Self.snapshot()
        fresher.fetchedAt = Self.fetchedAt.addingTimeInterval(900)
        fresher.hoursPages = []
        fresher.hoursFailure = nil
        cache.save(fresher, for: Fixture.place)
        let read = try #require(cache.snapshot(for: Fixture.place))
        #expect(read.fetchedAt == Self.fetchedAt.addingTimeInterval(900))
        #expect(read.hoursPages.isEmpty)
        #expect(read.hoursFailure == nil)
    }
}
