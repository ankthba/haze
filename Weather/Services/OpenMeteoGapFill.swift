//
//  OpenMeteoGapFill.swift
//  Weather
//
//  Google's Weather API cannot supply four things Open-Meteo does, and the
//  app would otherwise lose them the moment WeatherNext is switched on: the
//  15-minute precipitation nowcast behind "rain starting around" and the Rain
//  Live Activity, a pre-today daily row for the "yesterday's high and low"
//  comparison (Google keeps only 24 h of history and no past daily rows),
//  the low/mid/high cloud layers the sunrise-quality and UV models read, and
//  the grid-cell elevation the UV altitude term uses.
//
//  It also stands in for Google's hours wherever there are none. Google's
//  hourly forecast is paged, every page counts against a per-day quota, and a
//  page can fail or the quota can run out; the horizon Google covers is also
//  shorter than Open-Meteo's ten days plus yesterday. So the request carries
//  the classic path's full hourly column set, and any hour Google did not
//  provide is appended as a complete Open-Meteo row. With no Google hours at
//  all (the hourly quota gone for the day) the series is Open-Meteo's whole
//  one, while current conditions and the day rows stay Google's.
//
//  This is the NBM overlay in reverse: one slim Open-Meteo request rides
//  alongside the Google fetch and only ever fills what Google left empty.
//  Google's numbers win everywhere they exist; today-forward daily rows and
//  every hourly value Google provided (except the cloud layers it never
//  carries) are never touched. It is a single-location request per refresh,
//  the same shape the classic path makes today (multi-point Open-Meteo
//  requests once got the whole app rate limited, so it must stay that way).
//
//  Inside the National Blend's coverage the same request also asks for NBM,
//  because best_match is raw GFS there and its daily highs run hot (see
//  NBMOverlay.swift). The classic path lays NBM over its yesterday row and
//  its hours, so the rows this fill adds are calibrated the same way;
//  otherwise the "than yesterday" sentence would pair a hot yesterday with
//  Google's today, and a stand-in hour would run hotter than its Google
//  neighbour. Asking for two models makes Open-Meteo suffix every column with
//  its model id, so the blocks decode both the plain and the suffixed shape.
//
//  Alignment: WeatherNext writes local wall-clock strings in Google's zone id,
//  while Open-Meteo with timezone=auto picks its own IANA id from the
//  coordinates. Almost always the same zone, but never assumed: every
//  Open-Meteo stamp is parsed in Open-Meteo's zone and re-expressed in the
//  response's zone before any string is matched. Equal zone ids make that an
//  identity.
//

import Foundation

