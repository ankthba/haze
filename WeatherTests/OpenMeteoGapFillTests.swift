//
//  OpenMeteoGapFillTests.swift
//  WeatherTests
//
//  The gap fill is the one place a WeatherNext forecast takes numbers from a
//  second source, so what these tests pin are the rules that keep the two
//  from blurring: Google's values are never overwritten, only Open-Meteo days
//  before the first Google day are added, the cloud layers are scaled to
//  Google's total for the hour, and every Open-Meteo stamp is realigned by
//  absolute instant before any string is matched. The fill side goes through
//  real JSON so both column shapes (plain, and model-suffixed when NBM rides
//  along) and the element-optional decoding are exercised;
//  the response side is built with the memberwise inits, the way the adapter
//  builds it. The network fetch is not tested here.
//

import Testing
import Foundation
@testable import Haze_Weather

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

// MARK: - Fixtures

/// A WeatherNext-shaped response: no elevation, no nowcast, no cloud layers,
/// daily starting today, three afternoon hours. Google's total cover is 0 %
/// for the first hour and 50 % for the second, and the column stops there:
/// `Hourly.cloudCover` is not element-optional, so a column shorter than the
/// time array is how an hour with no total to scale against is expressed.
private func weatherNextResponse(cloudCover: [Double]? = [0, 50],
                                 cloudCoverLow: [Double?]? = nil,
                                 elevation: Double? = nil,
                                 minutely15: ForecastResponse.Minutely15? = nil,
                                 snowfallSum: [Double]? = [0, 35]) -> ForecastResponse {
    ForecastResponse(
        timezone: "America/Los_Angeles",
        utcOffsetSeconds: -25200,
        elevation: elevation,
        current: ForecastResponse.Current(
            time: "2026-09-08T14:00", temperature: 22, humidity: 55, apparentTemperature: 23,
            isDay: 1, precipitation: 0, weatherCode: 2, cloudCover: 40, pressure: 1013.2,
            windSpeed: 12, windDirection: 270, windGust: 20),
        hourly: ForecastResponse.Hourly(
            time: ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
            temperature: [21, 22, 23],
            humidity: [58, 55, 50],
            apparentTemperature: [21, 23, 23],
            precipitationProbability: [10, 20, 0],
            precipitation: [0.5, 1.0, 0],
            weatherCode: [3, 61, 0],
            windSpeed: [10, 12, 36],
            windDirection: [250, 270, 0],
            isDay: [1, 1, 1],
            cloudCover: cloudCover,
            dewPoint: [12, 13, 14],
            visibility: [16000, 10000, 16000],
            cloudCoverLow: cloudCoverLow, cloudCoverMid: nil, cloudCoverHigh: nil),
        daily: ForecastResponse.Daily(
            time: ["2026-09-08", "2026-09-09"],
            weatherCode: [61, 73],
            tempMax: [25, 2], tempMin: [15, 0],
            apparentMax: [26, 2], apparentMin: [14, 0],
            sunrise: ["2026-09-08T06:35", "2026-09-09T06:36"],
            sunset: ["2026-09-08T19:10", "2026-09-09T19:08"],
            precipitationSum: [4, 10], precipitationProbabilityMax: [60, 80],
            windSpeedMax: [20, 30], windGustMax: [35, 45], windDirectionDominant: [270, 10],
            snowfallSum: snowfallSum),
        minutely15: minutely15)
}

private func fill(_ json: String) throws -> OpenMeteoGapFill {
    try JSONDecoder().decode(OpenMeteoGapFill.self, from: Data(json.utf8))
}

/// Every daily column's length, so "one row was added to all of them" is a
/// single assertion. The snowfall column joins only when it exists.
private func dailyCounts(_ d: ForecastResponse.Daily) -> Set<Int> {
    var counts = [d.time.count, d.weatherCode.count, d.tempMax.count, d.tempMin.count,
                  d.apparentMax.count, d.apparentMin.count, d.sunrise.count, d.sunset.count,
                  d.precipitationSum.count, d.precipitationProbabilityMax.count,
                  d.windSpeedMax.count, d.windGustMax.count, d.windDirectionDominant.count]
    if let snow = d.snowfallSum { counts.append(snow.count) }
    return Set(counts)
}

private func layers(_ r: (low: Double?, mid: Double?, high: Double?)) -> [Double?] {
    [r.low, r.mid, r.high]
}

/// The same afternoon as seen by Open-Meteo, in the same zone. Yesterday's
/// row is the one that should be added; today's and tomorrow's carry 99s so
/// any leak into Google's rows is unmistakable. Hour 0 meets a Google total
/// of 0, hour 1 a total of 50 against Open-Meteo's 25, hour 2 no total.
private let sameZoneFill = """
{
  "timezone": "America/Los_Angeles",
  "utc_offset_seconds": -25200,
  "elevation": 2058.0,
  "hourly": {
    "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
    "cloud_cover": [40, 25, 80],
    "cloud_cover_low": [10, 10, 30],
    "cloud_cover_mid": [30, 20, 60],
    "cloud_cover_high": [40, 5, 75]
  },
  "daily": {
    "time": ["2026-09-07", "2026-09-08", "2026-09-09"],
    "weather_code": [1, 99, 99],
    "temperature_2m_max": [27.5, 99, 99],
    "temperature_2m_min": [13.1, -99, -99],
    "apparent_temperature_max": [26.8, 99, 99],
    "apparent_temperature_min": [12.4, -99, -99],
    "sunrise": ["2026-09-07T06:34", "2026-09-08T06:00", "2026-09-09T06:00"],
    "sunset": ["2026-09-07T19:12", "2026-09-08T19:00", "2026-09-09T19:00"],
    "precipitation_sum": [0.3, 99, 99],
    "precipitation_probability_max": [15, 99, 99],
    "wind_speed_10m_max": [18.4, 99, 99],
    "wind_gusts_10m_max": [null, 99, 99],
    "wind_direction_10m_dominant": [265, 99, 99],
    "snowfall_sum": [0, 99, 99]
  },
  "minutely_15": {
    "time": ["2026-09-08T14:00", "2026-09-08T14:15", "2026-09-08T14:30", "2026-09-08T14:45"],
    "precipitation": [0, 0.1, 0.4, 0.2]
  }
}
"""

