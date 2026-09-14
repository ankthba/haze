//
//  WeatherService.swift
//  Weather
//
//  Fetches forecast + air quality from Open-Meteo and maps the wire format
//  (parallel arrays) into the app's domain models. When the user has chosen
//  Google WeatherNext, the forecast itself comes from WeatherNextService
//  (already shaped as a ForecastResponse) and only the mapping runs here.
//

import CoreLocation
import Foundation

nonisolated enum WeatherError: LocalizedError {
    case badURL
    case requestFailed
    case decodingFailed
    /// Anything that went wrong on the WeatherNext path: no key, a non-2xx
    /// answer, a transport error, an undecodable body. The reason is a full
    /// sentence built by `WeatherNextService.failureReason`, carrying what
    /// Google actually said (its JSON error body) so the user and the log see
    /// the cause, not a generic "couldn't reach".
    case weatherNextFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Couldn't build the request."
        case .requestFailed: return "Couldn't reach the weather service."
        case .decodingFailed: return "Received an unexpected response."
        case .weatherNextFailed(let reason): return reason
        }
    }
}

/// `nonisolated` on purpose: the app defaults to main-actor isolation, and
/// decoding a ten-day forecast and mapping its parallel arrays is real work that
/// has no business happening on the thread that's drawing.
nonisolated struct WeatherService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Everything the screen needs to draw. Air quality and station
    /// observations are deliberately *not* awaited here — they're a second
    /// service and a three-request chain respectively, and waiting on them used
    /// to hold the whole forecast off the screen. `fetchExtras` collects them
    /// afterwards and they're folded into the bundle when they land.
    ///
    /// `weatherNextMaxAge` is how old a stored Google snapshot may be and still
    /// be re-adapted instead of refetched (see WeatherNextRawCache). Unit
    /// changes and relaunches inside the refresh window then cost Google
    /// nothing, which matters because every hourly page counts against a
    /// per-day quota; 0 means the user asked for fresh numbers.
    func fetchForecast(for place: Place,
                       temperatureUnit: TemperatureUnit,
                       speedUnit: SpeedUnit,
                       precipUnit: PrecipUnit = .auto,
                       source: ForecastSource = .classic,
                       weatherNextMaxAge: TimeInterval = 15 * 60) async throws -> WeatherBundle {
        guard source == .weatherNext else {
            return try await fetchClassicForecast(place: place,
                                                  temperatureUnit: temperatureUnit,
                                                  speedUnit: speedUnit,
                                                  precipUnit: precipUnit)
        }
        do {
            // No NBM here: WeatherNext is already a calibrated blend, and
            // splicing NBM's numbers over it would mix two models into one
            // reading. The extras (air quality, station observation, alerts)
            // still arrive through fetchExtras regardless of source.
            let outcome = try await WeatherNextService(session: session)
                .fetchForecastResponse(place: place,
                                       temperatureUnit: temperatureUnit,
                                       speedUnit: speedUnit,
                                       precipUnit: precipUnit,
                                       maxAge: weatherNextMaxAge)
            // One Open-Meteo request follows, for what Google cannot supply
            // (the 15-minute nowcast, a pre-today daily row, the cloud layers,
            // elevation) and, since the hourly quota can run out on its own,
            // for any hour Google did not send: the fill appends those rows,
            // so a WeatherNext page with no hours from Google still has an
            // hourly strip. It never overwrites a Google value. It waits for
            // Google rather than riding alongside so a load that throws (and
            // falls back to another Open-Meteo request below) or is served
            // from the snapshot (whose fill is stored beside it) sends none;
            // Open-Meteo's rate limit has taken the whole app down before.
            // See OpenMeteoGapFill.swift.
            let fill = await OpenMeteoGapFill.load(place: place,
                                                   temperatureUnit: temperatureUnit,
                                                   speedUnit: speedUnit,
                                                   precipUnit: precipUnit,
                                                   maxAge: weatherNextMaxAge,
                                                   session: session)
            var raw = outcome.response
            if let fill { raw.applyGapFill(fill, timezone: outcome.timezone) }
            // Stamped with Google's answer time, not now: a page re-adapted
            // from the snapshot is as old as the snapshot, and the footer's
            // "Updated" line and the sidebar's freshness gate read this.
            var bundle = try transform(raw: raw, place: place, timezone: outcome.timezone,
                                       airQuality: nil, observedCode: nil,
                                       fetchedAt: outcome.fetchedAt)
            // Current and daily are Google's whenever this path returns, so
            // the attribution stays WeatherNext even when the hours were
            // borrowed; the notice (nil when nothing was borrowed) is what
            // tells the reader about the substitution, and it is composed
            // knowing whether the fill actually landed, so a page with no
            // hourly series never claims Open-Meteo supplied one.
            bundle.source = .weatherNext
            bundle.sourceNotice = WeatherNextService.Outcome.notice(
                googleHours: outcome.googleHours,
                hoursFailure: outcome.hoursFailure,
                fillApplied: fill != nil)
            return bundle
        } catch {
            // The source toggle must never take the forecast away. A rejected
            // key, a project without the API enabled, a Google outage: none of
            // these is a reason to show an error screen when Open-Meteo is a
            // request away. The page falls back to Classic Haze inside this
            // same load and carries Google's reason as `sourceNotice`, so the
            // attribution stays honest and Settings can say why. If Open-Meteo
            // fails too, that is the error worth showing.
            var bundle = try await fetchClassicForecast(place: place,
                                                        temperatureUnit: temperatureUnit,
                                                        speedUnit: speedUnit,
                                                        precipUnit: precipUnit)
            // The notice is printed verbatim by the views, so it has to say
            // both what happened and why, in that order.
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "Google WeatherNext could not be loaded."
            bundle.sourceNotice = "Google WeatherNext is unavailable, so this is Classic Haze. \(reason)"
            return bundle
        }
    }

    /// The Open-Meteo forecast with the NBM overlay: the classic path, and the
    /// safety net under WeatherNext. Shared so a fallback bundle is built the
    /// same way as one the user asked for.
    private func fetchClassicForecast(place: Place,
                                      temperatureUnit: TemperatureUnit,
                                      speedUnit: SpeedUnit,
                                      precipUnit: PrecipUnit) async throws -> WeatherBundle {
        // The NBM overlay rides alongside the main request and splices in the
        // numbers the calibrated blend does better (see NBMOverlay.swift);
        // outside its US coverage, or on any failure, nothing changes.
        async let overlay = NBMOverlay.fetch(place: place,
                                             temperatureUnit: temperatureUnit,
                                             speedUnit: speedUnit,
                                             precipUnit: precipUnit,
                                             session: session)
        let (fetched, tz) = try await fetchForecastResponse(place: place,
                                                            temperatureUnit: temperatureUnit,
                                                            speedUnit: speedUnit,
                                                            precipUnit: precipUnit)
        var raw = fetched
        if let nbm = await overlay { raw.applyNBM(nbm) }
        // After the overlay, so NBM's feet are converted with the rest.
        raw.normaliseVisibility(precipAPI: precipUnit.apiValue(temperatureUnit: temperatureUnit))
        var bundle = try transform(raw: raw, place: place, timezone: tz,
                                   airQuality: nil, observedCode: nil)
        bundle.source = .classic
        return bundle
    }

    struct Extras {
        let airQuality: AirQuality?
        /// The nearest station's live report (US). Models routinely miss a
        /// storm that's overhead *right now*, and their "current" hour is an
        /// analysis rather than a measurement, so the instrument wins for
        /// everything it actually measures. See StationObservation.swift.
        let observation: StationObservation?
        /// The observed condition, but only for *active* weather worth
        /// overriding the model's code for: a ceilometer judges "cloudy"
        /// from one column of sky, the model judges it from the whole area.
        let observedCode: Int?
        /// Active NWS advisories (US); nil when the fetch failed, empty when
        /// it succeeded and there are none — the difference matters, because
        /// an empty answer should clear a banner and a failure should not.
        let alerts: [WeatherAlert]?
        var isEmpty: Bool {
            airQuality == nil && observation == nil && observedCode == nil && alerts == nil
        }
    }

    func fetchExtras(for place: Place) async -> Extras {
        async let air = try? fetchAirQuality(place: place)
        async let observed = fetchObservation(place: place)
        async let alerts = fetchAlerts(place: place)
        let observation = await observed
        return Extras(airQuality: await air ?? nil,
                      observation: observation,
                      observedCode: observation.flatMap {
                          Self.activeCode(fromObservation: $0.textDescription ?? "")
                      },
                      alerts: await alerts)
    }

    // MARK: - Forecast

    private func fetchForecastResponse(place: Place,
                                       temperatureUnit: TemperatureUnit,
                                       speedUnit: SpeedUnit,
                                       precipUnit: PrecipUnit) async throws -> (ForecastResponse, TimeZone) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: [
                "temperature_2m", "relative_humidity_2m", "apparent_temperature",
                "is_day", "precipitation", "weather_code", "cloud_cover",
                "pressure_msl", "wind_speed_10m", "wind_direction_10m",
                "wind_gusts_10m"
            ].joined(separator: ",")),
            .init(name: "hourly", value: [
                "temperature_2m", "relative_humidity_2m", "apparent_temperature",
                "precipitation_probability", "precipitation", "weather_code",
                "wind_speed_10m", "wind_direction_10m", "is_day",
                "dew_point_2m", "visibility",
                // Layered cloud cover feeds the sunrise/sunset quality model:
                // high/mid clouds are the canvas the light paints, low clouds
                // are the wall that blocks it.
                "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high"
            ].joined(separator: ",")),
            .init(name: "daily", value: [
                "weather_code", "temperature_2m_max", "temperature_2m_min",
                "apparent_temperature_max", "apparent_temperature_min",
                "sunrise", "sunset", "precipitation_sum",
                "precipitation_probability_max", "wind_speed_10m_max",
                "wind_gusts_10m_max", "wind_direction_10m_dominant",
                "snowfall_sum"
            ].joined(separator: ",")),
            // 15-minute nowcast for "rain starting around…" (12 steps = 3 h),
            // and one past day for the yesterday comparison — both ride along
            // on this same single request; no extra Open-Meteo calls.
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "12"),
            .init(name: "past_days", value: "1"),
            .init(name: "temperature_unit", value: temperatureUnit.apiValue),
            .init(name: "wind_speed_unit", value: speedUnit.apiValue),
            .init(name: "precipitation_unit", value: precipUnit.apiValue(temperatureUnit: temperatureUnit)),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "10")
        ]

        guard let url = components?.url else { throw WeatherError.badURL }

        let data: Data
        do {
            let (d, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw WeatherError.requestFailed
            }
            data = d
        } catch let error as WeatherError {
            throw error
        } catch {
            throw WeatherError.requestFailed
        }

        do {
            let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
            let tz = TimeZone(identifier: decoded.timezone)
                ?? TimeZone(secondsFromGMT: decoded.utcOffsetSeconds)
                ?? .current
            return (decoded, tz)
        } catch {
            throw WeatherError.decodingFailed
        }
    }

    // MARK: - Current-conditions summary (for the "back to my location" panel)

    struct CurrentSummary {
        let temperature: Double
        let code: Int
        let isDay: Bool
    }

    /// A deliberately tiny request: current temperature + condition only, used
    /// to show the device location's weather while browsing another place and
    /// beside each place in the Mac sidebar. It follows the forecast source so
    /// those numbers agree with the page they sit next to. On WeatherNext,
    /// `maxAge` lets a stored snapshot's current conditions answer instead of
    /// a call, the same way the full forecast does.
    func fetchCurrentSummary(for place: Place,
                             temperatureUnit: TemperatureUnit,
                             source: ForecastSource = .classic,
                             maxAge: TimeInterval = 15 * 60) async throws -> CurrentSummary {
        if source == .weatherNext {
            // Same safety net as fetchForecast: a WeatherNext failure falls
            // through to Open-Meteo rather than blanking the sidebar number.
            // No notice here; the page it sits beside already carries one.
            if let current = try? await WeatherNextService(session: session)
                .fetchCurrentSummary(place: place, temperatureUnit: temperatureUnit, maxAge: maxAge) {
                return CurrentSummary(temperature: current.temperature, code: current.code, isDay: current.isDay)
            }
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: temperatureUnit.apiValue)
        ]
        guard let url = components?.url else { throw WeatherError.badURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.requestFailed
        }
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
            }
            let current: Current
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return CurrentSummary(temperature: decoded.current.temperature_2m,
                              code: decoded.current.weather_code,
                              isDay: decoded.current.is_day == 1)
    }

    // MARK: - Station observations (NWS, US only)

    /// One station, already measured against the place that asked for it.
    struct CachedStation {
        let url: String
        let id: String
        let name: String
        let distance: CLLocationDistance
    }

    /// Caches each location's sorted station list so repeat loads cost one
    /// request instead of three. The nearest stations to a point don't move.
    private actor StationCache {
        private var map: [String: [CachedStation]] = [:]
        func stations(for key: String) -> [CachedStation]? { map[key] }
        func set(_ stations: [CachedStation], for key: String) { map[key] = stations }
    }
    private static let stationCache = StationCache()
    /// How far down the list to walk before giving up. Enough to survive a
    /// station or two being offline, few enough to stay cheap.
    private static let maxStationsTried = 4

    /// The nearest usable station's live report. Nil outside the US, on any
    /// failure, when every nearby station is stale or too far, or when the
    /// station reports nothing we can trust.
    ///
    /// Three requests on a cold cache (gridpoint, station list, observation),
    /// one afterwards: the station list is cached per location, since the
    /// nearest station to you does not change.
    func fetchObservation(place: Place) async -> StationObservation? {
        let cc = place.countryCode?.uppercased()
        guard cc == nil || cc == "US" else { return nil }

        let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let key = String(format: "%.2f,%.2f", place.latitude, place.longitude)

        var candidates = await Self.stationCache.stations(for: key)
        if candidates == nil {
            struct Points: Decodable {
                struct Props: Decodable { let observationStations: String }
                let properties: Props
            }
            guard let pointsURL = URL(string:
                    "https://api.weather.gov/points/\(place.latitude),\(place.longitude)"),
                  let points: Points = await getNWS(pointsURL),
                  let stationsURL = URL(string: points.properties.observationStations),
                  let stations: NWSStationsResponse = await getNWS(stationsURL)
            else { return nil }

            // Sorted by true distance, not by the order the NWS happened to
            // return: the list is only roughly proximity-ordered, and taking
            // `features.first` on faith is how a station across the state
            // ends up supplying "your" current conditions.
            let sorted = stations.features.compactMap { feature -> CachedStation? in
                guard let coordinate = feature.coordinate else { return nil }
                let distance = here.distance(from: CLLocation(latitude: coordinate.latitude,
                                                              longitude: coordinate.longitude))
                guard distance <= StationObservation.maxDistance else { return nil }
                return CachedStation(
                    url: feature.id + "/observations/latest",
                    id: feature.properties.stationIdentifier
                        ?? String(feature.id.split(separator: "/").last ?? "Station"),
                    name: feature.properties.name ?? "",
                    distance: distance)
            }.sorted { $0.distance < $1.distance }

            await Self.stationCache.set(sorted, for: key)
            candidates = sorted
        }
        guard let candidates, !candidates.isEmpty else { return nil }

        // Walk outwards until one answers with something fresh. Stations go
        // offline for maintenance all the time, and the old code gave up on
        // the first one rather than asking the next.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        for station in candidates.prefix(Self.maxStationsTried) {
            guard let url = URL(string: station.url),
                  let response: NWSObservationResponse = await getNWS(url)
            else { continue }
            let p = response.properties
            guard let stamp = iso.date(from: p.timestamp) ?? isoPlain.date(from: p.timestamp),
                  Date().timeIntervalSince(stamp) < StationObservation.maxAge
            else { continue }

            let observation = StationObservation(
                stationID: station.id,
                stationName: station.name,
                distanceMeters: station.distance,
                observedAt: stamp,
                temperatureC: p.temperature?.trusted,
                apparentC: p.heatIndex?.trusted ?? p.windChill?.trusted,
                dewPointC: p.dewpoint?.trusted,
                humidityPercent: p.relativeHumidity?.trusted,
                windSpeedKPH: p.windSpeed?.asKPH,
                windGustKPH: p.windGust?.asKPH,
                windDirectionDegrees: p.windDirection?.trusted,
                // Sea level only: `barometricPressure` is the station's own
                // uncorrected reading and does not mean what the app's
                // pressure row says it means.
                pressurePa: p.seaLevelPressure?.trusted,
                visibilityMeters: p.visibility?.asMetres,
                textDescription: p.textDescription)

            // A report with no temperature and no condition text is not worth
            // showing as an observation; try the next station instead.
            guard observation.temperatureC != nil || observation.textDescription?.isEmpty == false
            else { continue }
            return observation
        }
        return nil
    }

    // MARK: - Active alerts (NWS, US only)

    /// The advisories in force at the place right now. Returns nil on failure
    /// or outside the US, [] when the NWS answers and nothing is active.
    /// Internal so the background check can ask for alerts *alone* instead of
    /// paying for the whole extras fetch.
    func fetchAlerts(place: Place) async -> [WeatherAlert]? {
        let cc = place.countryCode?.uppercased()
        guard cc == nil || cc == "US" else { return nil }

        struct AlertsResponse: Decodable {
            struct Feature: Decodable {
                let id: String
                let properties: Props
            }
            struct Props: Decodable {
                let event: String?
                let headline: String?
                let severity: String?
                let description: String?
                let instruction: String?
                let ends: String?
                let expires: String?
                let senderName: String?
            }
            let features: [Feature]
        }

        guard let url = URL(string:
                "https://api.weather.gov/alerts/active?point=\(place.latitude),\(place.longitude)"),
              let decoded: AlertsResponse = await getNWS(url)
        else { return nil }

        let iso = ISO8601DateFormatter()
        let now = Date()
        return decoded.features.compactMap { feature -> WeatherAlert? in
            let p = feature.properties
            guard let event = p.event else { return nil }
            let ends = (p.ends ?? p.expires).flatMap { iso.date(from: $0) }
            // NWS occasionally leaves expired alerts in the active feed briefly.
            if let ends, ends < now { return nil }
            return WeatherAlert(id: feature.id,
                                event: event,
                                headline: p.headline,
                                severity: p.severity ?? "Unknown",
                                details: p.description ?? "",
                                instruction: p.instruction,
                                ends: ends,
                                source: p.senderName ?? "National Weather Service")
        }
    }

    private func getNWS<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        // api.weather.gov requires an identifying User-Agent.
        request.setValue("HazeWeatherApp (github.com/ankthba/haze)",
                         forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Maps an NWS observation description to a WMO code, but only for active
    /// weather worth overriding the model for.
    static func activeCode(fromObservation text: String) -> Int? {
        let t = text.lowercased()
        if t.contains("thunder") { return 95 }
        if t.contains("freezing") { return 66 }
        if t.contains("sleet") || t.contains("ice pellets") { return 66 }
        if t.contains("snow") {
            if t.contains("heavy") { return 75 }
            if t.contains("light") { return 71 }
            return 73
        }
        if t.contains("drizzle") { return 53 }
        if t.contains("rain") || t.contains("showers") {
            if t.contains("heavy") { return 65 }
            if t.contains("light") { return 61 }
            return 63
        }
        if t.contains("fog") || t.contains("mist") { return 45 }
        return nil
    }

    // MARK: - Air quality

    private func fetchAirQuality(place: Place) async throws -> AirQuality? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide"),
            .init(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(AirQualityResponse.self, from: data)
        guard let aqi = decoded.current.usAQI else { return nil }
        return AirQuality(
            usAQI: Int(aqi.rounded()),
            pm25: decoded.current.pm25,
            pm10: decoded.current.pm10,
            ozone: decoded.current.ozone,
            no2: decoded.current.no2
        )
    }

    // MARK: - Transform

    /// `fetchedAt` is now for a fresh answer; the WeatherNext path passes its
    /// snapshot's clock so a re-adapted page is not stamped as new.
    private func transform(raw: ForecastResponse,
                           place: Place,
                           timezone: TimeZone,
                           airQuality: AirQuality?,
                           observedCode: Int? = nil,
                           fetchedAt: Date = Date()) throws -> WeatherBundle {
        let parser = LocalTimeParser(timezone: timezone)

        // Current
        let c = raw.current
        let currentDate = parser.date(from: c.time) ?? Date()
        // Parsed once and reused by both the current-hour lookup and the
        // hourly series: 240 date parses, not 480.
        let hourlyDates = raw.hourly.time.map { parser.date(from: $0) }
        // The hourly sample closest to the current time stands in for the
        // "current" variables Open-Meteo doesn't offer.
        let nearestHourIndex: Int? = {
            var best: (index: Int, delta: TimeInterval)?
            for (i, date) in hourlyDates.enumerated() {
                guard let date else { continue }
                let delta = abs(date.timeIntervalSince(currentDate))
                if best == nil || delta < best!.delta { best = (i, delta) }
            }
            return best?.index
        }()
        // The UV index is computed, not fetched (see UVIndex.swift): the sun's
        // height at this place and moment, under the cloud layers of the
        // nearest forecast hour.
        let elevation = raw.elevation ?? 0
        let h = raw.hourly
        func uvIndex(at date: Date, hour: Int?) -> Double {
            let clouds: (low: Double?, mid: Double?, high: Double?) =
                hour.map { Self.uvClouds(in: h, at: $0) } ?? (nil, nil, nil)
            return UVIndex.value(at: date, latitude: place.latitude, longitude: place.longitude,
                                 elevation: elevation,
                                 cloudLow: clouds.low, cloudMid: clouds.mid, cloudHigh: clouds.high)
        }
        let currentUV = uvIndex(at: currentDate, hour: nearestHourIndex)
        // Dew point and visibility have no "current" variable; the nearest
        // hourly sample is the honest stand-in.
        let currentDew = nearestHourIndex.flatMap { raw.hourly.dewPoint?[safe: $0] }
        let currentVisibility = nearestHourIndex.flatMap { raw.hourly.visibility?[safe: $0] }
        let current = CurrentWeather(
            date: currentDate,
            temperature: c.temperature,
            apparentTemperature: c.apparentTemperature,
            code: observedCode ?? c.weatherCode,
            isDay: c.isDay == 1,
            humidity: c.humidity,
            precipitation: c.precipitation,
            cloudCover: c.cloudCover,
            pressure: c.pressure,
            windSpeed: c.windSpeed,
            windGust: c.windGust,
            windDirection: c.windDirection,
            uvIndex: currentUV,
            visibility: currentVisibility,
            dewPoint: currentDew
        )

        // The request carries past_days=1 for the yesterday comparison, so the
        // hourly and daily arrays begin yesterday. The comparison numbers are
        // pulled out here, and everything the rest of the app sees is filtered
        // back to today-forward — exactly the shape it had before.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let todayStart = cal.startOfDay(for: currentDate)

        // Yesterday's temperature at this same hour, for the comparison line.
        let sameHourTarget = currentDate.addingTimeInterval(-24 * 3600)
        let sameHourTemp: Double? = {
            var best: (temp: Double, delta: TimeInterval)?
            for (i, date) in hourlyDates.enumerated() {
                guard let date, date < todayStart,
                      let temp = raw.hourly.temperature[safe: i] else { continue }
                let delta = abs(date.timeIntervalSince(sameHourTarget))
                if best == nil || delta < best!.delta { best = (temp, delta) }
            }
            return best.map(\.temp)
        }()

        // Hourly
        var hours: [HourPoint] = []
        hours.reserveCapacity(hourlyDates.count)
        // Each day's strongest hour, for the daily UV figure.
        var uvPeakByDay: [Date: Double] = [:]
        for i in h.time.indices {
            guard let date = hourlyDates[safe: i] ?? nil, date >= todayStart else { continue }
            let uv = uvIndex(at: date, hour: i)
            let day = cal.startOfDay(for: date)
            uvPeakByDay[day] = max(uvPeakByDay[day] ?? 0, uv)
            var point = HourPoint(
                date: date,
                temperature: h.temperature[safe: i] ?? 0,
                apparentTemperature: h.apparentTemperature[safe: i] ?? 0,
                code: h.weatherCode[safe: i] ?? 0,
                isDay: (h.isDay[safe: i] ?? 1) == 1,
                precipitationProbability: Double(h.precipitationProbability[safe: i] ?? 0),
                precipitation: h.precipitation[safe: i] ?? 0,
                windSpeed: h.windSpeed[safe: i] ?? 0,
                windDirection: h.windDirection[safe: i] ?? 0,
                humidity: h.humidity[safe: i] ?? 0,
                uvIndex: uv
            )
            point.cloudCoverLow = h.cloudCoverLow?[safe: i] ?? nil
            point.cloudCoverMid = h.cloudCoverMid?[safe: i] ?? nil
            point.cloudCoverHigh = h.cloudCoverHigh?[safe: i] ?? nil
            point.visibility = h.visibility?[safe: i]
            hours.append(point)
        }

        // Daily — the entry before today becomes the comparison record.
        let d = raw.daily
        var days: [DayForecast] = []
        var yesterday: YesterdayComparison?
        for i in d.time.indices {
            guard let date = parser.date(from: d.time[i]) else { continue }
            if date < todayStart {
                if let high = d.tempMax[safe: i], let low = d.tempMin[safe: i] {
                    yesterday = YesterdayComparison(high: high, low: low,
                                                   sameHourTemperature: sameHourTemp)
                }
                continue
            }
            var day = DayForecast(
                date: date,
                code: d.weatherCode[safe: i] ?? 0,
                tempMax: d.tempMax[safe: i] ?? 0,
                tempMin: d.tempMin[safe: i] ?? 0,
                apparentMax: d.apparentMax[safe: i] ?? 0,
                apparentMin: d.apparentMin[safe: i] ?? 0,
                sunrise: parser.date(from: d.sunrise[safe: i] ?? ""),
                sunset: parser.date(from: d.sunset[safe: i] ?? ""),
                uvIndexMax: uvPeakByDay[cal.startOfDay(for: date)] ?? 0,
                precipitationSum: d.precipitationSum[safe: i] ?? 0,
                precipitationProbabilityMax: Double(d.precipitationProbabilityMax[safe: i] ?? 0),
                windSpeedMax: d.windSpeedMax[safe: i] ?? 0,
                windGustMax: d.windGustMax[safe: i] ?? 0,
                windDirectionDominant: d.windDirectionDominant[safe: i] ?? 0
            )
            day.snowfallSum = d.snowfallSum?[safe: i]
            days.append(day)
        }

        // 15-minute nowcast steps, where the model covers this location.
        let minutely: [MinutePoint]? = raw.minutely15.map { m in
            var points: [MinutePoint] = []
            points.reserveCapacity(m.time.count)
            for i in m.time.indices {
                guard let date = parser.date(from: m.time[i]),
                      let precip = m.precipitation[safe: i] else { continue }
                points.append(MinutePoint(date: date, precipitation: precip))
            }
            return points
        }

        var resolvedPlace = place
        resolvedPlace.timezone = timezone.identifier

        var bundle = WeatherBundle(
            place: resolvedPlace,
            timezone: timezone,
            current: current,
            hourly: hours,
            daily: days,
            airQuality: airQuality,
            fetchedAt: fetchedAt
        )
        bundle.minutely = minutely
        bundle.yesterday = yesterday
        return bundle
    }
}