/// The slice of an Open-Meteo forecast that plugs WeatherNext's gaps. Every
/// value array is element-optional: Open-Meteo returns null for hours or
/// fields a model does not cover, and a null must read as "unknown", never as
/// zero. The blocks themselves are optional too, because the 15-minute model
/// covers only some regions and the key is simply absent elsewhere.
nonisolated struct OpenMeteoGapFill: Decodable {
    /// Every column the classic request asks for, so an appended hour can be
    /// as complete as a classic one. The eight columns NBMOverlay lays over
    /// the classic hours are read `calibrated` here for the same reason the
    /// daily ones are: a stand-in hour must carry the blend the classic path
    /// would have shown for it, not raw GFS.
    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double?]?
        let humidity: [Double?]?
        let apparentTemperature: [Double?]?
        let precipitationProbability: [Int?]?
        let precipitation: [Double?]?
        let weatherCode: [Int?]?
        let windSpeed: [Double?]?
        let windDirection: [Double?]?
        let isDay: [Int?]?
        let dewPoint: [Double?]?
        let visibility: [Double?]?
        let cloudCover: [Double?]?
        let cloudCoverLow: [Double?]?
        let cloudCoverMid: [Double?]?
        let cloudCoverHigh: [Double?]?

        init(from decoder: Decoder) throws {
            let columns = try ModelColumns(from: decoder)
            time = try columns.time()
            temperature = try columns.calibrated("temperature_2m")
            humidity = try columns.calibrated("relative_humidity_2m")
            apparentTemperature = try columns.calibrated("apparent_temperature")
            precipitationProbability = try columns.calibrated("precipitation_probability")
            precipitation = try columns.column("precipitation")
            weatherCode = try columns.column("weather_code")
            windSpeed = try columns.calibrated("wind_speed_10m")
            windDirection = try columns.calibrated("wind_direction_10m")
            isDay = try columns.column("is_day")
            dewPoint = try columns.calibrated("dew_point_2m")
            visibility = try columns.calibrated("visibility")
            cloudCover = try columns.column("cloud_cover")
            cloudCoverLow = try columns.column("cloud_cover_low")
            cloudCoverMid = try columns.column("cloud_cover_mid")
            cloudCoverHigh = try columns.column("cloud_cover_high")
        }
    }

    /// Every column the classic request asks for, so a prepended yesterday
    /// row can be as complete as a classic one. The columns NBMOverlay lays
    /// over the classic daily rows are read `calibrated` here, so the row
    /// carries the same blend the classic path would have shown for it.
    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int?]?
        let tempMax: [Double?]?
        let tempMin: [Double?]?
        let apparentMax: [Double?]?
        let apparentMin: [Double?]?
        let sunrise: [String?]?
        let sunset: [String?]?
        let precipitationSum: [Double?]?
        let precipitationProbabilityMax: [Int?]?
        let windSpeedMax: [Double?]?
        let windGustMax: [Double?]?
        let windDirectionDominant: [Double?]?
        let snowfallSum: [Double?]?

        init(from decoder: Decoder) throws {
            let columns = try ModelColumns(from: decoder)
            time = try columns.time()
            weatherCode = try columns.column("weather_code")
            tempMax = try columns.calibrated("temperature_2m_max")
            tempMin = try columns.calibrated("temperature_2m_min")
            apparentMax = try columns.calibrated("apparent_temperature_max")
            apparentMin = try columns.calibrated("apparent_temperature_min")
            sunrise = try columns.column("sunrise")
            sunset = try columns.column("sunset")
            precipitationSum = try columns.column("precipitation_sum")
            precipitationProbabilityMax = try columns.calibrated("precipitation_probability_max")
            windSpeedMax = try columns.calibrated("wind_speed_10m_max")
            windGustMax = try columns.calibrated("wind_gusts_10m_max")
            windDirectionDominant = try columns.calibrated("wind_direction_10m_dominant")
            snowfallSum = try columns.column("snowfall_sum")
        }
    }

    struct Minutely15: Decodable {
        let time: [String]
        let precipitation: [Double?]?

        init(from decoder: Decoder) throws {
            let columns = try ModelColumns(from: decoder)
            time = try columns.time()
            precipitation = try columns.column("precipitation")
        }
    }

    /// Open-Meteo names a column by its variable alone when one model answers
    /// and suffixes every column with the model id ("temperature_2m_max_best_match")
    /// as soon as more than one is requested. The fill asks for NBM alongside
    /// best_match inside NBM's coverage, so each block reads both shapes.
    struct ModelColumns {
        /// Open-Meteo's default blend: raw GFS for the US beyond the HRRR window.
        static let baseModel = "best_match"
        /// The NWS National Blend, the model the classic path calibrates with.
        static let calibratedModel = "ncep_nbm_conus"

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(_ name: String) { stringValue = name }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        private let container: KeyedDecodingContainer<Key>

        init(from decoder: Decoder) throws {
            container = try decoder.container(keyedBy: Key.self)
        }

        /// The time axis is never suffixed: one grid, however many models.
        func time() throws -> [String] {
            try container.decode([String].self, forKey: Key("time"))
        }

        /// The best_match column, under its plain or its suffixed name.
        func column<T: Decodable>(_ name: String) throws -> [T?]? {
            if let plain = try container.decodeIfPresent([T?].self, forKey: Key(name)) { return plain }
            return try container.decodeIfPresent([T?].self, forKey: Key(name + "_" + Self.baseModel))
        }

        /// NBM's column laid over best_match element by element, the way
        /// NBMOverlay merges: a null NBM element (a day or place the blend
        /// does not cover) falls back to the best-match one. Without an NBM
        /// column this is `column`.
        func calibrated<T: Decodable>(_ name: String) throws -> [T?]? {
            let base: [T?]? = try column(name)
            guard let nbm = try container.decodeIfPresent([T?].self, forKey: Key(name + "_" + Self.calibratedModel))
            else { return base }
            guard let base else { return nbm }
            return base.indices.map { i in (i < nbm.count ? nbm[i] : nil) ?? base[i] }
        }
    }

    let timezone: String
    let utcOffsetSeconds: Int
    let elevation: Double?
    let hourly: Hourly?
    let daily: Daily?
    let minutely15: Minutely15?

    /// Open-Meteo switches hourly visibility to feet whenever the precipitation
    /// unit is "inch", and nothing in the payload says so. Only the request
    /// knows which unit it asked for, so `fetch` sets this and the splice
    /// converts appended rows to the metres every other visibility in the app
    /// is in. Not a wire field: a decoded fill defaults to metres.
    var visibilityInFeet = false

    enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case elevation
        case hourly, daily
        case minutely15 = "minutely_15"
    }

    /// The zone Open-Meteo wrote its wall-clock strings in.
    var zone: TimeZone? {
        TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: utcOffsetSeconds)
    }

    /// The classic request's hourly columns, plus the total cover the layers
    /// are scaled against. Same list, same order, so an appended hour is
    /// indistinguishable from a classic one downstream.
    static let hourlyColumns = [
        "temperature_2m", "relative_humidity_2m", "apparent_temperature",
        "precipitation_probability", "precipitation", "weather_code",
        "wind_speed_10m", "wind_direction_10m", "is_day",
        "dew_point_2m", "visibility",
        "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high"
    ]

    static let dailyColumns = [
        "weather_code", "temperature_2m_max", "temperature_2m_min",
        "apparent_temperature_max", "apparent_temperature_min",
        "sunrise", "sunset", "precipitation_sum",
        "precipitation_probability_max", "wind_speed_10m_max",
        "wind_gusts_10m_max", "wind_direction_10m_dominant",
        "snowfall_sum"
    ]

    /// A fill's answer as it arrived, kept by WeatherNextRawCache beside the
    /// place's snapshot. The body is stored rather than the decoded value
    /// because the blocks decode two column shapes and keeping an encoder in
    /// step with that buys nothing; decoding 50 KB again is nothing. Open-Meteo
    /// formats the numbers server side, so `units` records what it was asked
    /// for and a request in other units cannot reuse it.
    struct Stored: Codable {
        var fetchedAt: Date
        var units: String
        var body: Data
    }

    /// The request's unit triple, the key a stored fill is checked against.
    static func unitsKey(temperatureUnit: TemperatureUnit, speedUnit: SpeedUnit, precipUnit: PrecipUnit) -> String {
        [temperatureUnit.apiValue, speedUnit.apiValue,
         precipUnit.apiValue(temperatureUnit: temperatureUnit)].joined(separator: ",")
    }

    /// The fill for a WeatherNext load: the stored one when it is younger
    /// than `maxAge` and in the same units, else a fetch, saved on success.
    /// The same window the Google snapshot is served under, so a load that
    /// spent no Google calls spends no Open-Meteo call either; a unit change
    /// still needs one, Open-Meteo having formatted the last answer in the
    /// old units. Nil on any failure, as `fetch` is.
    static func load(place: Place,
                     temperatureUnit: TemperatureUnit,
                     speedUnit: SpeedUnit,
                     precipUnit: PrecipUnit,
                     maxAge: TimeInterval,
                     session: URLSession,
                     cache: WeatherNextRawCache = .shared) async -> OpenMeteoGapFill? {
        let units = unitsKey(temperatureUnit: temperatureUnit, speedUnit: speedUnit, precipUnit: precipUnit)
        let precipAPI = precipUnit.apiValue(temperatureUnit: temperatureUnit)
        if maxAge > 0, let stored = cache.gapFill(for: place), stored.units == units,
           Date().timeIntervalSince(stored.fetchedAt) < maxAge,
           let fill = decode(stored.body, precipAPI: precipAPI) {
            return fill
        }
        guard let body = await fetchBody(place: place, temperatureUnit: temperatureUnit,
                                         speedUnit: speedUnit, precipUnit: precipUnit, session: session),
              let fill = decode(body, precipAPI: precipAPI) else { return nil }
        cache.save(gapFill: Stored(fetchedAt: Date(), units: units, body: body), for: place)
        return fill
    }

    /// Nil on any failure: the fill is a completeness upgrade, never a reason
    /// to lose the forecast. Unit and span parameters mirror the classic
    /// request exactly, so a spliced value can never arrive in a different
    /// unit or day grid than the one the app was built around.
    static func fetch(place: Place,
                      temperatureUnit: TemperatureUnit,
                      speedUnit: SpeedUnit,
                      precipUnit: PrecipUnit,
                      session: URLSession) async -> OpenMeteoGapFill? {
        guard let body = await fetchBody(place: place, temperatureUnit: temperatureUnit,
                                         speedUnit: speedUnit, precipUnit: precipUnit, session: session)
        else { return nil }
        return decode(body, precipAPI: precipUnit.apiValue(temperatureUnit: temperatureUnit))
    }

    /// A decoded body with the feet flag set from the request that made it;
    /// only the request knows which visibility unit Open-Meteo used.
    static func decode(_ body: Data, precipAPI: String) -> OpenMeteoGapFill? {
        guard var fill = try? JSONDecoder().decode(OpenMeteoGapFill.self, from: body) else { return nil }
        fill.visibilityInFeet = precipAPI == "inch"
        return fill
    }

    /// The 2xx body of one fill request, nil otherwise.
    private static func fetchBody(place: Place,
                                  temperatureUnit: TemperatureUnit,
                                  speedUnit: SpeedUnit,
                                  precipUnit: PrecipUnit,
                                  session: URLSession) async -> Data? {
        let precipAPI = precipUnit.apiValue(temperatureUnit: temperatureUnit)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "hourly", value: hourlyColumns.joined(separator: ",")),
            .init(name: "daily", value: dailyColumns.joined(separator: ",")),
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "12"),
            .init(name: "past_days", value: "1"),
            .init(name: "forecast_days", value: "10"),
            .init(name: "temperature_unit", value: temperatureUnit.apiValue),
            .init(name: "wind_speed_unit", value: speedUnit.apiValue),
            .init(name: "precipitation_unit", value: precipAPI),
            .init(name: "timezone", value: "auto")
        ]
        // Inside the National Blend's coverage the same call also carries
        // NBM, so the yesterday row and any stand-in hour are calibrated like
        // the classic path's (raw best_match runs hot there, see
        // NBMOverlay.swift). Still one single-location request.
        if NBMOverlay.covers(place) {
            components?.queryItems?.append(.init(
                name: "models",
                value: [ModelColumns.baseModel, ModelColumns.calibratedModel].joined(separator: ",")))
        }
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    /// Reconciles Open-Meteo's cloud layers with Google's total for the same
    /// hour. Layered cover is not additive (a low deck can hide a high one,
    /// and all three can be 80 % under a 90 % total), so there is no exact
    /// way to fit three layers to one total. This is a consistency nudge, not
    /// physics: the layers keep Open-Meteo's proportions and are scaled so
    /// their governing value (the total where Open-Meteo gives one, else the
    /// thickest layer) matches what Google shows for the hour, and no layer
    /// exceeds 100.
    ///
    /// - Open-Meteo reported nothing for the hour (no layer and no total):
    ///   all three stay nil whatever Google says. The fill never invents a
    ///   layer Open-Meteo did not describe, not even a clear one; the UV
    ///   model falls back to Google's total for such an hour.
    /// - `target == nil`: Google offered no total, so the layers pass through
    ///   unchanged; there is nothing to reconcile against.
    /// - `target == 0`: Google says clear, and every layer Open-Meteo
    ///   reported says clear too; a layer it did not report stays nil.
    /// - Open-Meteo's governing value is 0 while Google says cloudy: all
    ///   three come back nil. Inventing a split for a sky Open-Meteo did not
    ///   see would bias the sunrise score, and nil reads as "unknown".
    static func scaledLayers(low: Double?, mid: Double?, high: Double?,
                             total: Double?, target: Double?) -> (low: Double?, mid: Double?, high: Double?) {
        if low == nil, mid == nil, high == nil, total == nil { return (nil, nil, nil) }
        guard let target else { return (low, mid, high) }
        if target <= 0 { return (low.map { _ in 0 }, mid.map { _ in 0 }, high.map { _ in 0 }) }
        let governing = total ?? max(low ?? 0, mid ?? 0, high ?? 0)
        guard governing > 0 else { return (nil, nil, nil) }
        let factor = target / governing
        func scale(_ layer: Double?) -> Double? {
            layer.map { min(100, max(0, $0) * factor) }
        }
        return (scale(low), scale(mid), scale(high))
    }
}