/// Open-Meteo answering in a fixed -08:00 zone while the response is Pacific
/// daylight time (-07:00): every fill stamp is one wall-clock hour behind the
/// response's for the same instant. Only one hour is supplied, so where it
/// lands is unambiguous.
private let shiftedZoneFill = """
{
  "timezone": "Etc/GMT+8",
  "utc_offset_seconds": -28800,
  "elevation": 2058.0,
  "hourly": {
    "time": ["2026-09-08T13:00"],
    "cloud_cover": [25],
    "cloud_cover_low": [10],
    "cloud_cover_mid": [20],
    "cloud_cover_high": [5]
  },
  "daily": {
    "time": ["2026-09-07", "2026-09-08"],
    "weather_code": [1, 99],
    "temperature_2m_max": [27.5, 99],
    "temperature_2m_min": [13.1, -99],
    "sunrise": ["2026-09-07T05:34", "2026-09-08T05:00"],
    "sunset": ["2026-09-07T18:12", "2026-09-08T18:00"]
  },
  "minutely_15": {
    "time": ["2026-09-08T13:00", "2026-09-08T13:15"],
    "precipitation": [0.1, 0.2]
  }
}
"""

// MARK: - Layer scaling

struct OpenMeteoGapFillScalingTests {
    @Test("No Google total means nothing to reconcile: the layers pass through")
    func noTargetPassesThrough() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: 50, target: nil)) == [20, 40, 20])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: 40, high: nil, total: nil, target: nil)) == [nil, 40, nil])
    }

    @Test("A clear sky from Google clears every layer Open-Meteo reported")
    func zeroTargetIsClear() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: 50, target: 0)) == [0, 0, 0])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: 40, high: nil, total: nil, target: 0)) == [nil, 0, nil])
    }

    @Test("An hour Open-Meteo said nothing about stays unknown whatever Google says")
    func nothingReportedStaysUnknown() {
        // Not even a clear target invents layers; the UV model reads Google's
        // total for such an hour instead.
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: nil, high: nil, total: nil, target: 0)) == [nil, nil, nil])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: nil, high: nil, total: nil, target: 60)) == [nil, nil, nil])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: nil, high: nil, total: nil, target: nil)) == [nil, nil, nil])
    }

    @Test("Cloud Google sees but Open-Meteo did not comes back unknown, never invented")
    func cloudFromNowhereIsUnknown() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 0, mid: 0, high: 0, total: 0, target: 60)) == [nil, nil, nil])
        // A zero total governs even when a layer disagrees with it.
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 10, mid: nil, high: nil, total: 0, target: 60)) == [nil, nil, nil])
    }

    @Test("The layers keep their proportions and scale so the total matches Google's")
    func proportionalScaling() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: 50, target: 100)) == [40, 80, 40])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: 50, target: 25)) == [10, 20, 10])
        // The factor is exactly one when the two sources already agree.
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: 50, target: 50)) == [20, 40, 20])
    }

    @Test("No layer is scaled past 100")
    func clampedAtHundred() {
        // Layered cover is not additive, so a layer can sit above the total.
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 70, mid: 10, high: 10, total: 50, target: 100)) == [100, 20, 20])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 60, high: 20, total: 50, target: 100)) == [40, 100, 40])
    }

    @Test("A nil layer stays nil while its neighbours scale")
    func nilLayerStaysNil() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: 40, high: 20, total: 50, target: 100)) == [nil, 80, 40])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: nil, high: nil, total: 50, target: 100)) == [40, nil, nil])
    }

    @Test("Without a total the thickest layer governs")
    func missingTotalUsesThickestLayer() {
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: 20, mid: 40, high: 20, total: nil, target: 100)) == [50, 100, 50])
        #expect(layers(OpenMeteoGapFill.scaledLayers(low: nil, mid: 40, high: 20, total: nil, target: 20)) == [nil, 20, 10])
    }
}

// MARK: - Decoding

