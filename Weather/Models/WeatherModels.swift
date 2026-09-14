//
//  WeatherModels.swift
//  Weather
//
//  Domain + wire models. Data is sourced from Open-Meteo, a free aggregator
//  that blends national weather models (ECMWF, GFS, ICON, etc.) — chosen for
//  accuracy and because it needs no API key.
//

import Foundation

// MARK: - Units

nonisolated enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var apiValue: String { self == .fahrenheit ? "fahrenheit" : "celsius" }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    var short: String { self == .fahrenheit ? "F" : "C" }
}

nonisolated enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
    case mph, kmh, ms
    var id: String { rawValue }
    var apiValue: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "kmh"
        case .ms: return "ms"
        }
    }
    var label: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        case .ms: return "m/s"
        }
    }
}

// MARK: - Place

nonisolated struct Place: Codable, Identifiable, Hashable {
    var id: String { "\(latitude.rounded(to: 3)),\(longitude.rounded(to: 3))" }
    let name: String
    let admin1: String?
    let country: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    var timezone: String?

    var subtitle: String {
        [admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var flag: String {
        guard let code = countryCode, code.count == 2 else { return "" }
        return code.uppercased().unicodeScalars.reduce("") { acc, scalar in
            acc + String(UnicodeScalar(127397 + scalar.value)!)
        }
    }
}

nonisolated private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}

// MARK: - Bundle (decoded + transformed forecast)

nonisolated struct WeatherBundle: Codable {
    let place: Place
    let timezone: TimeZone
    /// The reading exactly as it was fetched. Almost nothing should read this
    /// directly — use `current`, which advances a stale one to the wall clock.
    ///
    /// The bug that made this private: a cached bundle is served for up to 24
    /// hours (WeatherCache.maxAge), and `upcomingHours` recomputes its window
    /// against `Date()` every time it is read, while this value stays frozen
    /// at `fetchedAt`. Open the app on a hot afternoon with a bundle fetched
    /// that morning and the hero said 83° beside an hourly strip whose "Now"
    /// column said 98°, with the brief (which also reads the current reading)
    /// wrong in the same direction. Both halves were behaving as written;
    /// only one of them tracked the clock.
    private let fetchedCurrent: CurrentWeather
    let hourly: [HourPoint]
    let daily: [DayForecast]
    let airQuality: AirQuality?
    let fetchedAt: Date
    // Optional so cache entries written before these features decode cleanly.
    /// Next ~3 h of 15-minute precipitation, where the nowcast model covers.
    var minutely: [MinutePoint]?
    /// Yesterday's numbers for the comparison line.
    var yesterday: YesterdayComparison?
    /// Active NWS advisories (US), delivered with the extras.
    var alerts: [WeatherAlert]?
    /// Which forecast pipeline produced these numbers. The attribution at the
    /// foot of the page follows this, not the current preference, so a switch
    /// never credits one model for the other's figures. Nil in cache entries
    /// written before the field existed; those were all Open-Meteo.
    var source: ForecastSource?
    /// Why the page differs from the WeatherNext choice, as complete sentences
    /// the views print verbatim (under the attribution line and in Settings,
    /// with no prefix of their own). Two shapes: a partial substitution, where
    /// `source` is still `.weatherNext` because current and daily are Google's
    /// but the hours came from Open-Meteo (the hourly quota is per day and
    /// runs out on its own); or a full fallback, where `source` is `.classic`
    /// because the WeatherNext fetch failed and Open-Meteo answered inside the
    /// same load. Either way the text carries Google's own reason so the
    /// reader can fix the cause (a key restriction, a spent quota). Nil
    /// whenever the page is exactly the source the user asked for.
    var sourceNotice: String?
    /// The station whose live report supplied the current reading, when one
    /// did. Nil means the hero is model output — which is always the case
    /// outside the US, and inside it whenever no nearby station answered.
    /// Optional so cache entries written before observations decode cleanly.
    var observation: StationObservation?

    var attributionLine: String { (source ?? .classic).attributionLine }

    /// How old the fetch may be before the hero stops being "now" and the
    /// hourly series takes over. Comfortably longer than the refresh interval,
    /// so an ordinary reading is never second-guessed.
    static let currentFreshness: TimeInterval = 45 * 60

    /// The conditions to show as "now". Normally the fetched reading; once
    /// that has aged past `currentFreshness`, the forecast for the current
    /// hour instead, which is both the better estimate and the number the
    /// hourly strip is already showing.
    var current: CurrentWeather {
        guard isCurrentStale, let hour = hourNearestNow else { return fetchedCurrent }
        return fetchedCurrent.advanced(to: hour)
    }

    /// True when the fetched reading is too old to stand as "now".
    var isCurrentStale: Bool {
        Date().timeIntervalSince(fetchedAt) > Self.currentFreshness
    }

    /// The forecast hour bracketing the wall clock. Nil when the series does
    /// not reach the present at all (a bundle old enough that its hours have
    /// run out), in which case there is nothing better than what was fetched.
    private var hourNearestNow: HourPoint? {
        let now = Date()
        guard let nearest = hourly.min(by: {
            abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
        }), abs(nearest.date.timeIntervalSince(now)) < 90 * 60 else { return nil }
        return nearest
    }

    /// A station report is only worth crediting while it is still recent. Once
    /// the page has fallen back to the hourly series the numbers are no longer
    /// the instrument's, so the provenance line must not claim they are.
    var displayedObservation: StationObservation? {
        isCurrentStale ? nil : observation
    }

    /// Hours from "now" forward, for the scrolling hourly strip.
    var upcomingHours: [HourPoint] {
        let now = Date()
        let start = hourly.firstIndex { $0.date >= now.addingTimeInterval(-3600) } ?? 0
        return Array(hourly[start...].prefix(24))
    }

    var today: DayForecast? { daily.first }

    /// Spelled out rather than synthesised: the stored reading is private, so
    /// the memberwise init would have taken `fetchedCurrent:` and every caller
    /// would have had to learn the distinction. They shouldn't have to.
    init(place: Place, timezone: TimeZone, current: CurrentWeather,
         hourly: [HourPoint], daily: [DayForecast], airQuality: AirQuality?,
         fetchedAt: Date) {
        self.place = place
        self.timezone = timezone
        self.fetchedCurrent = current
        self.hourly = hourly
        self.daily = daily
        self.airQuality = airQuality
        self.fetchedAt = fetchedAt
    }

    /// `current` on the wire, so bundles cached before this split still decode.
    enum CodingKeys: String, CodingKey {
        case place, timezone, hourly, daily, airQuality, fetchedAt
        case fetchedCurrent = "current"
        case minutely, yesterday, alerts, source, sourceNotice, observation
    }

    /// The forecast is shown the moment it lands; air quality, the nearest
    /// station's observation, and active alerts arrive on their own schedule
    /// and are folded in here, so a slow secondary service never holds up the
    /// screen.
    /// The reading with the extras folded in. When a station observation is
    /// present it replaces every value the instrument actually measured (see
    /// StationObservation.swift); without one, an observed code alone still
    /// overrides the modeled condition, as before.
    func applying(airQuality newAirQuality: AirQuality?,
                  observation newObservation: StationObservation?,
                  observedCode: Int?,
                  alerts newAlerts: [WeatherAlert]?,
                  temperatureUnit: TemperatureUnit,
                  speedUnit: SpeedUnit) -> WeatherBundle {
        // Trust is all-or-nothing: a report that fails the plausibility check
        // is dropped entirely rather than half-applied, and the page then says
        // nothing about a station instead of crediting one for model numbers.
        let trusted = newObservation.flatMap {
            $0.isPlausible(against: current, temperatureUnit: temperatureUnit) ? $0 : nil
        }
        let updatedCurrent: CurrentWeather
        if let trusted {
            updatedCurrent = trusted.applied(to: current,
                                             observedCode: observedCode,
                                             temperatureUnit: temperatureUnit,
                                             speedUnit: speedUnit)
        } else {
            updatedCurrent = observedCode.map(current.withCode) ?? current
        }
        var enriched = WeatherBundle(
            place: place,
            timezone: timezone,
            current: updatedCurrent,
            hourly: hourly,
            daily: daily,
            airQuality: newAirQuality ?? airQuality,
            fetchedAt: fetchedAt
        )
        enriched.minutely = minutely
        enriched.yesterday = yesterday
        enriched.alerts = newAlerts ?? alerts
        enriched.source = source
        enriched.sourceNotice = sourceNotice
        enriched.observation = trusted ?? observation
        return enriched
    }

    /// All hourly points falling on the same calendar day as `date`, in the
    /// location's timezone. Empty for days outside the hourly forecast window.
    func hours(on date: Date) -> [HourPoint] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return hourly.filter { cal.isDate($0.date, inSameDayAs: date) }
    }
}

