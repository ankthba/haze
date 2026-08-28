//
//  WeatherService.swift
//  Weather
//
//  Fetches forecast + air quality from Open-Meteo and maps the wire format
//  (parallel arrays) into the app's domain models.
//

import Foundation

nonisolated enum WeatherError: LocalizedError {
    case badURL
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "Couldn't build the request."
        case .requestFailed: return "Couldn't reach the weather service."
        case .decodingFailed: return "Received an unexpected response."
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
    func fetchForecast(for place: Place,
                       temperatureUnit: TemperatureUnit,
                       speedUnit: SpeedUnit,
                       precipUnit: PrecipUnit = .auto) async throws -> WeatherBundle {
        let (raw, tz) = try await fetchForecastResponse(place: place,
                                                        temperatureUnit: temperatureUnit,
                                                        speedUnit: speedUnit,
                                                        precipUnit: precipUnit)
        return try transform(raw: raw, place: place, timezone: tz,
                             airQuality: nil, observedCode: nil)
    }

    struct Extras {
        let airQuality: AirQuality?
        /// A real station observation (US): forecast models routinely miss a
        /// storm that's overhead *right now*, so an observed active-weather
        /// condition overrides the modeled current code.
        let observedCode: Int?
        /// Active NWS advisories (US); nil when the fetch failed, empty when
        /// it succeeded and there are none — the difference matters, because
        /// an empty answer should clear a banner and a failure should not.
        let alerts: [WeatherAlert]?
        var isEmpty: Bool { airQuality == nil && observedCode == nil && alerts == nil }
    }

    func fetchExtras(for place: Place) async -> Extras {
        async let air = try? fetchAirQuality(place: place)
        async let observed = fetchObservedCode(place: place)
        async let alerts = fetchAlerts(place: place)
        return Extras(airQuality: await air ?? nil,
                      observedCode: await observed,
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
                "wind_speed_10m", "wind_direction_10m", "uv_index", "is_day",
                "dew_point_2m", "visibility"
            ].joined(separator: ",")),
            .init(name: "daily", value: [
                "weather_code", "temperature_2m_max", "temperature_2m_min",
                "apparent_temperature_max", "apparent_temperature_min",
                "sunrise", "sunset", "uv_index_max", "precipitation_sum",
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
    /// to show the device location's weather while browsing another place.
    func fetchCurrentSummary(for place: Place,
                             temperatureUnit: TemperatureUnit) async throws -> CurrentSummary {
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

    /// Caches each location's nearest-station observations URL so repeat loads
    /// cost one request instead of three.
    private actor StationCache {
        private var map: [String: String] = [:]
        func url(for key: String) -> String? { map[key] }
        func set(_ url: String, for key: String) { map[key] = url }
    }
    private static let stationCache = StationCache()

    /// The latest real observation near the place, mapped to a WMO-style code.
    /// Returns nil outside the US, on any failure, when the report is stale,
    /// or when it shows nothing *active* (clear/cloudy states stay with the
    /// model, which judges cloud cover better than a single station).
    private func fetchObservedCode(place: Place) async -> Int? {
        let cc = place.countryCode?.uppercased()
        guard cc == nil || cc == "US" else { return nil }

        let key = String(format: "%.2f,%.2f", place.latitude, place.longitude)
        var obsURLString = await Self.stationCache.url(for: key)

        if obsURLString == nil {
            struct Points: Decodable {
                struct Props: Decodable { let observationStations: String }
                let properties: Props
            }
            struct Stations: Decodable {
                struct Feature: Decodable { let id: String }
                let features: [Feature]
            }
            guard let pointsURL = URL(string:
                    "https://api.weather.gov/points/\(place.latitude),\(place.longitude)"),
                  let points: Points = await getNWS(pointsURL),
                  let stationsURL = URL(string: points.properties.observationStations),
                  let stations: Stations = await getNWS(stationsURL),
                  let station = stations.features.first
            else { return nil }
            obsURLString = station.id + "/observations/latest"
            await Self.stationCache.set(obsURLString!, for: key)
        }

        struct Observation: Decodable {
            struct Props: Decodable {
                let timestamp: String
                let textDescription: String?
            }
            let properties: Props
        }
        guard let obsURL = URL(string: obsURLString!),
              let observation: Observation = await getNWS(obsURL)
        else { return nil }

        // Ignore stale reports; stations file extra reports during storms, so
        // active weather is almost always fresh.
        let iso = ISO8601DateFormatter()
        guard let stamp = iso.date(from: observation.properties.timestamp),
              Date().timeIntervalSince(stamp) < 90 * 60
        else { return nil }

        return Self.activeCode(fromObservation: observation.properties.textDescription ?? "")
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

    private func transform(raw: ForecastResponse,
                           place: Place,
                           timezone: TimeZone,
                           airQuality: AirQuality?,
                           observedCode: Int? = nil) throws -> WeatherBundle {
        let parser = LocalTimeParser(timezone: timezone)

        // Current
        let c = raw.current
        let currentDate = parser.date(from: c.time) ?? Date()
        // Parsed once and reused by both the UV lookup and the hourly series —
        // 240 date parses, not 480.
        let hourlyDates = raw.hourly.time.map { parser.date(from: $0) }
        // Open-Meteo's hourly arrays begin at local midnight, so `uvIndex.first`
        // is the overnight value (always 0). Read the UV from the hourly sample
        // closest to the current time instead.
        let nearestHourIndex: Int? = {
            var best: (index: Int, delta: TimeInterval)?
            for (i, date) in hourlyDates.enumerated() {
                guard let date else { continue }
                let delta = abs(date.timeIntervalSince(currentDate))
                if best == nil || delta < best!.delta { best = (i, delta) }
            }
            return best?.index
        }()
        let currentUV = nearestHourIndex.flatMap { raw.hourly.uvIndex[safe: $0] }
            ?? raw.hourly.uvIndex.first
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
        let h = raw.hourly
        var hours: [HourPoint] = []
        hours.reserveCapacity(hourlyDates.count)
        for i in h.time.indices {
            guard let date = hourlyDates[safe: i] ?? nil, date >= todayStart else { continue }
            hours.append(HourPoint(
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
                uvIndex: h.uvIndex[safe: i] ?? 0
            ))
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
                uvIndexMax: d.uvIndexMax[safe: i] ?? 0,
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
            fetchedAt: Date()
        )
        bundle.minutely = minutely
        bundle.yesterday = yesterday
        return bundle
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