// MARK: - Splicing

extension ForecastResponse {
    /// Fills the holes WeatherNext leaves, and nothing else: elevation when
    /// absent, the 15-minute nowcast when absent, daily rows for dates before
    /// the first Google day, the hourly cloud layers wherever they are still
    /// unknown, and a whole Open-Meteo row for every hour Google's series
    /// lacks. `timezone` is this response's own zone (Google's), and every
    /// Open-Meteo stamp is re-expressed in it before matching.
    nonisolated mutating func applyGapFill(_ fill: OpenMeteoGapFill, timezone: TimeZone) {
        let realign = GapFillRealigner(from: fill.zone ?? timezone, to: timezone)

        if elevation == nil { elevation = fill.elevation }

        if minutely15 == nil, let steps = fill.minutely15, let precipitation = steps.precipitation {
            var times: [String] = []
            var amounts: [Double] = []
            times.reserveCapacity(steps.time.count)
            amounts.reserveCapacity(steps.time.count)
            for (j, stamp) in steps.time.enumerated() {
                guard j < precipitation.count, let amount = precipitation[j],
                      let local = realign.dateTime(stamp) else { continue }
                times.append(local)
                amounts.append(amount)
            }
            // An empty nowcast would read as "no rain for three hours"; nil
            // keeps it honestly unknown.
            if !times.isEmpty {
                minutely15 = Minutely15(time: times, precipitation: amounts)
            }
        }

        if let fillDaily = fill.daily {
            prependPastDays(from: fillDaily, realign: realign)
        }

        if let fillHourly = fill.hourly {
            // Layers first, so only Google's hours are scaled against
            // Google's total; an appended hour keeps Open-Meteo's own layers,
            // there being no Google total to reconcile them with.
            fillCloudLayers(from: fillHourly, realign: realign)
            appendMissingHours(from: fillHourly, realign: realign,
                               visibilityInFeet: fill.visibilityInFeet)
        }
    }