nonisolated struct CurrentWeather: Codable {
    let date: Date
    let temperature: Double
    let apparentTemperature: Double
    let code: Int
    let isDay: Bool
    let humidity: Double
    let precipitation: Double
    let cloudCover: Double
    let pressure: Double
    let windSpeed: Double
    let windGust: Double
    let windDirection: Double
    let uvIndex: Double?
    let visibility: Double?
    let dewPoint: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }

    /// This reading moved forward onto a forecast hour, for when the fetch has
    /// aged out (see `WeatherBundle.current`). Everything the hour measures
    /// comes from the hour; pressure and gust, which it doesn't carry, are
    /// left as fetched because both drift slowly. The dew point is recomputed
    /// from the hour's own temperature and humidity rather than carried over,
    /// since a stale dew point beside a fresh temperature is exactly the kind
    /// of disagreement this is meant to end.
    func advanced(to hour: HourPoint) -> CurrentWeather {
        CurrentWeather(
            date: hour.date,
            temperature: hour.temperature,
            apparentTemperature: hour.apparentTemperature,
            code: hour.code,
            isDay: hour.isDay,
            humidity: hour.humidity,
            precipitation: hour.precipitation,
            cloudCover: hour.cloudCoverTotal ?? cloudCover,
            pressure: pressure,
            windSpeed: hour.windSpeed,
            windGust: max(windGust, hour.windSpeed),
            windDirection: hour.windDirection,
            uvIndex: hour.uvIndex,
            visibility: hour.visibility ?? visibility,
            dewPoint: Self.dewPoint(temperature: hour.temperature,
                                    humidity: hour.humidity)
        )
    }

    /// Magnus-Tetens, in whichever unit the temperature arrived in. The
    /// coefficients are defined in Celsius, so a Fahrenheit reading is
    /// converted in and back out.
    static func dewPoint(temperature: Double, humidity: Double) -> Double {
        // Above 100 °C the input is certainly Fahrenheit; below it, ambiguous
        // temperatures are equally valid in either, so the caller's unit is
        // inferred from the app-wide setting instead of guessed here.
        let usesFahrenheit = Fmt.temperatureUnitIsFahrenheit
        let celsius = usesFahrenheit ? (temperature - 32) * 5 / 9 : temperature
        let rh = min(max(humidity, 1), 100)
        let a = 17.625, b = 243.04
        let alpha = log(rh / 100) + (a * celsius) / (b + celsius)
        let dewC = (b * alpha) / (a - alpha)
        return usesFahrenheit ? dewC * 9 / 5 + 32 : dewC
    }

    /// The same reading with the condition code replaced — used when a station
    /// observation arrives after the forecast and overrides the modeled code.
    func withCode(_ newCode: Int) -> CurrentWeather {
        CurrentWeather(date: date, temperature: temperature,
                       apparentTemperature: apparentTemperature, code: newCode,
                       isDay: isDay, humidity: humidity, precipitation: precipitation,
                       cloudCover: cloudCover, pressure: pressure, windSpeed: windSpeed,
                       windGust: windGust, windDirection: windDirection,
                       uvIndex: uvIndex, visibility: visibility, dewPoint: dewPoint)
    }
}