struct OpenMeteoGapFillDecodingTests {
    @Test("Nulls decode as unknown elements, absent blocks as nil, and the zone comes from the id")
    func decodesElementOptionals() throws {
        let decoded = try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
            "cloud_cover": [40, null, 80],
            "cloud_cover_low": [10, null, 30]
          },
          "daily": {
            "time": ["2026-09-07"],
            "weather_code": [null],
            "sunrise": [null]
          }
        }
        """)
        #expect(decoded.elevation == nil)
        #expect(decoded.minutely15 == nil)
        #expect(decoded.hourly?.cloudCover == [40, nil, 80])
        #expect(decoded.hourly?.cloudCoverLow == [10, nil, 30])
        #expect(decoded.hourly?.cloudCoverMid == nil)
        #expect(decoded.daily?.weatherCode == [nil])
        #expect(decoded.daily?.sunrise == [nil])
        #expect(decoded.daily?.tempMax == nil)
        #expect(decoded.zone?.identifier == "America/Los_Angeles")
    }

    @Test("An unknown zone id falls back to the fixed offset Open-Meteo also sends")
    func unknownZoneUsesOffset() throws {
        let decoded = try fill("""
        {"timezone": "Mars/Olympus_Mons", "utc_offset_seconds": -25200}
        """)
        #expect(decoded.zone?.secondsFromGMT() == -25200)
    }

    @Test("Two-model answers decode through the suffixed names, with NBM laid over best_match")
    func decodesSuffixedColumns() throws {
        let decoded = try fill("""
        {
          "timezone": "America/Chicago",
          "utc_offset_seconds": -18000,
          "elevation": 149.0,
          "hourly": {
            "time": ["2026-09-08T13:00"],
            "cloud_cover_best_match": [40],
            "cloud_cover_ncep_nbm_conus": [null],
            "cloud_cover_low_best_match": [10],
            "cloud_cover_low_ncep_nbm_conus": [null]
          },
          "daily": {
            "time": ["2026-09-07", "2026-09-08"],
            "weather_code_best_match": [1, 99],
            "weather_code_ncep_nbm_conus": [51, 51],
            "temperature_2m_max_best_match": [37.5, 99],
            "temperature_2m_max_ncep_nbm_conus": [33.9, null],
            "temperature_2m_min_best_match": [24.8, -99],
            "apparent_temperature_max_best_match": [40.1, 99],
            "apparent_temperature_max_ncep_nbm_conus": [36.2, 36.0, 35.0]
          },
          "minutely_15": {
            "time": ["2026-09-08T13:00", "2026-09-08T13:15"],
            "precipitation_best_match": [0.1, null],
            "precipitation_ncep_nbm_conus": [null, null]
          }
        }
        """)
        // Layers, codes and the nowcast are best_match's: NBM has none.
        #expect(decoded.hourly?.cloudCover == [40])
        #expect(decoded.hourly?.cloudCoverLow == [10])
        #expect(decoded.hourly?.cloudCoverMid == nil)
        #expect(decoded.daily?.weatherCode == [1, 99])
        #expect(decoded.minutely15?.precipitation == [0.1, nil])
        // Temperatures take NBM where it answered and best_match where it
        // did not; a longer NBM column is cut to best_match's grid.
        #expect(decoded.daily?.tempMax == [33.9, 99])
        #expect(decoded.daily?.tempMin == [24.8, -99])
        #expect(decoded.daily?.apparentMax == [36.2, 36.0])
        #expect(decoded.daily?.apparentMin == nil)
    }

    @Test("The request asks for every classic daily column and nothing else")
    func dailyColumns() {
        #expect(OpenMeteoGapFill.dailyColumns.count == 13)
        #expect(Set(OpenMeteoGapFill.dailyColumns).count == 13)
        #expect(OpenMeteoGapFill.dailyColumns.contains("temperature_2m_max"))
        #expect(OpenMeteoGapFill.dailyColumns.contains("snowfall_sum"))
        #expect(!OpenMeteoGapFill.dailyColumns.contains("time"))
    }
}

// MARK: - Realignment

struct GapFillRealignerTests {
    @Test("Equal zone ids are the identity, and an empty stamp is nil either way")
    func identity() {
        let same = GapFillRealigner(from: losAngeles, to: losAngeles)
        #expect(same.dateTime("2026-09-08T13:00") == "2026-09-08T13:00")
        #expect(same.date("2026-09-08") == "2026-09-08")
        #expect(same.dateTime("") == nil)
        #expect(same.date("") == nil)
    }

    @Test("Different zone ids go through the instant, so the hour shifts and the day label holds")
    func shiftsByInstant() {
        let shifted = GapFillRealigner(from: TimeZone(identifier: "Etc/GMT+8")!, to: losAngeles)
        #expect(shifted.dateTime("2026-09-08T13:00") == "2026-09-08T14:00")
        // 23:00 in -08:00 is midnight the next day in -07:00.
        #expect(shifted.dateTime("2026-09-08T23:00") == "2026-09-09T00:00")
        #expect(shifted.date("2026-09-07") == "2026-09-07")
        #expect(shifted.dateTime("not a stamp") == nil)

        // The other way round: a day label must not slip backwards either.
        let westward = GapFillRealigner(from: losAngeles, to: TimeZone(identifier: "Etc/GMT+8")!)
        #expect(westward.dateTime("2026-09-08T14:00") == "2026-09-08T13:00")
        #expect(westward.date("2026-09-07") == "2026-09-07")
    }
}

// MARK: - Splicing

struct OpenMeteoGapFillSpliceTests {
    @Test("Elevation and the nowcast are filled in, with the fill's own times")
    func elevationAndNowcast() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)

        #expect(response.elevation == 2058)
        let steps = try #require(response.minutely15)
        #expect(steps.time == ["2026-09-08T14:00", "2026-09-08T14:15", "2026-09-08T14:30", "2026-09-08T14:45"])
        #expect(steps.precipitation == [0, 0.1, 0.4, 0.2])
    }

    @Test("Exactly one yesterday row is prepended to every daily column, and Google's days are untouched")
    func prependsYesterday() throws {
        var response = weatherNextResponse()
        let before = response.daily
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        let daily = response.daily

        #expect(dailyCounts(daily) == [dailyCounts(before).first! + 1])
        #expect(daily.time == ["2026-09-07", "2026-09-08", "2026-09-09"])
        #expect(daily.weatherCode == [1, 61, 73])
        #expect(daily.tempMax == [27.5, 25, 2])
        #expect(daily.tempMin == [13.1, 15, 0])
        #expect(daily.apparentMax == [26.8, 26, 2])
        #expect(daily.apparentMin == [12.4, 14, 0])
        #expect(daily.sunrise == ["2026-09-07T06:34", "2026-09-08T06:35", "2026-09-09T06:36"])
        #expect(daily.sunset == ["2026-09-07T19:12", "2026-09-08T19:10", "2026-09-09T19:08"])
        #expect(daily.precipitationSum == [0.3, 4, 10])
        #expect(daily.precipitationProbabilityMax == [15, 60, 80])
        #expect(daily.windSpeedMax == [18.4, 20, 30])
        // A null in the fill reads as zero in the new row, not as a gap.
        #expect(daily.windGustMax == [0, 35, 45])
        #expect(daily.windDirectionDominant == [265, 270, 10])
        #expect(daily.snowfallSum == [0, 0, 35])
    }

    @Test("A yesterday without both its high and its low is not added at all")
    func yesterdayWithoutTemperaturesIsSkipped() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "daily": {
            "time": ["2026-09-07", "2026-09-08"],
            "weather_code": [1, 99],
            "temperature_2m_max": [27.5, 99],
            "temperature_2m_min": [null, -99]
          }
        }
        """), timezone: losAngeles)
        let daily = response.daily

        // Borrowing today's low would make "same as yesterday" true by
        // construction, so the row is left out and the comparison stays absent.
        #expect(dailyCounts(daily) == [2])
        #expect(daily.time == ["2026-09-08", "2026-09-09"])
        #expect(daily.tempMax == [25, 2])
        #expect(daily.tempMin == [15, 0])
    }

    @Test("A sparse yesterday with both temperatures zeros the rest and never borrows another day")
    func sparseYesterday() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "daily": {
            "time": ["2026-09-07", "2026-09-08"],
            "temperature_2m_max": [27.5, 99],
            "temperature_2m_min": [13.1, -99]
          }
        }
        """), timezone: losAngeles)
        let daily = response.daily

        #expect(dailyCounts(daily) == [3])
        #expect(daily.time.first == "2026-09-07")
        // No code at all reads as overcast; a missing feels-like takes the
        // same day's own air temperature.
        #expect(daily.weatherCode.first == 3)
        #expect(daily.tempMax.first == 27.5)
        #expect(daily.tempMin.first == 13.1)
        #expect(daily.apparentMax.first == 27.5)
        #expect(daily.apparentMin.first == 13.1)
        #expect(daily.sunrise.first == "")
        #expect(daily.sunset.first == "")
        #expect(daily.precipitationSum.first == 0)
        #expect(daily.precipitationProbabilityMax.first == 0)
        #expect(daily.windSpeedMax.first == 0)
        #expect(daily.snowfallSum?.first == 0)
        #expect(daily.tempMin[1] == 15)
    }

    @Test("A snowfall column that was never there is not invented by the prepend")
    func absentSnowfallStaysAbsent() throws {
        var response = weatherNextResponse(snowfallSum: nil)
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        #expect(response.daily.snowfallSum == nil)
        #expect(response.daily.time.count == 3)
    }

    @Test("Cloud layers follow the scaling rule hour by hour")
    func cloudLayersScaled() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        let hourly = response.hourly

        // Hour 0: Google says clear. Hour 1: Google's 50 against Open-Meteo's
        // 25 doubles each layer. Hour 2: no Google total, Open-Meteo as is.
        #expect(hourly.cloudCoverLow == [0, 20, 30])
        #expect(hourly.cloudCoverMid == [0, 40, 60])
        #expect(hourly.cloudCoverHigh == [0, 10, 75])
        // Google's own hourly columns are not touched by the fill.
        #expect(hourly.cloudCover == [0, 50])
        #expect(hourly.temperature == [21, 22, 23])
        #expect(hourly.weatherCode == [3, 61, 0])
    }

    @Test("A repeated wall-clock hour resolves to its later occurrence, as the adapter's does")
    func repeatedHourKeepsLater() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T14:00", "2026-09-08T14:00"],
            "cloud_cover": [25, 25],
            "cloud_cover_low": [10, 20]
          }
        }
        """), timezone: losAngeles)
        // Google's 50 against Open-Meteo's 25 doubles the later hour's 20.
        #expect(response.hourly.cloudCoverLow == [nil, 40, nil])
    }

    @Test("Slots that already hold a layer are left alone; only nil slots are filled")
    func existingLayersKept() throws {
        var response = weatherNextResponse(cloudCoverLow: [5, nil, nil])
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        #expect(response.hourly.cloudCoverLow == [5, 20, 30])
        #expect(response.hourly.cloudCoverMid == [0, 40, 60])
    }

    @Test("Values the response already has are never overwritten")
    func existingValuesWin() throws {
        let nowcast = ForecastResponse.Minutely15(time: ["2026-09-08T14:00"], precipitation: [9])
        var response = weatherNextResponse(elevation: 1000, minutely15: nowcast)
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        #expect(response.elevation == 1000)
        #expect(response.minutely15?.time == ["2026-09-08T14:00"])
        #expect(response.minutely15?.precipitation == [9])
    }

    @Test("A nowcast of nothing but nulls stays absent rather than reading as dry")
    func emptyNowcastStaysNil() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "minutely_15": {
            "time": ["2026-09-08T14:00", "2026-09-08T14:15"],
            "precipitation": [null, null]
          }
        }
        """), timezone: losAngeles)
        #expect(response.minutely15 == nil)
    }

    // MARK: Zone mismatch

    @Test("A fill in a different zone is aligned by instant: 13:00 at -08:00 is the response's 14:00")
    func shiftedZoneAlignsByInstant() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill(shiftedZoneFill), timezone: losAngeles)
        let hourly = response.hourly

        // Google's total for 14:00 is 50 against Open-Meteo's 25, so the
        // layers double and land on index 1, nowhere else. A naive string
        // match would have put them on index 0 and zeroed them.
        #expect(hourly.cloudCoverLow == [nil, 20, nil])
        #expect(hourly.cloudCoverMid == [nil, 40, nil])
        #expect(hourly.cloudCoverHigh == [nil, 10, nil])

        let steps = try #require(response.minutely15)
        #expect(steps.time == ["2026-09-08T14:00", "2026-09-08T14:15"])
        #expect(steps.precipitation == [0.1, 0.2])

        let daily = response.daily
        #expect(daily.time == ["2026-09-07", "2026-09-08", "2026-09-09"])
        #expect(daily.tempMax == [27.5, 25, 2])
        #expect(daily.tempMin == [13.1, 15, 0])
        // Sun times in the new row are re-expressed in the response's zone.
        #expect(daily.sunrise.first == "2026-09-07T06:34")
        #expect(daily.sunset.first == "2026-09-07T19:12")
        #expect(response.elevation == 2058)
    }

    // MARK: Nothing to splice

    @Test("When no hour matches, the layer columns are allocated to the hourly length and all unknown")
    func nothingMatches() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-10T13:00", "2026-09-10T14:00"],
            "cloud_cover": [40, 25],
            "cloud_cover_low": [10, 10],
            "cloud_cover_mid": [30, 20],
            "cloud_cover_high": [40, 5]
          },
          "daily": {
            "time": ["2026-09-08", "2026-09-09", "2026-09-10"],
            "weather_code": [99, 99, 99],
            "temperature_2m_max": [99, 99, 99]
          }
        }
        """), timezone: losAngeles)

        #expect(response.hourly.cloudCoverLow == [nil, nil, nil])
        #expect(response.hourly.cloudCoverMid == [nil, nil, nil])
        #expect(response.hourly.cloudCoverHigh == [nil, nil, nil])
        // Today-forward rows only: nothing is prepended and nothing changes.
        #expect(response.daily.time == ["2026-09-08", "2026-09-09"])
        #expect(response.daily.weatherCode == [61, 73])
        #expect(response.daily.tempMax == [25, 2])
        #expect(response.minutely15 == nil)
    }

    @Test("Value arrays shorter than the time array are safe and read as unknown")
    func shortArraysAreSafe() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
            "cloud_cover": [40],
            "cloud_cover_low": [10, 10],
            "cloud_cover_mid": [30, 20, 60]
          },
          "daily": {
            "time": ["2026-09-07"],
            "temperature_2m_max": [],
            "temperature_2m_min": [13.1]
          },
          "minutely_15": {
            "time": ["2026-09-08T14:00", "2026-09-08T14:15"],
            "precipitation": [0.5]
          }
        }
        """), timezone: losAngeles)
        let hourly = response.hourly

        // Hour 0: target 0 clears the two reported layers; the high column
        // was never sent, so it stays unknown. Hour 1: no total, so the
        // thickest layer (20) governs against Google's 50. Hour 2: no target,
        // Open-Meteo as is.
        #expect(hourly.cloudCoverLow == [0, 25, nil])
        #expect(hourly.cloudCoverMid == [0, 50, 60])
        #expect(hourly.cloudCoverHigh == [nil, nil, nil])
        // A high that ran out is unknown, and a day without one is not added.
        #expect(response.daily.time == ["2026-09-08", "2026-09-09"])
        #expect(response.daily.tempMax == [25, 2])
        #expect(response.minutely15?.time == ["2026-09-08T14:00"])
    }

    @Test("A fill with no blocks at all changes nothing")
    func emptyFillIsNoOp() throws {
        var response = weatherNextResponse()
        response.applyGapFill(try fill("""
        {"timezone": "America/Los_Angeles", "utc_offset_seconds": -25200}
        """), timezone: losAngeles)

        #expect(response.elevation == nil)
        #expect(response.minutely15 == nil)
        #expect(response.hourly.cloudCoverLow == nil)
        #expect(response.hourly.cloudCoverMid == nil)
        #expect(response.hourly.cloudCoverHigh == nil)
        #expect(response.daily.time == ["2026-09-08", "2026-09-09"])
    }

    // MARK: What the UV model reads

    @Test("An hour with no layers hands the UV model Google's total, so overcast is not clear-sky UV")
    func uvFallsBackToGoogleTotal() throws {
        // No fill at all (a failed or rate-limited call): every layer nil,
        // Google's total 100 for the hour.
        let response = weatherNextResponse(cloudCover: [100, 50])
        let clouds = WeatherService.uvClouds(in: response.hourly, at: 0)
        #expect(clouds.low == 100)
        #expect(clouds.mid == nil)
        #expect(clouds.high == nil)
        #expect(UVIndex.cloudTransmission(low: clouds.low, mid: clouds.mid, high: clouds.high) < 0.5)

        // An hour past the end of Google's total column has nothing to offer.
        let beyond = WeatherService.uvClouds(in: response.hourly, at: 2)
        #expect(beyond.low == nil && beyond.mid == nil && beyond.high == nil)
    }

    @Test("Once any layer is known the layers are read as they are")
    func uvPrefersLayers() throws {
        var response = weatherNextResponse(cloudCover: [100, 50], cloudCoverLow: [nil, 20, nil])
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        // Hour 1 keeps its own low deck (20) and takes the fill's mid and high.
        let filled = WeatherService.uvClouds(in: response.hourly, at: 1)
        #expect(filled.low == 20)
        #expect(filled.mid == 40)
        #expect(filled.high == 10)

        // A single known layer is enough to stop the total standing in.
        let partial = weatherNextResponse(cloudCover: [100], cloudCoverLow: [5])
        let clouds = WeatherService.uvClouds(in: partial.hourly, at: 0)
        #expect(clouds.low == 5)
        #expect(clouds.mid == nil)
    }

    @Test("An empty hourly series is left alone")
    func emptyHourlyIsSafe() throws {
        var response = weatherNextResponse()
        response.hourly = ForecastResponse.Hourly(
            time: [], temperature: [], humidity: [], apparentTemperature: [],
            precipitationProbability: [], precipitation: [], weatherCode: [],
            windSpeed: [], windDirection: [], isDay: [], cloudCover: [],
            dewPoint: nil, visibility: nil,
            cloudCoverLow: nil, cloudCoverMid: nil, cloudCoverHigh: nil)
        response.applyGapFill(try fill(sameZoneFill), timezone: losAngeles)
        #expect(response.hourly.cloudCoverLow == nil)
        #expect(response.daily.time.count == 3)
    }
}

// MARK: - Appended hours

/// Every hourly column's length, the optional columns included when present.
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

/// When Google's hourly quota is spent the fill supplies whole hours, not
/// just cloud layers. The rule that matters most is the one the file header
/// opens with: a Google row is never overwritten, however many Open-Meteo
/// hours arrive for the same labels; the rest is bookkeeping (one length for
/// every column, ascending order, metres, Open-Meteo's own layers).
struct OpenMeteoGapFillAppendTests {
    /// A response with a single Google hour, 14:00, every column present.
    private func oneHourResponse() -> ForecastResponse {
        var response = weatherNextResponse(cloudCover: [50])
        response.hourly = ForecastResponse.Hourly(
            time: ["2026-09-08T14:00"], temperature: [22], humidity: [55], apparentTemperature: [23],
            precipitationProbability: [20], precipitation: [1.0], weatherCode: [61],
            windSpeed: [12], windDirection: [270], isDay: [1], cloudCover: [50],
            dewPoint: [13], visibility: [10000],
            cloudCoverLow: nil, cloudCoverMid: nil, cloudCoverHigh: nil)
        return response
    }

    /// Open-Meteo's three hours around it. The 14:00 column carries 99s
    /// wherever Google has a value, so a leak is unmistakable.
    private static let threeHourFill = """
    {
      "timezone": "America/Los_Angeles",
      "utc_offset_seconds": -25200,
      "hourly": {
        "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
        "temperature_2m": [21, 99, 23],
        "relative_humidity_2m": [58, 99, 50],
        "apparent_temperature": [21, 99, 23],
        "precipitation_probability": [10, 99, 0],
        "precipitation": [0.5, 99, 0],
        "weather_code": [3, 99, 0],
        "wind_speed_10m": [10, 99, 36],
        "wind_direction_10m": [250, 99, 0],
        "is_day": [1, 0, 1],
        "dew_point_2m": [12, 99, 14],
        "visibility": [16000, 99, 16000],
        "cloud_cover": [40, 25, 80],
        "cloud_cover_low": [10, 10, 30],
        "cloud_cover_mid": [30, 20, 60],
        "cloud_cover_high": [40, 5, 75]
      }
    }
    """

    @Test("Hours Google lacks are appended around the one it has, and that one keeps every value")
    func appendsAroundGoogleHour() throws {
        var response = oneHourResponse()
        response.applyGapFill(try fill(Self.threeHourFill), timezone: losAngeles)
        let hourly = response.hourly

        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"])
        #expect(hourlyCounts(hourly) == [3])
        #expect(hourly.temperature == [21, 22, 23])
        #expect(hourly.humidity == [58, 55, 50])
        #expect(hourly.apparentTemperature == [21, 23, 23])
        #expect(hourly.precipitationProbability == [10, 20, 0])
        #expect(hourly.precipitation == [0.5, 1.0, 0])
        #expect(hourly.weatherCode == [3, 61, 0])
        #expect(hourly.windSpeed == [10, 12, 36])
        #expect(hourly.windDirection == [250, 270, 0])
        #expect(hourly.isDay == [1, 1, 1])
        #expect(hourly.dewPoint == [12, 13, 14])
        #expect(hourly.visibility == [16000, 10000, 16000])
        #expect(hourly.cloudCover == [40, 50, 80])
        // Google's hour had its layers scaled to its total (50 against
        // Open-Meteo's 25 doubles them); the appended hours carry
        // Open-Meteo's own, there being no Google total to scale against.
        #expect(hourly.cloudCoverLow == [10, 20, 30])
        #expect(hourly.cloudCoverMid == [30, 40, 60])
        #expect(hourly.cloudCoverHigh == [40, 10, 75])
    }

    @Test("A fill in another zone is realigned before the label check, so Google's hour is not doubled")
    func shiftedZoneDoesNotDouble() throws {
        // 13:00 at -08:00 is 14:00 PDT, the hour Google already has; 12:00 is new.
        var response = oneHourResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "Etc/GMT+8",
          "utc_offset_seconds": -28800,
          "hourly": {
            "time": ["2026-09-08T12:00", "2026-09-08T13:00"],
            "temperature_2m": [21, 99],
            "weather_code": [3, 99],
            "cloud_cover": [40, 25],
            "dew_point_2m": [12, 99],
            "visibility": [16000, 99]
          }
        }
        """), timezone: losAngeles)
        let hourly = response.hourly
        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00"])
        #expect(hourlyCounts(hourly) == [2])
        #expect(hourly.temperature == [21, 22])
        #expect(hourly.weatherCode == [3, 61])
        #expect(hourly.cloudCover == [40, 50])
        #expect(hourly.dewPoint == [12, 13])
        #expect(hourly.visibility == [16000, 10000])
    }

    @Test("An Open-Meteo hour without a temperature is not appended; its other nulls take the yesterday row's defaults")
    func nullTemperatureSkipped() throws {
        var response = oneHourResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T13:00", "2026-09-08T15:00", "2026-09-08T16:00"],
            "temperature_2m": [21, null, 24],
            "weather_code": [3, 0, null],
            "is_day": [1, 1, null],
            "cloud_cover": [40, 80, 10],
            "dew_point_2m": [12, 14, 15],
            "visibility": [16000, 16000, 16000]
          }
        }
        """), timezone: losAngeles)
        let hourly = response.hourly
        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T16:00"])
        #expect(hourlyCounts(hourly) == [3])
        #expect(hourly.temperature == [21, 22, 24])
        // No humidity or wind reads as zero, no feels-like as the hour's own
        // temperature, no code as overcast, no is_day as daylight.
        #expect(hourly.humidity == [0, 55, 0])
        #expect(hourly.apparentTemperature == [21, 23, 24])
        #expect(hourly.precipitationProbability == [0, 20, 0])
        #expect(hourly.precipitation == [0, 1.0, 0])
        #expect(hourly.weatherCode == [3, 61, 3])
        #expect(hourly.windSpeed == [0, 12, 0])
        #expect(hourly.isDay == [1, 1, 1])
        #expect(hourly.cloudCover == [40, 50, 10])
        #expect(hourly.dewPoint == [12, 13, 15])
    }

    @Test("A null in an Open-Meteo hour before Google's is bridged from its neighbour, so Google's dew points and visibility survive")
    func nullBeforeGoogleIsBridged() throws {
        // Open-Meteo's yesterday sorts ahead of everything Google sent; one
        // null there used to end the whole column at hour 0.
        var response = oneHourResponse()
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T12:00", "2026-09-08T13:00", "2026-09-08T15:00", "2026-09-08T16:00"],
            "temperature_2m": [20, 21, 23, 24],
            "dew_point_2m": [null, 12, 14, null],
            "visibility": [null, null, 16000, 12000],
            "cloud_cover": [30, null, 80, 10]
          }
        }
        """), timezone: losAngeles)
        let hourly = response.hourly
        #expect(hourly.time == ["2026-09-08T12:00", "2026-09-08T13:00", "2026-09-08T14:00",
                                "2026-09-08T15:00", "2026-09-08T16:00"])
        // The first hour takes the next value, a later hole the one before
        // it, and Google's 14:00 keeps its own; the trailing null still ends
        // the dew point column.
        #expect(hourly.dewPoint == [12, 12, 13, 14])
        #expect(hourly.visibility == [10000, 10000, 10000, 16000, 12000])
        #expect(hourly.cloudCover == [30, 30, 50, 80, 10])
        #expect(hourly.temperature == [20, 21, 22, 23, 24])
    }

    @Test("A Google hour without a value still ends the column where the adapter did")
    func googleGapStillEndsColumn() throws {
        // Google's column stops after its first hour (the adapter's rule for
        // a gap); the appended hour after it must not reopen the column.
        var response = weatherNextResponse(cloudCover: [0])
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T12:00", "2026-09-08T16:00"],
            "temperature_2m": [20, 24],
            "cloud_cover": [30, 10]
          }
        }
        """), timezone: losAngeles)
        #expect(response.hourly.time.count == 5)
        #expect(response.hourly.cloudCover == [30, 0])
    }

    @Test("A shorter Google horizon is extended with Open-Meteo's later hours, and the extension is in metres")
    func extendsHorizon() throws {
        // Google's three hours with a full-length total column; Open-Meteo
        // covers the same three plus two more, in feet.
        var response = weatherNextResponse(cloudCover: [0, 50, 90])
        var longer = try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00", "2026-09-08T16:00", "2026-09-08T17:00"],
            "temperature_2m": [99, 99, 99, 24, 25],
            "relative_humidity_2m": [99, 99, 99, 45, 40],
            "apparent_temperature": [99, 99, 99, 24.5, 25.5],
            "precipitation_probability": [99, 99, 99, 0, 5],
            "precipitation": [99, 99, 99, 0, 0.1],
            "weather_code": [99, 99, 99, 1, 2],
            "wind_speed_10m": [99, 99, 99, 15, 18],
            "wind_direction_10m": [99, 99, 99, 280, 285],
            "is_day": [0, 0, 0, 1, 0],
            "dew_point_2m": [99, 99, 99, 14.5, 15],
            "visibility": [99, 99, 99, 50000, 10000],
            "cloud_cover": [40, 25, 45, 60, 10],
            "cloud_cover_low": [10, 10, 30, 20, 5],
            "cloud_cover_mid": [30, 20, 60, 25, 5],
            "cloud_cover_high": [40, 5, 75, 30, 5]
          }
        }
        """)
        longer.visibilityInFeet = true
        response.applyGapFill(longer, timezone: losAngeles)
        let hourly = response.hourly

        #expect(hourly.time == ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00",
                                "2026-09-08T16:00", "2026-09-08T17:00"])
        #expect(hourlyCounts(hourly) == [5])
        #expect(hourly.temperature == [21, 22, 23, 24, 25])
        #expect(hourly.humidity == [58, 55, 50, 45, 40])
        #expect(hourly.weatherCode == [3, 61, 0, 1, 2])
        #expect(hourly.isDay == [1, 1, 1, 1, 0])
        #expect(hourly.dewPoint == [12, 13, 14, 14.5, 15])
        // Google's metres stay; 50000 ft and 10000 ft become metres.
        let visibility = try #require(hourly.visibility)
        #expect(visibility.count == 5)
        #expect(Array(visibility.prefix(3)) == [16000, 10000, 16000])
        #expect(abs(visibility[3] - 15240) < 0.01)
        #expect(abs(visibility[4] - 3048) < 0.01)
        #expect(hourly.cloudCover == [0, 50, 90, 60, 10])
        // Hour 0 clears to Google's 0, hour 1 doubles (50 against 25), hour 2
        // doubles and clamps (90 against 45); the two new hours are as sent.
        #expect(hourly.cloudCoverLow == [0, 20, 60, 20, 5])
        #expect(hourly.cloudCoverMid == [0, 40, 100, 25, 5])
        #expect(hourly.cloudCoverHigh == [0, 10, 100, 30, 5])
    }

    @Test("A fill whose hours are all already Google's appends nothing and changes no value")
    func nothingToAppend() throws {
        var response = weatherNextResponse(cloudCover: [0, 50, 90])
        let before = response.hourly
        response.applyGapFill(try fill("""
        {
          "timezone": "America/Los_Angeles",
          "utc_offset_seconds": -25200,
          "hourly": {
            "time": ["2026-09-08T13:00", "2026-09-08T14:00", "2026-09-08T15:00"],
            "temperature_2m": [99, 99, 99],
            "weather_code": [99, 99, 99],
            "dew_point_2m": [99, 99, 99],
            "visibility": [99, 99, 99],
            "cloud_cover": [99, 99, 99]
          }
        }
        """), timezone: losAngeles)
        let hourly = response.hourly
        #expect(hourly.time == before.time)
        #expect(hourly.temperature == before.temperature)
        #expect(hourly.weatherCode == before.weatherCode)
        #expect(hourly.dewPoint == before.dewPoint)
        #expect(hourly.visibility == before.visibility)
        #expect(hourly.cloudCover == before.cloudCover)
        #expect(hourly.isDay == before.isDay)
    }
}