    /// Prepends one full row per Open-Meteo day dated strictly before the
    /// first Google day, so every daily column keeps the same length and
    /// transform() finds the pre-today row it builds the yesterday comparison
    /// from. Rows from the first Google day onward are never touched.
    ///
    /// A day without both its high and its low is not added at all: the
    /// comparison is the row's only consumer and needs both, and standing in
    /// a neighbouring day's temperature would make "same as yesterday" true
    /// by construction.
    private nonisolated mutating func prependPastDays(from src: OpenMeteoGapFill.Daily,
                                                      realign: GapFillRealigner) {
        guard let firstDate = daily.time.first else { return }
        func value<T>(_ column: [T?]?, _ j: Int) -> T? {
            guard let column, j < column.count else { return nil }
            return column[j]
        }
        // ISO dates sort as strings, so "before" is a plain comparison.
        var rows: [(index: Int, date: String, high: Double, low: Double)] = []
        for (j, stamp) in src.time.enumerated() {
            guard let date = realign.date(stamp), date < firstDate,
                  let high = value(src.tempMax, j), let low = value(src.tempMin, j) else { continue }
            rows.append((j, date, high, low))
        }
        guard !rows.isEmpty else { return }
        rows.sort { $0.date < $1.date }
        var time: [String] = [], code: [Int] = []
        var tempMax: [Double] = [], tempMin: [Double] = []
        var apparentMax: [Double] = [], apparentMin: [Double] = []
        var sunrise: [String] = [], sunset: [String] = []
        var precipitationSum: [Double] = [], probabilityMax: [Int] = []
        var windSpeedMax: [Double] = [], windGustMax: [Double] = [], windDirection: [Double] = []
        var snowfallSum: [Double] = []
        for row in rows {
            let j = row.index
            time.append(row.date)
            code.append(value(src.weatherCode, j) ?? 3)
            tempMax.append(row.high)
            tempMin.append(row.low)
            // A missing feels-like falls back to the same day's own air
            // temperature, never to another day's.
            apparentMax.append(value(src.apparentMax, j) ?? row.high)
            apparentMin.append(value(src.apparentMin, j) ?? row.low)
            // The parser tolerates an empty sun time, so "" is the honest
            // stand-in for an absent one.
            sunrise.append(value(src.sunrise, j).flatMap(realign.dateTime) ?? "")
            sunset.append(value(src.sunset, j).flatMap(realign.dateTime) ?? "")
            precipitationSum.append(value(src.precipitationSum, j) ?? 0)
            probabilityMax.append(value(src.precipitationProbabilityMax, j) ?? 0)
            windSpeedMax.append(value(src.windSpeedMax, j) ?? 0)
            windGustMax.append(value(src.windGustMax, j) ?? 0)
            windDirection.append(value(src.windDirectionDominant, j) ?? 0)
            snowfallSum.append(value(src.snowfallSum, j) ?? 0)
        }

        daily.time = time + daily.time
        daily.weatherCode = code + daily.weatherCode
        daily.tempMax = tempMax + daily.tempMax
        daily.tempMin = tempMin + daily.tempMin
        daily.apparentMax = apparentMax + daily.apparentMax
        daily.apparentMin = apparentMin + daily.apparentMin
        daily.sunrise = sunrise + daily.sunrise
        daily.sunset = sunset + daily.sunset
        daily.precipitationSum = precipitationSum + daily.precipitationSum
        daily.precipitationProbabilityMax = probabilityMax + daily.precipitationProbabilityMax
        daily.windSpeedMax = windSpeedMax + daily.windSpeedMax
        daily.windGustMax = windGustMax + daily.windGustMax
        daily.windDirectionDominant = windDirection + daily.windDirectionDominant
        // Only a column that exists gets longer; inventing one would make
        // the day rows claim snow data the source never carried.
        if let existing = daily.snowfallSum {
            daily.snowfallSum = snowfallSum + existing
        }
    }