/// Hours and days are identified by their own timestamp rather than a fresh
/// UUID: a refresh then re-renders the rows that actually changed instead of
/// rebuilding every one of them.
nonisolated struct HourPoint: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let temperature: Double
    let apparentTemperature: Double
    let code: Int
    let isDay: Bool
    let precipitationProbability: Double
    let precipitation: Double
    let windSpeed: Double
    let windDirection: Double
    let humidity: Double
    let uvIndex: Double
    // Optional (and `var`) so cache entries from before these fields decode.
    /// Layered cloud cover (%) for the sunrise/sunset quality model.
    /// The layers combined into one "how much sky is covered" figure, by the
    /// random-overlap rule forecasters use: each layer hides a fraction of
    /// what is left above it. Nil when the hour carries no layer at all, so
    /// the caller can fall back rather than read an absent sky as clear.
    var cloudCoverTotal: Double? {
        let layers = [cloudCoverLow, cloudCoverMid, cloudCoverHigh].compactMap { $0 }
        guard !layers.isEmpty else { return nil }
        let clear = layers.reduce(1.0) { $0 * (1 - min(max($1, 0), 100) / 100) }
        return (1 - clear) * 100
    }

    var cloudCoverLow: Double?
    var cloudCoverMid: Double?
    var cloudCoverHigh: Double?
    /// Metres; same source as the current-conditions visibility.
    var visibility: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }
}