// MARK: - The stored fill

/// A load served from the Google snapshot must not send an Open-Meteo request
/// either, so the fill's body is kept beside the snapshot with the units it
/// was formatted in. What matters: it reads back as the same fill, the feet
/// flag comes from the request and not the file, other units are a miss,
/// and removing the place takes the fill with it.
struct OpenMeteoGapFillStoredTests {
    private static let place = Place(name: "Big Bear Lake", admin1: "California", country: "United States",
                                     countryCode: "US", latitude: 34.24, longitude: -116.91,
                                     timezone: "America/Los_Angeles")

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenMeteoGapFillStoredTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("The units key is the request's unit triple, with auto precipitation resolved")
    func unitsKey() {
        #expect(OpenMeteoGapFill.unitsKey(temperatureUnit: .celsius, speedUnit: .kmh, precipUnit: .mm)
                == "celsius,kmh,mm")
        #expect(OpenMeteoGapFill.unitsKey(temperatureUnit: .fahrenheit, speedUnit: .mph, precipUnit: .auto)
                == "fahrenheit,mph,inch")
    }

    @Test("Decoding a body sets the feet flag from the request, so a stored fill is read in the units it was asked for")
    func decodeSetsFeetFlag() throws {
        let body = Data("""
        {"timezone": "America/Los_Angeles", "utc_offset_seconds": -25200, "elevation": 2058}
        """.utf8)
        #expect(try #require(OpenMeteoGapFill.decode(body, precipAPI: "inch")).visibilityInFeet)
        #expect(!(try #require(OpenMeteoGapFill.decode(body, precipAPI: "mm")).visibilityInFeet))
        #expect(try #require(OpenMeteoGapFill.decode(body, precipAPI: "mm")).elevation == 2058)
        #expect(OpenMeteoGapFill.decode(Data("nope".utf8), precipAPI: "mm") == nil)
    }

    @Test("A stored fill round-trips through the cache beside the snapshot and goes with the place")
    func cacheRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WeatherNextRawCache(directory: directory)
        #expect(cache.gapFill(for: Self.place) == nil)

        let fetchedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let body = Data("{\"timezone\": \"America/Los_Angeles\", \"utc_offset_seconds\": -25200}".utf8)
        cache.save(gapFill: OpenMeteoGapFill.Stored(fetchedAt: fetchedAt, units: "celsius,kmh,mm", body: body),
                   for: Self.place)
        let read = try #require(cache.gapFill(for: Self.place))
        #expect(read.fetchedAt == fetchedAt)
        #expect(read.units == "celsius,kmh,mm")
        #expect(read.body == body)
        #expect(OpenMeteoGapFill.decode(read.body, precipAPI: "mm")?.timezone == "America/Los_Angeles")
        // Its own file, under the snapshot's stem.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["\(Self.place.id).fill.json"])

        cache.remove(for: Self.place)
        #expect(cache.gapFill(for: Self.place) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