    /// Splices Open-Meteo's cloud layers into every hour whose layer is still
    /// unknown, scaled against Google's total for that hour. The columns are
    /// allocated to the hourly length, nil wherever no Open-Meteo hour lines
    /// up, and slots that already hold a value are left alone.
    private nonisolated mutating func fillCloudLayers(from src: OpenMeteoGapFill.Hourly,
                                                      realign: GapFillRealigner) {
        let count = hourly.time.count
        guard count > 0 else { return }
        // On a fall-back night two Open-Meteo hours share one wall-clock
        // label; the later wins, the same rule the WeatherNext adapter uses
        // for its own repeated hour, so both sides describe the same instant.
        var lookup: [String: Int] = [:]
        lookup.reserveCapacity(src.time.count)
        for (j, stamp) in src.time.enumerated() {
            guard let local = realign.dateTime(stamp) else { continue }
            lookup[local] = j
        }

        func column(_ existing: [Double?]?) -> [Double?] {
            var out = existing ?? []
            if out.count < count { out.append(contentsOf: Array(repeating: nil, count: count - out.count)) }
            return out
        }
        func element(_ column: [Double?]?, _ j: Int) -> Double? {
            guard let column, j < column.count else { return nil }
            return column[j]
        }
        var low = column(hourly.cloudCoverLow)
        var mid = column(hourly.cloudCoverMid)
        var high = column(hourly.cloudCoverHigh)

        for i in 0..<count {
            guard low[i] == nil || mid[i] == nil || high[i] == nil,
                  let j = lookup[hourly.time[i]] else { continue }
            let target = hourly.cloudCover.flatMap { i < $0.count ? $0[i] : nil }
            let scaled = OpenMeteoGapFill.scaledLayers(
                low: element(src.cloudCoverLow, j),
                mid: element(src.cloudCoverMid, j),
                high: element(src.cloudCoverHigh, j),
                total: element(src.cloudCover, j),
                target: target)
            if low[i] == nil { low[i] = scaled.low }
            if mid[i] == nil { mid[i] = scaled.mid }
            if high[i] == nil { high[i] = scaled.high }
        }

        hourly.cloudCoverLow = low
        hourly.cloudCoverMid = mid
        hourly.cloudCoverHigh = high
    }