// MARK: - Visibility unit

extension ForecastResponse {
    /// Open-Meteo (and NBM with it) switches hourly visibility to feet
    /// whenever the precipitation unit is "inch", and nothing in the payload
    /// says so; Fmt.visibility and SunQuality read metres. The classic path
    /// calls this after the overlay so every bundle carries metres whatever
    /// the source (the WeatherNext adapter and the gap fill already do).
    nonisolated mutating func normaliseVisibility(precipAPI: String) {
        guard precipAPI == "inch", let feet = hourly.visibility else { return }
        hourly.visibility = feet.map { $0 * 0.3048 }
    }
}

// MARK: - UV cloud input

extension WeatherService {
    /// The cloud layers the UV model reads for one forecast hour. UVIndex
    /// counts a missing layer as clear, which is right on the classic path
    /// (Open-Meteo always sends the layers) and wrong under WeatherNext
    /// whenever the gap fill could not supply them: a failed or rate-limited
    /// Open-Meteo call, an hour no fill hour lined up with, or a sky
    /// Open-Meteo did not see. Google's total cover is known for that hour
    /// regardless, so when every layer is unknown the total stands in as one
    /// opaque deck rather than letting an overcast hour read as clear-sky UV.
    nonisolated static func uvClouds(in hourly: ForecastResponse.Hourly,
                                     at index: Int) -> (low: Double?, mid: Double?, high: Double?) {
        let low = hourly.cloudCoverLow?[safe: index] ?? nil
        let mid = hourly.cloudCoverMid?[safe: index] ?? nil
        let high = hourly.cloudCoverHigh?[safe: index] ?? nil
        if low == nil, mid == nil, high == nil {
            return (hourly.cloudCover?[safe: index], nil, nil)
        }
        return (low, mid, high)
    }
}

// MARK: - Local time parsing

/// Open-Meteo returns local wall-clock times (e.g. "2026-06-04T15:00") without
/// an offset. We anchor them to the location's timezone to get absolute Dates.
nonisolated struct LocalTimeParser {
    private let dateTimeFormatter: DateFormatter
    private let dateOnlyFormatter: DateFormatter

    init(timezone: TimeZone) {
        let dt = DateFormatter()
        dt.locale = Locale(identifier: "en_US_POSIX")
        dt.timeZone = timezone
        dt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dateTimeFormatter = dt

        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = timezone
        d.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter = d
    }

    /// Open-Meteo hourly/sunrise values include a time ("…T15:00"); daily values
    /// are date-only ("2026-06-04"). Try both so neither silently drops.
    func date(from string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        return dateTimeFormatter.date(from: string) ?? dateOnlyFormatter.date(from: string)
    }
}

nonisolated private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
