//
//  WeatherService.swift
//  Weather
//
//  Fetches forecast + air quality from Open-Meteo and maps the wire format
//  (parallel arrays) into the app's domain models.
//

import Foundation

enum WeatherError: LocalizedError {
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

struct WeatherService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    func fetch(for place: Place,
               temperatureUnit: TemperatureUnit,
               speedUnit: SpeedUnit,
               precipUnit: PrecipUnit = .auto) async throws -> WeatherBundle {
        async let forecast = fetchForecast(place: place,
                                           temperatureUnit: temperatureUnit,
                                           speedUnit: speedUnit,
                                           precipUnit: precipUnit)
        async let air = try? fetchAirQuality(place: place)
        let (raw, tz) = try await forecast
        let aqi = await air ?? nil
        return try transform(raw: raw, place: place, timezone: tz, airQuality: aqi)
    }

    // MARK: - Forecast

    private func fetchForecast(place: Place,
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
                "wind_speed_10m", "wind_direction_10m", "uv_index", "is_day"
            ].joined(separator: ",")),
            .init(name: "daily", value: [
                "weather_code", "temperature_2m_max", "temperature_2m_min",
                "apparent_temperature_max", "apparent_temperature_min",
                "sunrise", "sunset", "uv_index_max", "precipitation_sum",
                "precipitation_probability_max", "wind_speed_10m_max",
                "wind_gusts_10m_max", "wind_direction_10m_dominant"
            ].joined(separator: ",")),
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
                           airQuality: AirQuality?) throws -> WeatherBundle {
        let parser = LocalTimeParser(timezone: timezone)

        // Current
        let c = raw.current
        let currentDate = parser.date(from: c.time) ?? Date()
        // Open-Meteo's hourly arrays begin at local midnight, so `uvIndex.first`
        // is the overnight value (always 0). Read the UV from the hourly sample
        // closest to the current time instead.
        let currentUV: Double? = {
            var best: (index: Int, delta: TimeInterval)?
            for (i, timeString) in raw.hourly.time.enumerated() {
                guard let t = parser.date(from: timeString) else { continue }
                let delta = abs(t.timeIntervalSince(currentDate))
                if best == nil || delta < best!.delta { best = (i, delta) }
            }
            if let best { return raw.hourly.uvIndex[safe: best.index] }
            return raw.hourly.uvIndex.first
        }()
        let current = CurrentWeather(
            date: currentDate,
            temperature: c.temperature,
            apparentTemperature: c.apparentTemperature,
            code: c.weatherCode,
            isDay: c.isDay == 1,
            humidity: c.humidity,
            precipitation: c.precipitation,
            cloudCover: c.cloudCover,
            pressure: c.pressure,
            windSpeed: c.windSpeed,
            windGust: c.windGust,
            windDirection: c.windDirection,
            uvIndex: currentUV,
            visibility: nil,
            dewPoint: nil
        )

        // Hourly
        let h = raw.hourly
        var hours: [HourPoint] = []
        for i in h.time.indices {
            guard let date = parser.date(from: h.time[i]) else { continue }
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

        // Daily
        let d = raw.daily
        var days: [DayForecast] = []
        for i in d.time.indices {
            guard let date = parser.date(from: d.time[i]) else { continue }
            days.append(DayForecast(
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
            ))
        }

        var resolvedPlace = place
        resolvedPlace.timezone = timezone.identifier

        return WeatherBundle(
            place: resolvedPlace,
            timezone: timezone,
            current: current,
            hourly: hours,
            daily: days,
            airQuality: airQuality,
            fetchedAt: Date()
        )
    }
}

// MARK: - Local time parsing

/// Open-Meteo returns local wall-clock times (e.g. "2026-06-04T15:00") without
/// an offset. We anchor them to the location's timezone to get absolute Dates.
struct LocalTimeParser {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