    /// One complete Open-Meteo row, defaults already applied, ready to sit
    /// beside a Google hour. Only the temperature is required; the other
    /// defaults follow the yesterday row's conventions (feels-like falls back
    /// to the same hour's own air temperature, no code reads as overcast,
    /// amounts and winds read as zero) so a null never becomes a gap in a
    /// column that cannot express one.
    private nonisolated struct AppendedHour {
        let time: String
        let temperature: Double
        let humidity: Double
        let apparentTemperature: Double
        let precipitationProbability: Int
        let precipitation: Double
        let weatherCode: Int
        let windSpeed: Double
        let windDirection: Double
        let isDay: Int
        let cloudCover: Double?
        let dewPoint: Double?
        let visibility: Double?
        let cloudCoverLow: Double?
        let cloudCoverMid: Double?
        let cloudCoverHigh: Double?
    }

    /// Appends a full row for every Open-Meteo hour whose local label is not
    /// in the series, then puts the whole series back in ascending order with
    /// every column moved by the same permutation. Hours Google provided keep
    /// every value they had. With no Google hours at all the series becomes
    /// Open-Meteo's (yesterday plus ten days); a shorter Google horizon or a
    /// failed page is extended or bridged the same way.
    ///
    /// An hour without a temperature is not added: it is the row's headline
    /// number and every other column has an honest zero, but a temperature
    /// does not. Cloud layers for an appended hour are Open-Meteo's own,
    /// unscaled, since there is no Google total for that hour.
    ///
    /// The `[Double]?` columns (total cover, dew point, visibility) cannot
    /// mark a single hour unknown, and their readers already treat a column
    /// shorter than the time axis as unknown from its end. So each keeps the
    /// longest prefix of the reordered series for which every hour has a
    /// value, and a column absent while Google hours exist stays absent, the
    /// adapter's own rule for a column with a gap. An appended hour with a
    /// null amid hours that have values is bridged from the hour before it
    /// (the first hour from the one after), because Open-Meteo's yesterday
    /// sorts ahead of everything Google sent: one null there would otherwise
    /// end the column and drop every Google dew point and visibility from
    /// today on. A trailing null still ends the column, and a Google hour
    /// without a value still ends it where the adapter did.
    private nonisolated mutating func appendMissingHours(from src: OpenMeteoGapFill.Hourly,
                                                         realign: GapFillRealigner,
                                                         visibilityInFeet: Bool) {
        let old = hourly
        let count = old.time.count
        // Every plain column has to line up with the time axis before a row
        // can be appended to all of them at once; a series that does not is
        // left exactly as it is rather than indexed out of range.
        let plainCounts = [old.temperature.count, old.humidity.count, old.apparentTemperature.count,
                           old.precipitationProbability.count, old.precipitation.count,
                           old.weatherCode.count, old.windSpeed.count, old.windDirection.count,
                           old.isDay.count]
        guard plainCounts.allSatisfy({ $0 == count }) else { return }

        func element<T>(_ column: [T?]?, _ j: Int) -> T? {
            guard let column, j < column.count else { return nil }
            return column[j]
        }

        // On a fall-back night two Open-Meteo hours share one wall-clock
        // label; the later wins, as in fillCloudLayers and the adapter.
        let present = Set(old.time)
        var candidates: [String: Int] = [:]
        for (j, stamp) in src.time.enumerated() {
            guard let local = realign.dateTime(stamp), !present.contains(local),
                  element(src.temperature, j) != nil else { continue }
            candidates[local] = j
        }
        guard !candidates.isEmpty else { return }

        let added: [AppendedHour] = candidates.sorted { $0.key < $1.key }.map { label, j in
            let temperature = element(src.temperature, j) ?? 0
            let visibility = element(src.visibility, j).map { visibilityInFeet ? $0 * 0.3048 : $0 }
            return AppendedHour(
                time: label,
                temperature: temperature,
                humidity: element(src.humidity, j) ?? 0,
                apparentTemperature: element(src.apparentTemperature, j) ?? temperature,
                precipitationProbability: element(src.precipitationProbability, j) ?? 0,
                precipitation: element(src.precipitation, j) ?? 0,
                weatherCode: element(src.weatherCode, j) ?? 3,
                windSpeed: element(src.windSpeed, j) ?? 0,
                windDirection: element(src.windDirection, j) ?? 0,
                // Open-Meteo always sends is_day; daylight is the safer
                // default for the odd null, since it hides nothing.
                isDay: element(src.isDay, j) ?? 1,
                cloudCover: element(src.cloudCover, j),
                dewPoint: element(src.dewPoint, j),
                visibility: visibility,
                cloudCoverLow: element(src.cloudCoverLow, j),
                cloudCoverMid: element(src.cloudCoverMid, j),
                cloudCoverHigh: element(src.cloudCoverHigh, j))
        }

        // The merged order: Google's rows keep their relative order (a
        // repeated fall-back hour included), appended rows slot in by label.
        // ISO stamps sort as strings.
        enum Slot { case existing(Int), added(Int) }
        var slots: [(label: String, order: Int, slot: Slot)] = []
        slots.reserveCapacity(count + added.count)
        for (i, label) in old.time.enumerated() { slots.append((label, i, .existing(i))) }
        for (k, row) in added.enumerated() { slots.append((row.time, count + k, .added(k))) }
        slots.sort { ($0.label, $0.order) < ($1.label, $1.order) }

        func plain<T>(_ existing: [T], _ value: (AppendedHour) -> T) -> [T] {
            slots.map { slot in
                switch slot.slot {
                case .existing(let i): return existing[i]
                case .added(let k): return value(added[k])
                }
            }
        }
        func prefix(_ existing: [Double]?, _ value: (AppendedHour) -> Double?) -> [Double]? {
            if existing == nil, count > 0 { return nil }
            let values: [Double?] = slots.map { slot in
                switch slot.slot {
                case .existing(let i): return existing.flatMap { i < $0.count ? $0[i] : nil }
                case .added(let k): return value(added[k])
                }
            }
            let lastValued = values.lastIndex { $0 != nil } ?? -1
            var out: [Double] = []
            for (s, next) in values.enumerated() {
                if let next { out.append(next); continue }
                // A hole, not the end: only an Open-Meteo hour is bridged, and
                // only while a value still follows it.
                guard s < lastValued, case .added = slots[s].slot,
                      let standIn = out.last ?? values[(s + 1)...].compactMap({ $0 }).first
                else { break }
                out.append(standIn)
            }
            return out
        }
        func layer(_ existing: [Double?]?, _ value: (AppendedHour) -> Double?) -> [Double?] {
            slots.map { slot in
                switch slot.slot {
                case .existing(let i): return existing.flatMap { i < $0.count ? $0[i] : nil }
                case .added(let k): return value(added[k])
                }
            }
        }

        hourly.time = plain(old.time, \.time)
        hourly.temperature = plain(old.temperature, \.temperature)
        hourly.humidity = plain(old.humidity, \.humidity)
        hourly.apparentTemperature = plain(old.apparentTemperature, \.apparentTemperature)
        hourly.precipitationProbability = plain(old.precipitationProbability, \.precipitationProbability)
        hourly.precipitation = plain(old.precipitation, \.precipitation)
        hourly.weatherCode = plain(old.weatherCode, \.weatherCode)
        hourly.windSpeed = plain(old.windSpeed, \.windSpeed)
        hourly.windDirection = plain(old.windDirection, \.windDirection)
        hourly.isDay = plain(old.isDay, \.isDay)
        hourly.cloudCover = prefix(old.cloudCover, \.cloudCover)
        hourly.dewPoint = prefix(old.dewPoint, \.dewPoint)
        hourly.visibility = prefix(old.visibility, \.visibility)
        hourly.cloudCoverLow = layer(old.cloudCoverLow, \.cloudCoverLow)
        hourly.cloudCoverMid = layer(old.cloudCoverMid, \.cloudCoverMid)
        hourly.cloudCoverHigh = layer(old.cloudCoverHigh, \.cloudCoverHigh)
    }
}