nonisolated struct DayForecast: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let code: Int
    let tempMax: Double
    let tempMin: Double
    let apparentMax: Double
    let apparentMin: Double
    let sunrise: Date?
    let sunset: Date?
    let uvIndexMax: Double
    let precipitationSum: Double
    let precipitationProbabilityMax: Double
    let windSpeedMax: Double
    let windGustMax: Double
    let windDirectionDominant: Double
    /// Optional (and `var`) so cache entries from before this field decode.
    /// Centimetres in metric mode, inches in imperial.
    var snowfallSum: Double?

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: true) }
}

/// One 15-minute precipitation step from the nowcast model — the resolution
/// behind "rain starting around 3:40".
nonisolated struct MinutePoint: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    /// Precipitation over the step, in the request's precipitation unit.
    let precipitation: Double
}

/// Yesterday's reading, kept only as the few numbers the comparison line needs.
nonisolated struct YesterdayComparison: Codable {
    let high: Double
    let low: Double
    /// Yesterday's temperature at (roughly) the current hour, for
    /// "4° warmer than this time yesterday".
    let sameHourTemperature: Double?
}

/// An active advisory from the National Weather Service (US only).
nonisolated struct WeatherAlert: Codable, Identifiable, Equatable {
    let id: String
    let event: String          // "Tornado Warning"
    let headline: String?
    let severity: String       // Extreme | Severe | Moderate | Minor | Unknown
    let details: String
    let instruction: String?
    let ends: Date?
    let source: String         // "NWS Norman OK"

    /// Warnings and watches outrank advisories visually.
    var isUrgent: Bool {
        severity == "Extreme" || severity == "Severe"
    }
}

nonisolated struct AirQuality: Codable {
    let usAQI: Int
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
    let no2: Double?

    var category: AQICategory { AQICategory(aqi: usAQI) }
}

nonisolated enum AQICategory: String {
    case good = "Good"
    case moderate = "Moderate"
    case sensitive = "Unhealthy for Sensitive Groups"
    case unhealthy = "Unhealthy"
    case veryUnhealthy = "Very Unhealthy"
    case hazardous = "Hazardous"

    init(aqi: Int) {
        switch aqi {
        case ..<51: self = .good
        case 51..<101: self = .moderate
        case 101..<151: self = .sensitive
        case 151..<201: self = .unhealthy
        case 201..<301: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    var short: String {
        switch self {
        case .sensitive: return "Sensitive"
        case .veryUnhealthy: return "Very Bad"
        default: return rawValue
        }
    }
}