/// Re-expresses Open-Meteo wall-clock strings in the response's zone by way
/// of the absolute instant, so two zone ids that differ still line up on the
/// same hour. Equal zone ids short-circuit to the identity, so a fall-back
/// night's repeated wall-clock hour arrives twice, exactly as Open-Meteo
/// wrote it; the splice decides which occurrence to keep.
nonisolated struct GapFillRealigner {
    private let identity: Bool
    private let parser: LocalTimeParser
    private let dateTimeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(from source: TimeZone, to target: TimeZone) {
        identity = source.identifier == target.identifier
        parser = LocalTimeParser(timezone: source)
        let dt = DateFormatter()
        dt.locale = Locale(identifier: "en_US_POSIX")
        dt.timeZone = target
        dt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dateTimeFormatter = dt
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = target
        d.dateFormat = "yyyy-MM-dd"
        dateFormatter = d
    }

    /// An hourly, 15-minute or sun-event stamp ("2026-09-08T15:00").
    func dateTime(_ stamp: String) -> String? {
        if identity { return stamp.isEmpty ? nil : stamp }
        guard let instant = parser.date(from: stamp) else { return nil }
        return dateTimeFormatter.string(from: instant)
    }

    /// A daily stamp ("2026-09-08"). A day is a label, not an instant, so it
    /// is carried across on its midday: midnight would slip to the previous
    /// date in any zone west of Open-Meteo's, while noon lands on the date
    /// the day mostly overlaps.
    func date(_ stamp: String) -> String? {
        if identity { return stamp.isEmpty ? nil : stamp }
        guard let midnight = parser.date(from: stamp) else { return nil }
        return dateFormatter.string(from: midnight.addingTimeInterval(12 * 3600))
    }
}
