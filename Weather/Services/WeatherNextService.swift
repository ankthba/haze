//
//  WeatherNextService.swift
//  Weather
//
//  WeatherNext is Google DeepMind's machine-learned forecast model. Google
//  exposes it to apps only through the Maps Platform Weather API, so this file
//  speaks that API (current conditions, hourly and daily forecasts, a day of
//  history) and then reshapes the answer into the exact Open-Meteo-shaped
//  `ForecastResponse` the rest of Haze already consumes: same field names,
//  same local wall-clock time strings, same units. Nothing downstream of
//  `WeatherService.transform` knows which source the numbers came from.
//
//  Cost shape: the hours endpoint caps a page at 24 records, so a full 240 h
//  forecast is ten sequential pages, plus one call each for current, days and
//  history, about 13 calls per refresh. Google gives 10,000 free calls a month
//  and charges $0.15 per 1,000 after that, which is why this source is opt-in
//  and keyed rather than the default.
//
//  Four things Open-Meteo supplies and Google does not: a 15-minute nowcast,
//  a daily row before today (Google keeps 24 h of history, enough for "this
//  time yesterday" but not yesterday's high and low), the low, mid and high
//  cloud layers, and the elevation. Under WeatherNext one slim Open-Meteo
//  request (OpenMeteoGapFill.swift, applied in WeatherService.fetchForecast)
//  follows the Google answer and splices those in, the layers scaled so they
//  agree with Google's total cover; this adapter only leaves the slots. Google's
//  condition enum also has no fog type, so fog is derived here from its own
//  hourly visibility and dew point (see `fogCode`).
//
//  Two shapes need translating rather than copying. Google's hourly intervals
//  start on the UTC hour, so in a half-hour zone every record straddles two
//  local hours; each is filed under the local hour that holds its midpoint,
//  because the app labels and keys hours without minutes. And Google's daily
//  rows run 7 am to 7 am with day and night halves, where Open-Meteo's cover
//  the calendar day: the daily highs, lows and sums are therefore rebuilt from
//  the hourly series wherever it covers the whole calendar day, and Google's
//  own 7-to-7 figures stand in only where it does not (today, if the history
//  call failed).
//
//  Quota: Google meters the hours endpoint per PAGE and per DAY, so one full
//  refresh spends ten of that allowance and a busy day of unit flips and
//  relaunches ran it dry (429 RESOURCE_EXHAUSTED). Three defences. The raw
//  Google answers for each place are kept on disk (`RawSnapshot`, stored by
//  WeatherNextRawCache) and, inside the refresh window, re-adapted with zero
//  calls: the adapter converts from METRIC locally, so a unit change or a
//  relaunch never needs the network. A 429 on an endpoint is remembered
//  (WeatherNextQuota, per day until midnight Pacific, when Google resets) and
//  that endpoint is skipped without a round trip until then. And the load
//  degrades rather than fails: current and days are required, but the hours
//  chain and history are optional, so when only the hourly quota is gone the
//  page stays on WeatherNext with Google's current and daily figures while
//  the gap fill supplies the hourly series, and `Outcome.notice` says so.
//
//  Failure: every way a call can fail (no key, a non-2xx answer, a transport
//  error, an unreadable body) surfaces as `WeatherError.weatherNextFailed`
//  carrying Google's own reason, never a generic error. WeatherService then
//  falls back to the classic path for that load and shows the reason, so a
//  key restriction or an unenabled API costs the user a notice, not the
//  forecast. Log lines carry the endpoint path only; the URL's query holds
//  the key.
//
//  Attribution: Google requires the phrase "Includes weather data from Google"
//  to appear verbatim and visibly near the top or bottom of any content that
//  shows this data. `ForecastSource.attributionLine` carries it; screens that
//  draw WeatherNext numbers must show that line.
//

import Foundation
import os

// MARK: - Source selection

/// Which forecast pipeline feeds the app. Persisted by the view model and
/// offered in Settings; `.weatherNext` only takes effect once a key exists.
/// Google WeatherNext is switched off for now. The whole pipeline below is
/// left intact and still compiles (and its tests still run); this one flag is
/// what keeps it off the wire and out of Settings. Flip it back to true to
/// restore the feature exactly as it was.
///
/// Reasons it is parked rather than deleted: the per-endpoint daily quotas
/// drain fast enough to leave the app falling back mid-session, and the
/// Classic path with the NBM overlay is the more accurate of the two in the
/// US anyway. See WeatherNextQuota.swift for the quota ledger.
nonisolated enum WeatherNextFeature {
    static let isEnabled = false
}

nonisolated enum ForecastSource: String, CaseIterable, Codable, Identifiable {
    case classic, weatherNext

    /// What Settings may offer. With the feature parked this is Classic only,
    /// so no picker can put the app back on a source it must not use.
    static var selectable: [ForecastSource] {
        WeatherNextFeature.isEnabled ? allCases : [.classic]
    }

    var id: String { rawValue }

    /// What a chosen source actually resolves to. WeatherNext needs both the
    /// feature to be live and a key to be present; anything else is Classic.
    /// The one place this rule lives: the view model and the background
    /// refresh both ask here, and used to spell it out separately.
    static func effective(for chosen: ForecastSource) -> ForecastSource {
        guard WeatherNextFeature.isEnabled, chosen == .weatherNext,
              WeatherNextKey.isConfigured else { return .classic }
        return .weatherNext
    }

    var label: String {
        switch self {
        case .classic: return "Classic Haze"
        case .weatherNext: return "Google WeatherNext"
        }
    }

    var sourceName: String {
        switch self {
        case .classic: return "Open-Meteo"
        case .weatherNext: return "Google Weather"
        }
    }

    var modelsName: String {
        switch self {
        case .classic: return "ECMWF · GFS · ICON"
        case .weatherNext: return "WeatherNext"
        }
    }

    var attributionLine: String {
        switch self {
        case .classic: return "Data from Open-Meteo, blending ECMWF, GFS & ICON models"
        case .weatherNext: return "Includes weather data from Google, via the WeatherNext model"
        }
    }

    /// The Settings paragraph under each choice.
    var blurb: String {
        switch self {
        case .classic:
            return "Open-Meteo blends the ECMWF, GFS and ICON global models, with the NWS National Blend spliced in for US locations. Free, needs no key, and the way Haze has always worked."
        case .weatherNext:
            return "Google's WeatherNext is a machine-learned forecast model, served through the Google Weather API: hourly out to ten days, with a day of recent history. Open-Meteo still supplies the 15-minute rain nowcast, yesterday's high and low, the cloud layers and the elevation, and stands in for the hourly detail whenever Google's per-day quota for it is used up. Needs a Google Maps Platform API key; a full refresh costs about 13 calls, though unit changes and relaunches inside the refresh window reuse the last answer without any."
        }
    }
}

// MARK: - API key

/// Where the Google Weather API key comes from. A key pasted in Settings wins
/// over one baked into the Info.plist, and the pasted key is deliberately not
/// CloudSync'd: it is a billing credential, not a preference.
nonisolated enum WeatherNextKey {
    static let overrideDefaultsKey = "weathernext_api_key"
    static let infoPlistKey = "GoogleWeatherAPIKey"

    /// Override first, then plist. Nil when neither supplies a usable key.
    static var value: String? {
        if let override = usable(UserDefaults.standard.string(forKey: overrideDefaultsKey)) {
            return override
        }
        return builtIn
    }

    static var isConfigured: Bool { value != nil }

    /// The plist supplies a usable key (so Settings can say "built in" rather
    /// than ask for one).
    static var isBuiltIn: Bool { builtIn != nil }

    private static var builtIn: String? {
        usable(Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// An unresolved build setting reaches the plist as "$(GOOGLE_WEATHER_API_KEY)",
    /// which is not a key; neither is whitespace.
    private static func usable(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

// MARK: - Service

/// Fetches from the Google Weather API and adapts the result into the
/// Open-Meteo-shaped `ForecastResponse`. `nonisolated` for the same reason
/// `WeatherService` is: decoding and reshaping 264 hours of JSON is not work
/// for the drawing thread.
nonisolated struct WeatherNextService {
    /// Hours of forecast requested, matching Open-Meteo's ten days.
    static let hourlyHorizon = 240
    /// Google's hard cap on records per hours page.
    static let hoursPageSize = 24
    static let historyHours = 24
    static let forecastDays = 10

    private static let base = "https://weather.googleapis.com/v1/"

    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    // MARK: Snapshot and outcome

    /// Google's decoded answers for one place, exactly as they arrived and
    /// before any unit conversion, so the adapter can be re-run for a new unit
    /// or after a relaunch without spending calls. `hoursFailure` and
    /// `historyFailure` keep the reason those optional legs are short or
    /// missing, so a snapshot served later can still say why. Written to disk
    /// by `WeatherNextRawCache`.
    struct RawSnapshot: Codable {
        /// When the forecast legs (hours, days, history) were fetched: the
        /// snapshot's clock for the page and the "Updated" stamp.
        var fetchedAt: Date
        var current: Wire.CurrentConditions?
        var hoursPages: [Wire.HoursPage]
        var days: Wire.DaysPage?
        var history: Wire.HistoryPage?
        var hoursFailure: String?
        var historyFailure: String?
        /// When `current` was fetched, which `fetchCurrentSummary` advances
        /// on its own without touching the forecast clock; otherwise a
        /// sidebar place refetched once past the window would never read as
        /// fresh again. Optional so files written before it decode; those
        /// read `fetchedAt`.
        var currentFetchedAt: Date? = nil
    }

    /// What one WeatherNext load hands back. `hoursFromGoogle` is false when
    /// Google supplied no forecast hours at all and the gap fill must provide
    /// the whole series. `fetchedAt` is when Google answered, the snapshot's
    /// clock when served from it, so a re-adapted page is not stamped as new.
    struct Outcome {
        let response: ForecastResponse
        let timezone: TimeZone
        let fetchedAt: Date
        let hoursFromGoogle: Bool
        /// Forecast hours Google supplied; the seam the notice names.
        let googleHours: Int
        /// Why the hours chain is short or empty, nil when it is whole.
        let hoursFailure: String?

        /// The footer sentence once the gap fill has supplied the rest of the
        /// hourly detail; nil when all of it is Google's.
        var notice: String? { Self.notice(googleHours: googleHours, hoursFailure: hoursFailure, fillApplied: true) }

        /// Composed after the gap fill is known to have landed or not: the
        /// fill can fail on its own (Open-Meteo rate limited, offline), and a
        /// page with no hourly series must not claim Open-Meteo supplied one.
        /// Pure so tests can drive every shape without a network.
        static func notice(googleHours: Int, hoursFailure: String?, fillApplied: Bool) -> String? {
            if googleHours == 0 {
                let reason = hoursFailure ?? "Google returned no hourly forecast."
                return fillApplied
                    ? "Hourly detail is from Open-Meteo for now. \(reason)"
                    : "There is no hourly detail right now: Google sent no hours and Open-Meteo could not be reached to stand in. \(reason)"
            }
            guard let hoursFailure else { return nil }
            // A chain cut short: Google's hours stand where they exist, so
            // the reader should know where the seam is.
            return fillApplied
                ? "Hourly detail past the first \(googleHours) hours is from Open-Meteo for now. \(hoursFailure)"
                : "Hourly detail stops after the first \(googleHours) hours for now: Open-Meteo could not be reached to fill in the rest. \(hoursFailure)"
        }
    }

    // MARK: Fetch

    /// The forecast for `place`, from the snapshot when one is younger than
    /// `maxAge` (zero forces a fetch: the user's own refresh), else from
    /// Google. Current and days are required and go first, together; only
    /// once both are in do the optional legs (the hours chain and history)
    /// start, so a required leg that is quota-blocked or failing costs
    /// nothing beyond itself rather than ten hourly pages on a load that is
    /// going to throw anyway. The optional legs' failures are recorded in the
    /// snapshot, so the page keeps Google's current and daily figures when
    /// only the hourly quota is spent. Whatever hours did arrive before a
    /// failing page are kept.
    func fetchForecastResponse(place: Place,
                               temperatureUnit: TemperatureUnit,
                               speedUnit: SpeedUnit,
                               precipUnit: PrecipUnit,
                               maxAge: TimeInterval) async throws -> Outcome {
        let cache = WeatherNextRawCache.shared
        if maxAge > 0, let snapshot = cache.snapshot(for: place),
           let current = snapshot.current, let days = snapshot.days,
           Self.isFresh(snapshot.fetchedAt, within: maxAge) {
            let age = Int(Date().timeIntervalSince(snapshot.fetchedAt))
            Self.log.info("WeatherNext served from the snapshot (\(age, privacy: .public) s old), no Google calls")
            #if DEBUG
            print("[WeatherNext] served from the snapshot (\(age) s old), no Google calls")
            #endif
            return Self.adapt(snapshot, current: current, days: days, place: place,
                              temperatureUnit: temperatureUnit, speedUnit: speedUnit, precipUnit: precipUnit)
        }

        guard let key = WeatherNextKey.value else { throw Self.missingKey() }
        let target = Target(key: key, place: place)

        // Each leg keeps its own Result: with a bare throwing `async let` the
        // first error tears the whole scope down, and the two required legs
        // are metered separately, so a block on one must not stop the other
        // from proving its quota is still there (a 2xx clears its block).
        async let currentResult: Result<Wire.CurrentConditions, WeatherError> = attempt {
            try await fetch(.currentConditions, target: target)
        }
        async let daysResult: Result<Wire.DaysPage, WeatherError> = attempt {
            try await fetch(.days, target: target)
        }
        let currentOutcome = await currentResult
        let daysOutcome = await daysResult
        // Current is checked first so, when both required legs fail, the
        // notice carries the reason from the call the user sees first.
        let current = try currentOutcome.get()
        let days = try daysOutcome.get()

        async let hoursChain = fetchHoursChain(target: target)
        async let historyResult: Result<Wire.HistoryPage, WeatherError> = attempt {
            try await fetch(.history, target: target)
        }
        let (hoursPages, hoursFailure) = await hoursChain
        let historyOutcome = await historyResult
        let history: Wire.HistoryPage?
        let historyFailure: String?
        switch historyOutcome {
        case .success(let page): history = page; historyFailure = nil
        case .failure(let error): history = nil; historyFailure = Self.reason(error)
        }

        let now = Date()
        let snapshot = RawSnapshot(fetchedAt: now, current: current, hoursPages: hoursPages,
                                   days: days, history: history,
                                   hoursFailure: hoursFailure, historyFailure: historyFailure,
                                   currentFetchedAt: now)
        cache.save(snapshot, for: place)

        #if DEBUG
        let hourCount = hoursPages.reduce(0) { $0 + ($1.forecastHours?.count ?? 0) }
        Self.log.debug("WeatherNext fetched \(hoursPages.count + 2 + (history == nil ? 0 : 1)) pages: \(hourCount) hours, \(days.forecastDays?.count ?? 0) days, \(history?.historyHours?.count ?? 0) history hours")
        #endif

        return Self.adapt(snapshot, current: current, days: days, place: place,
                          temperatureUnit: temperatureUnit, speedUnit: speedUnit, precipUnit: precipUnit)
    }

    /// One `currentConditions:lookup`, for the places that only need a number
    /// and a code (the Mac sidebar, the return-home panel); the numbers then
    /// agree with the WeatherNext page beside them. A snapshot whose current
    /// reading is younger than `maxAge` answers without a call; a fetched
    /// reading is folded back into the place's snapshot, under its own clock,
    /// so the next unit change needs none either.
    func fetchCurrentSummary(place: Place,
                             temperatureUnit: TemperatureUnit,
                             maxAge: TimeInterval) async throws -> (temperature: Double, code: Int, isDay: Bool) {
        let cache = WeatherNextRawCache.shared
        let current: Wire.CurrentConditions
        if maxAge > 0, let snapshot = cache.snapshot(for: place), let cached = snapshot.current,
           Self.isFresh(snapshot.currentFetchedAt ?? snapshot.fetchedAt, within: maxAge) {
            Self.log.info("WeatherNext current summary served from the snapshot, no Google call")
            #if DEBUG
            print("[WeatherNext] current summary served from the snapshot, no Google call")
            #endif
            current = cached
        } else {
            guard let key = WeatherNextKey.value else { throw Self.missingKey() }
            current = try await fetch(.currentConditions, target: Target(key: key, place: place))
            // Read again after the await: a full fetch for the same place
            // (the page's own reload runs beside the sidebar's pass) may have
            // written a whole snapshot meanwhile, and a current-only one saved
            // over it would cost the next unit change a dozen calls. Only the
            // current reading and its clock move; the forecast clock stays,
            // its hours and days being as old as they were.
            if var snapshot = cache.snapshot(for: place) {
                snapshot.current = current
                snapshot.currentFetchedAt = Date()
                cache.save(snapshot, for: place)
            } else {
                // A current-only snapshot: enough for this summary next time,
                // never mistaken for a forecast (that path needs days too).
                let now = Date()
                cache.save(RawSnapshot(fetchedAt: now, current: current, hoursPages: [],
                                       days: nil, history: nil, hoursFailure: nil, historyFailure: nil,
                                       currentFetchedAt: now),
                           for: place)
            }
        }
        let temperature = Self.temperature(current.temperature?.degrees ?? 0,
                                           unit: current.temperature?.unit, to: temperatureUnit)
        let code = Self.fogCode(
            mappedCode: Self.wmoCode(for: current.weatherCondition?.type ?? "",
                                     cloudCover: current.cloudCover.map { Int($0.rounded()) }),
            visibilityMetres: Self.visibilityMetres(current.visibility),
            temperatureC: Self.celsius(current.temperature),
            dewPointC: Self.celsius(current.dewPoint))
        return (temperature, code, current.isDaytime == true)
    }

    /// Follows `nextPageToken` until the chain holds `hourlyHorizon` records or
    /// the token ends. The loop is also bounded by page count so a server that
    /// kept handing out tokens could not spin it. Never throws: a page that
    /// fails (including a quota block, checked inside `fetch` before each
    /// page) ends the chain with the pages so far and the reason, because a
    /// partial series is still worth adapting.
    private func fetchHoursChain(target: Target) async -> (pages: [Wire.HoursPage], failure: String?) {
        var pages: [Wire.HoursPage] = []
        var token: String?
        var count = 0
        let maxPages = (Self.hourlyHorizon + Self.hoursPageSize - 1) / Self.hoursPageSize + 1
        repeat {
            do {
                let page: Wire.HoursPage = try await fetch(.hours(pageToken: token), target: target)
                pages.append(page)
                count += page.forecastHours?.count ?? 0
                token = page.nextPageToken
            } catch {
                return (pages, Self.reason(error))
            }
        } while count < Self.hourlyHorizon && token != nil && pages.count < maxPages
        return (pages, nil)
    }

    /// Runs one leg and keeps its outcome instead of throwing, so the legs can
    /// share an `async let` scope without one failure cancelling the rest.
    private func attempt<T>(_ body: () async throws -> T) async -> Result<T, WeatherError> {
        do {
            return .success(try await body())
        } catch let error as WeatherError {
            return .failure(error)
        } catch {
            return .failure(.weatherNextFailed(reason: error.localizedDescription))
        }
    }

    /// Adapts a snapshot, fetched or read back, into the app's response.
    /// `current` and `days` are the snapshot's own, unwrapped by the caller
    /// because a forecast without them is no forecast. The hours failure is
    /// re-read from the quota ledger while a block is on file: the stored
    /// sentence says "about 6 h" as of the fetch, and a snapshot is served
    /// for up to the refresh window after that.
    private static func adapt(_ snapshot: RawSnapshot,
                              current: Wire.CurrentConditions,
                              days: Wire.DaysPage,
                              place: Place,
                              temperatureUnit: TemperatureUnit,
                              speedUnit: SpeedUnit,
                              precipUnit: PrecipUnit) -> Outcome {
        let hourRecords = snapshot.hoursPages.flatMap { $0.forecastHours ?? [] }
        let timeZoneID = days.timeZone?.id
            ?? snapshot.hoursPages.first?.timeZone?.id
            ?? current.timeZone?.id
        let (response, tz) = makeForecastResponse(
            current: current,
            hours: hourRecords,
            days: days.forecastDays ?? [],
            history: snapshot.history?.historyHours ?? [],
            timeZoneID: timeZoneID,
            place: place,
            temperatureUnit: temperatureUnit,
            speedUnit: speedUnit,
            precipUnit: precipUnit
        )
        let hoursFailure: String?
        if snapshot.hoursFailure != nil, let until = WeatherNextQuota.blockedUntil(.hours) {
            hoursFailure = WeatherNextQuota.reason(for: .hours, until: until)
        } else {
            hoursFailure = snapshot.hoursFailure
        }
        return Outcome(response: response, timezone: tz, fetchedAt: snapshot.fetchedAt,
                       hoursFromGoogle: !hourRecords.isEmpty,
                       googleHours: hourRecords.count, hoursFailure: hoursFailure)
    }

    /// Younger than `maxAge`. A clock set backwards makes `fetchedAt` read as
    /// the future; that counts as fresh rather than forcing a fetch.
    private static func isFresh(_ fetchedAt: Date, within maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) < maxAge
    }

    /// The user-readable reason inside a leg's error; `fetch` only ever throws
    /// `weatherNextFailed`, so this is Google's own sentence.
    private static func reason(_ error: Error) -> String {
        (error as? WeatherError)?.errorDescription ?? error.localizedDescription
    }

    private struct Target {
        let key: String
        let place: Place
    }

    private enum Endpoint {
        case currentConditions
        case hours(pageToken: String?)
        case days
        case history

        var path: String {
            switch self {
            case .currentConditions: return "currentConditions:lookup"
            case .hours: return "forecast/hours:lookup"
            case .days: return "forecast/days:lookup"
            case .history: return "history/hours:lookup"
            }
        }

        /// Google meters each endpoint separately; every hours page counts
        /// against the one hours quota.
        var quota: WeatherNextQuota.Endpoint {
            switch self {
            case .currentConditions: return .currentConditions
            case .hours: return .hours
            case .days: return .days
            case .history: return .history
            }
        }

        var queryItems: [URLQueryItem] {
            switch self {
            case .currentConditions:
                return []
            case .hours(let pageToken):
                var items = [
                    URLQueryItem(name: "hours", value: String(WeatherNextService.hourlyHorizon)),
                    URLQueryItem(name: "pageSize", value: String(WeatherNextService.hoursPageSize))
                ]
                if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
                return items
            case .days:
                return [
                    URLQueryItem(name: "days", value: String(WeatherNextService.forecastDays)),
                    URLQueryItem(name: "pageSize", value: String(WeatherNextService.forecastDays))
                ]
            case .history:
                return [
                    URLQueryItem(name: "hours", value: String(WeatherNextService.historyHours)),
                    URLQueryItem(name: "pageSize", value: String(WeatherNextService.historyHours))
                ]
            }
        }
    }

    /// METRIC is requested for predictability, but every adapter conversion
    /// still reads the unit string that actually arrives.
    private func request(_ endpoint: Endpoint, target: Target) throws -> URLRequest {
        var components = URLComponents(string: Self.base + endpoint.path)
        components?.queryItems = [
            URLQueryItem(name: "key", value: target.key),
            URLQueryItem(name: "location.latitude", value: String(target.place.latitude)),
            URLQueryItem(name: "location.longitude", value: String(target.place.longitude)),
            URLQueryItem(name: "unitsSystem", value: "METRIC")
        ] + endpoint.queryItems
        guard let url = components?.url else {
            throw Self.failure(endpoint: endpoint.path, status: nil, body: nil, transportError: nil,
                               reason: "The Google request could not be built (\(endpoint.path)).")
        }
        var request = URLRequest(url: url)
        // Google's recommended identification header for mobile REST callers;
        // it lets the key be restricted to this bundle. Harmless on macOS.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return request
    }

    /// Every way this can fail becomes `weatherNextFailed(reason:)` carrying
    /// Google's own words, because the caller falls back to Open-Meteo and
    /// shows the reason; a generic "couldn't reach" would hide the one fact
    /// (key restriction, API not enabled, quota) the user needs to fix it.
    ///
    /// The quota ledger is consulted first: an endpoint Google has already
    /// refused for the day is skipped without a round trip, since retrying
    /// only spends the per-minute allowance on a certain 429. A 429 records
    /// the block with Google's own message (it names the period), a 2xx
    /// clears it.
    private func fetch<T: Decodable>(_ endpoint: Endpoint, target: Target) async throws -> T {
        let path = endpoint.path
        let quota = endpoint.quota
        if let until = WeatherNextQuota.blockedUntil(quota) {
            let reason = WeatherNextQuota.reason(for: quota, until: until)
            Self.log.notice("WeatherNext \(path, privacy: .public) skipped, quota blocked until \(until.description, privacy: .public): \(reason, privacy: .public)")
            #if DEBUG
            print("[WeatherNext] \(path) skipped, quota blocked until \(until): \(reason)")
            #endif
            throw WeatherError.weatherNextFailed(reason: reason)
        }

        let urlRequest = try request(endpoint, target: target)
        let data: Data
        let status: Int?
        do {
            let (d, response) = try await session.data(for: urlRequest)
            data = d
            status = (response as? HTTPURLResponse)?.statusCode
        } catch {
            throw Self.failure(endpoint: path, status: nil, body: nil, transportError: error)
        }
        guard let status else {
            throw Self.failure(endpoint: path, status: nil, body: nil, transportError: nil)
        }
        guard (200..<300).contains(status) else {
            if status == 429 {
                let message = Self.googleError(in: data)?.message
                WeatherNextQuota.recordExhausted(quota, message: message)
                let until = WeatherNextQuota.blockedUntil(quota)
                Self.log.error("WeatherNext \(path, privacy: .public) quota exhausted, blocked until \(until?.description ?? "unknown", privacy: .public): \(message ?? "no message", privacy: .public)")
                #if DEBUG
                print("[WeatherNext] \(path) quota exhausted, blocked until \(until?.description ?? "unknown"): \(message ?? "no message")")
                #endif
                // The reason on screen is the ledger's sentence (which quota,
                // and when Google is back), not Google's project-number
                // boilerplate: the first blocked load and every later one
                // then read the same. Google's own words are in the log above.
                if let until {
                    throw Self.failure(endpoint: path, status: status, body: data, transportError: nil,
                                       reason: WeatherNextQuota.reason(for: quota, until: until))
                }
            }
            throw Self.failure(endpoint: path, status: status, body: data, transportError: nil)
        }
        WeatherNextQuota.clear(quota)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // The decoder's complaint names a key path, useful in the log and
            // noise on screen.
            throw Self.failure(endpoint: path, status: status, body: nil, transportError: nil,
                               reason: Self.failureReason(endpoint: path, status: nil, body: nil, transportError: nil),
                               logDetail: error.localizedDescription)
        }
    }

    // MARK: Failure reasons

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Haze", category: "WeatherNext")

    private static func missingKey() -> WeatherError {
        failure(endpoint: "(none)", status: nil, body: nil, transportError: nil,
                reason: "No Google API key is set.")
    }

    /// Builds the error and writes the log line in one place, so no failure
    /// path can forget the log. `reason` overrides the composed one; the log
    /// carries only the endpoint path, never the URL, whose query holds the key.
    private static func failure(endpoint: String, status: Int?, body: Data?, transportError: Error?,
                                reason: String? = nil, logDetail: String? = nil) -> WeatherError {
        let reason = reason ?? failureReason(endpoint: endpoint, status: status, body: body,
                                             transportError: transportError)
        let statusText = status.map(String.init) ?? "none"
        let detail = logDetail.map { " [\($0)]" } ?? ""
        log.error("WeatherNext \(endpoint, privacy: .public) failed, status \(statusText, privacy: .public): \(reason, privacy: .public)\(detail, privacy: .public)")
        #if DEBUG
        print("[WeatherNext] \(endpoint) failed, status \(statusText): \(reason)\(detail)")
        #endif
        return .weatherNextFailed(reason: reason)
    }

    /// Google's error envelope: {"error": {"code", "message", "status"}}.
    private struct GoogleErrorBody: Decodable {
        struct Detail: Decodable {
            var code: Int?
            var message: String?
            var status: String?
        }
        var error: Detail?
    }

    /// The envelope's detail, nil when the body is missing or not Google's shape.
    private static func googleError(in body: Data?) -> GoogleErrorBody.Detail? {
        body.flatMap { try? JSONDecoder().decode(GoogleErrorBody.self, from: $0) }?.error
    }

    /// One user-readable sentence for a failed call. Pure, so tests can feed it
    /// canned bodies. `endpoint` is the path ("forecast/hours:lookup"), never
    /// the URL: the URL's query carries the key and this string reaches the
    /// screen and the log.
    static func failureReason(endpoint: String, status: Int?, body: Data?, transportError: Error?) -> String {
        if let transportError {
            if let urlError = transportError as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return "The phone is offline, so Google could not be reached."
                case .timedOut:
                    return "Google took too long to answer."
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    return "Google's weather service could not be reached."
                default:
                    break
                }
            }
            return "Google could not be reached (\(trimmed(transportError.localizedDescription, to: 120)))."
        }

        guard let status else {
            return "Google's answer could not be read (\(endpoint))."
        }

        let detail = googleError(in: body)
        let googleStatus = detail?.status ?? "HTTP \(status)"
        let message = detail?.message.map { sentence(trimmed(redactKey($0), to: 200)) }

        switch status {
        case 400 where detail?.status == "INVALID_ARGUMENT"
            && (detail?.message ?? "").localizedCaseInsensitiveContains("api key"):
            return "Google rejected the API key: \(message ?? "invalid argument.")"
        case 403:
            return "Google refused the request (\(googleStatus)): \(message ?? "permission denied.")"
        case 429:
            return "Google's quota is exhausted (\(googleStatus)): \(message ?? "too many requests.")"
        case 404:
            return "Google has no data for this place (\(endpoint))."
        case 500...599:
            return "Google's weather service had an error (\(status))."
        default:
            return "Google answered \(status) on \(endpoint): \(message ?? sentence(googleStatus))"
        }
    }

    /// Cuts at the last space before `limit` so a long Google message does
    /// not end mid-word on screen.
    private static func trimmed(_ text: String, to limit: Int) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    /// The composed reason is read as a sentence, so a message Google ends
    /// without punctuation gets its full stop.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) || text.hasSuffix("...") ? text : text + "."
    }

    /// Google's messages are not known to echo the key, but the reason goes on
    /// screen and into the log, so any `key=` parameter is blanked regardless.
    private static func redactKey(_ text: String) -> String {
        text.replacingOccurrences(of: #"key=[^&\s]+"#, with: "key=redacted", options: .regularExpression)
    }

    // MARK: - Wire format

    /// Codable mirrors of the Google Weather API objects. Every numeric and
    /// boolean leaf is Optional because proto3 JSON omits zero and false: a
    /// temperature of exactly 0 °C, a calm wind from due north, a dry hour's
    /// qpf and midnight's `hours` all arrive as missing keys. Fields are `var`
    /// so the memberwise inits default them, which keeps test fixtures short.
    /// Encodable too, with the same keys, so a `RawSnapshot` round-trips to
    /// disk unchanged and reads back as if Google had just answered.
    nonisolated enum Wire {
        nonisolated struct TimeZoneInfo: Codable {
            var id: String?
        }

        nonisolated struct Temperature: Codable {
            var degrees: Double?
            /// "CELSIUS" or "FAHRENHEIT".
            var unit: String?
        }

        nonisolated struct Speed: Codable {
            var value: Double?
            /// "KILOMETERS_PER_HOUR" or "MILES_PER_HOUR".
            var unit: String?
        }

        nonisolated struct Direction: Codable {
            var degrees: Double?
            var cardinal: String?
        }

        nonisolated struct Wind: Codable {
            var direction: Direction?
            var speed: Speed?
            var gust: Speed?
        }

        nonisolated struct Probability: Codable {
            var percent: Double?
            /// "RAIN", "SNOW", and friends.
            var type: String?
        }

        nonisolated struct Depth: Codable {
            var quantity: Double?
            /// "MILLIMETERS" or "INCHES".
            var unit: String?
        }

        nonisolated struct Precipitation: Codable {
            var probability: Probability?
            var qpf: Depth?
            var snowQpf: Depth?
        }

        nonisolated struct AirPressure: Codable {
            var meanSeaLevelMillibars: Double?
        }

        nonisolated struct Visibility: Codable {
            var distance: Double?
            /// "KILOMETERS" or "MILES".
            var unit: String?
        }

        nonisolated struct ConditionDescription: Codable {
            var text: String?
            var languageCode: String?
        }

        nonisolated struct Condition: Codable {
            var iconBaseUri: String?
            var description: ConditionDescription?
            /// One of the `WeatherCondition.type` enum names, mapped to WMO by
            /// `WeatherNextService.wmoCode(for:cloudCover:)`; the enum has no
            /// fog, which `fogCode` derives from visibility and dew point.
            var type: String?
        }

        nonisolated struct Interval: Codable {
            /// RFC 3339, UTC.
            var startTime: String?
            var endTime: String?
        }

        nonisolated struct DisplayDate: Codable {
            var year: Int?
            var month: Int?
            var day: Int?
        }

        nonisolated struct SunEvents: Codable {
            var sunriseTime: String?
            var sunsetTime: String?
        }

        nonisolated struct CurrentConditions: Codable {
            var currentTime: String?
            var timeZone: TimeZoneInfo?
            var isDaytime: Bool?
            var weatherCondition: Condition?
            var temperature: Temperature?
            var feelsLikeTemperature: Temperature?
            var dewPoint: Temperature?
            var heatIndex: Temperature?
            var windChill: Temperature?
            var relativeHumidity: Double?
            var uvIndex: Double?
            var precipitation: Precipitation?
            var thunderstormProbability: Double?
            var airPressure: AirPressure?
            var wind: Wind?
            var visibility: Visibility?
            var cloudCover: Double?
        }

        /// Shared by forecast/hours and history/hours.
        nonisolated struct Hour: Codable {
            var interval: Interval?
            var weatherCondition: Condition?
            var temperature: Temperature?
            var feelsLikeTemperature: Temperature?
            var dewPoint: Temperature?
            var heatIndex: Temperature?
            var windChill: Temperature?
            var wetBulbTemperature: Temperature?
            var precipitation: Precipitation?
            var airPressure: AirPressure?
            var wind: Wind?
            var visibility: Visibility?
            var relativeHumidity: Double?
            var uvIndex: Double?
            var thunderstormProbability: Double?
            var cloudCover: Double?
            var isDaytime: Bool?
        }

        nonisolated struct HoursPage: Codable {
            var forecastHours: [Hour]?
            var timeZone: TimeZoneInfo?
            var nextPageToken: String?
        }

        nonisolated struct HistoryPage: Codable {
            var historyHours: [Hour]?
            var timeZone: TimeZoneInfo?
            var nextPageToken: String?
        }

        nonisolated struct DayPart: Codable {
            var interval: Interval?
            var weatherCondition: Condition?
            var precipitation: Precipitation?
            var wind: Wind?
            var relativeHumidity: Double?
            var uvIndex: Double?
            var thunderstormProbability: Double?
            var cloudCover: Double?
        }

        nonisolated struct Day: Codable {
            var interval: Interval?
            var displayDate: DisplayDate?
            var daytimeForecast: DayPart?
            var nighttimeForecast: DayPart?
            var maxTemperature: Temperature?
            var minTemperature: Temperature?
            var feelsLikeMaxTemperature: Temperature?
            var feelsLikeMinTemperature: Temperature?
            var maxHeatIndex: Temperature?
            var sunEvents: SunEvents?
        }

        nonisolated struct DaysPage: Codable {
            var forecastDays: [Day]?
            var timeZone: TimeZoneInfo?
            var nextPageToken: String?
        }
    }

    // MARK: - Adapter

    /// Builds the Open-Meteo-shaped response from decoded wire objects. Kept
    /// separate from the network path so tests can feed fixtures.
    ///
    /// The zone comes from `timeZoneID` (the pages' `timeZone.id`), then the
    /// current-conditions zone, then the place, then the device. Everything
    /// the app reads is then a local wall-clock string in that zone.
    ///
    /// `hours` and `history` may both be empty (the hourly quota spent): every
    /// hourly column is then an empty, index-aligned array for the gap fill to
    /// append to, current is still built, and every daily row falls to
    /// Google's own day and night halves since no calendar day has 23 hours.
    static func makeForecastResponse(current: Wire.CurrentConditions,
                                     hours: [Wire.Hour],
                                     days: [Wire.Day],
                                     history: [Wire.Hour],
                                     timeZoneID: String? = nil,
                                     place: Place,
                                     temperatureUnit: TemperatureUnit,
                                     speedUnit: SpeedUnit,
                                     precipUnit: PrecipUnit) -> (ForecastResponse, TimeZone) {
        let tz = [timeZoneID, current.timeZone?.id, place.timezone]
            .compactMap { $0 }
            .compactMap(TimeZone.init(identifier:))
            .first ?? .current
        let clock = LocalClock(timeZone: tz)
        let units = Units(temperatureUnit: temperatureUnit, speedUnit: speedUnit,
                          precipAPI: precipUnit.apiValue(temperatureUnit: temperatureUnit))

        // Current
        let currentDate = current.currentTime.flatMap(clock.date) ?? Date()
        let currentTemperature = units.temperature(current.temperature)
        let currentOut = ForecastResponse.Current(
            time: clock.dateTimeString(currentDate),
            temperature: currentTemperature,
            humidity: current.relativeHumidity ?? 0,
            apparentTemperature: current.feelsLikeTemperature.map(units.temperature) ?? currentTemperature,
            isDay: current.isDaytime == true ? 1 : 0,
            precipitation: units.precipitation(current.precipitation?.qpf),
            weatherCode: fogCode(
                mappedCode: wmoCode(for: current.weatherCondition?.type ?? "",
                                    cloudCover: current.cloudCover.map { Int($0.rounded()) }),
                visibilityMetres: visibilityMetres(current.visibility),
                temperatureC: celsius(current.temperature),
                dewPointC: celsius(current.dewPoint)),
            cloudCover: current.cloudCover ?? 0,
            pressure: current.airPressure?.meanSeaLevelMillibars ?? 0,
            windSpeed: units.speed(current.wind?.speed),
            windDirection: current.wind?.direction?.degrees ?? 0,
            windGust: units.speed(current.wind?.gust)
        )

        // Hourly: history then forecast, one record per start instant, ascending.
        // Where the two overlap the forecast record wins: it is the fresher of
        // the two and the one Google itself shows for that hour.
        var byStart: [Date: Wire.Hour] = [:]
        for hour in history + hours {
            guard let start = hour.interval?.startTime.flatMap(clock.date) else { continue }
            byStart[start] = hour
        }
        var samples: [HourSample] = []
        samples.reserveCapacity(byStart.count)
        for start in byStart.keys.sorted() {
            guard let hour = byStart[start] else { continue }
            let label = clock.hourLabel(start)
            // On a fall-back night two instants share one wall-clock hour and
            // LocalTimeParser can only recover the later, so the later record
            // takes the label and the earlier one is dropped, keeping every
            // array one-to-one with what the parser will read back.
            if samples.last?.time == label { samples.removeLast() }
            let temperature = units.temperature(hour.temperature)
            samples.append(HourSample(
                time: label,
                temperature: temperature,
                humidity: hour.relativeHumidity ?? 0,
                apparentTemperature: hour.feelsLikeTemperature.map(units.temperature) ?? temperature,
                precipitationProbability: Self.percent(hour.precipitation?.probability?.percent),
                precipitation: units.precipitation(hour.precipitation?.qpf),
                snowWaterMillimetres: depthMillimetres(hour.precipitation?.snowQpf),
                weatherCode: fogCode(
                    mappedCode: wmoCode(for: hour.weatherCondition?.type ?? "",
                                        cloudCover: hour.cloudCover.map { Int($0.rounded()) }),
                    visibilityMetres: visibilityMetres(hour.visibility),
                    temperatureC: celsius(hour.temperature),
                    dewPointC: celsius(hour.dewPoint)),
                windSpeed: units.speed(hour.wind?.speed),
                windGust: units.speed(hour.wind?.gust),
                windDirection: hour.wind?.direction?.degrees ?? 0,
                isDay: hour.isDaytime == true ? 1 : 0,
                // A plain leaf, so proto3's missing key is a clear hour, not a gap.
                cloudCover: hour.cloudCover ?? 0,
                dewPoint: hour.dewPoint.map(units.temperature),
                visibility: hour.visibility.map(units.visibility)
            ))
        }
        // proto3 drops a zero leaf but never a whole message, so a missing
        // `dewPoint` or `visibility` object is unset, not zero. The arrays are
        // non-optional per hour, so one gap makes the whole column absent: the
        // app then shows nothing, which beats a fabricated 0 °C or 0 m.
        let dewPoints = samples.map(\.dewPoint)
        let visibilities = samples.map(\.visibility)
        let hourly = ForecastResponse.Hourly(
            time: samples.map(\.time),
            temperature: samples.map(\.temperature),
            humidity: samples.map(\.humidity),
            apparentTemperature: samples.map(\.apparentTemperature),
            precipitationProbability: samples.map(\.precipitationProbability),
            precipitation: samples.map(\.precipitation),
            weatherCode: samples.map(\.weatherCode),
            windSpeed: samples.map(\.windSpeed),
            windDirection: samples.map(\.windDirection),
            isDay: samples.map(\.isDay),
            cloudCover: samples.map(\.cloudCover),
            dewPoint: dewPoints.allSatisfy { $0 != nil } ? dewPoints.compactMap { $0 } : nil,
            visibility: visibilities.allSatisfy { $0 != nil } ? visibilities.compactMap { $0 } : nil,
            // Google reports total cover only; the gap fill splices in Open-Meteo's
            // layers, scaled to that total (OpenMeteoGapFill.swift).
            cloudCoverLow: nil, cloudCoverMid: nil, cloudCoverHigh: nil
        )

        // Daily. Google's day is 7 am to 7 am; Open-Meteo's, and everything
        // downstream, is the calendar day. Where the hourly series covers a
        // whole calendar day its figures are aggregated the way Open-Meteo
        // does (max and min of the hours, sums of the hours), and Google's own
        // day and night halves are used only where the hours run short.
        var samplesByDay: [String: [HourSample]] = [:]
        for sample in samples { samplesByDay[String(sample.time.prefix(10)), default: []].append(sample) }

        var dTime: [String] = [], dCode: [Int] = [], dTempMax: [Double] = [], dTempMin: [Double] = []
        var dApparentMax: [Double] = [], dApparentMin: [Double] = []
        var dSunrise: [String] = [], dSunset: [String] = []
        var dPrecipitationSum: [Double] = [], dProbabilityMax: [Int] = []
        var dWindSpeedMax: [Double] = [], dWindGustMax: [Double] = [], dWindDirection: [Double] = []
        var dSnowfallSum: [Double] = []
        for day in days {
            let dateString: String
            if let d = day.displayDate, let y = d.year, let m = d.month, let dd = d.day {
                dateString = String(format: "%04d-%02d-%02d", y, m, dd)
            } else if let start = day.interval?.startTime.flatMap(clock.date) {
                dateString = clock.dateString(start)
            } else {
                continue
            }
            let dayPart = day.daytimeForecast
            let nightPart = day.nighttimeForecast

            dTime.append(dateString)
            dCode.append(dailyCode(day: dayPart, night: nightPart))
            dSunrise.append(day.sunEvents?.sunriseTime.flatMap(clock.date).map(clock.dateTimeString) ?? "")
            dSunset.append(day.sunEvents?.sunsetTime.flatMap(clock.date).map(clock.dateTimeString) ?? "")

            if let dayHours = samplesByDay[dateString], dayHours.count >= Self.fullDayHours {
                let temperatures = dayHours.map(\.temperature)
                let apparent = dayHours.map(\.apparentTemperature)
                dTempMax.append(temperatures.max() ?? 0)
                dTempMin.append(temperatures.min() ?? 0)
                dApparentMax.append(apparent.max() ?? 0)
                dApparentMin.append(apparent.min() ?? 0)
                dPrecipitationSum.append(dayHours.reduce(0) { $0 + $1.precipitation })
                dProbabilityMax.append(dayHours.map(\.precipitationProbability).max() ?? 0)
                dWindSpeedMax.append(dayHours.map(\.windSpeed).max() ?? 0)
                dWindGustMax.append(dayHours.map(\.windGust).max() ?? 0)
                dWindDirection.append(dominantDirection(dayHours))
                dSnowfallSum.append(snowfallDepth(
                    waterEquivalentMillimetres: dayHours.reduce(0) { $0 + $1.snowWaterMillimetres },
                    precipUnitAPI: units.precipAPI))
            } else {
                let tempMax = units.temperature(day.maxTemperature)
                let tempMin = units.temperature(day.minTemperature)
                dTempMax.append(tempMax)
                dTempMin.append(tempMin)
                dApparentMax.append(day.feelsLikeMaxTemperature.map(units.temperature) ?? tempMax)
                dApparentMin.append(day.feelsLikeMinTemperature.map(units.temperature) ?? tempMin)
                dPrecipitationSum.append(units.precipitation(dayPart?.precipitation?.qpf)
                                         + units.precipitation(nightPart?.precipitation?.qpf))
                dProbabilityMax.append(max(
                    Self.percent(dayPart?.precipitation?.probability?.percent),
                    Self.percent(nightPart?.precipitation?.probability?.percent)))
                dWindSpeedMax.append(max(units.speed(dayPart?.wind?.speed), units.speed(nightPart?.wind?.speed)))
                dWindGustMax.append(max(units.speed(dayPart?.wind?.gust), units.speed(nightPart?.wind?.gust)))
                dWindDirection.append(dayPart?.wind?.direction?.degrees
                                      ?? nightPart?.wind?.direction?.degrees ?? 0)
                let snowMM = depthMillimetres(dayPart?.precipitation?.snowQpf)
                    + depthMillimetres(nightPart?.precipitation?.snowQpf)
                dSnowfallSum.append(snowfallDepth(waterEquivalentMillimetres: snowMM, precipUnitAPI: units.precipAPI))
            }
        }
        let daily = ForecastResponse.Daily(
            time: dTime, weatherCode: dCode, tempMax: dTempMax, tempMin: dTempMin,
            apparentMax: dApparentMax, apparentMin: dApparentMin,
            sunrise: dSunrise, sunset: dSunset,
            precipitationSum: dPrecipitationSum, precipitationProbabilityMax: dProbabilityMax,
            windSpeedMax: dWindSpeedMax, windGustMax: dWindGustMax,
            windDirectionDominant: dWindDirection, snowfallSum: dSnowfallSum
        )

        // Elevation and the 15-minute nowcast are the gap fill's to set.
        let response = ForecastResponse(
            timezone: tz.identifier,
            utcOffsetSeconds: tz.secondsFromGMT(for: Date()),
            elevation: nil,
            current: currentOut,
            hourly: hourly,
            daily: daily,
            minutely15: nil
        )
        return (response, tz)
    }

    /// One adapted hour, kept together until the arrays are split out so a
    /// duplicate wall-clock label can drop a whole record at once.
    private struct HourSample {
        let time: String
        let temperature: Double
        let humidity: Double
        let apparentTemperature: Double
        let precipitationProbability: Int
        let precipitation: Double
        /// Snow as liquid water equivalent, before the 7:1 depth conversion.
        let snowWaterMillimetres: Double
        let weatherCode: Int
        let windSpeed: Double
        let windGust: Double
        let windDirection: Double
        let isDay: Int
        /// Total cover, percent; the `Hourly.cloudCover` column the gap fill
        /// scales Open-Meteo's layers against.
        let cloudCover: Double
        let dewPoint: Double?
        let visibility: Double?
    }

    /// Hours a calendar day must hold before its daily figures are taken from
    /// the hourly series. 23, not 24, so a spring-forward day still counts.
    private static let fullDayHours = 23

    /// The day's headline code, as Open-Meteo defines it: the most severe
    /// condition of the day. Both halves are mapped and the worse kind wins,
    /// so a night of rain is not hidden behind a partly cloudy afternoon;
    /// within a kind the heavier code wins. Overcast when neither half has one.
    private static func dailyCode(day: Wire.DayPart?, night: Wire.DayPart?) -> Int {
        let codes = [day, night].compactMap { part -> Int? in
            guard let type = part?.weatherCondition?.type else { return nil }
            return wmoCode(for: type, cloudCover: part?.cloudCover.map { Int($0.rounded()) })
        }
        return codes.max { (severity($0), $0) < (severity($1), $1) } ?? 3
    }

    /// Worse weather ranks higher; the tiers follow `WeatherCondition.kind`
    /// over the codes `wmoCode(for:cloudCover:)` can produce.
    private static func severity(_ code: Int) -> Int {
        switch code {
        case 96, 99: return 9
        case 95: return 8
        case 71...77, 85, 86: return 7
        case 56, 57, 66, 67: return 6
        case 61...65, 80...82: return 5
        case 51...55: return 4
        case 45, 48: return 3
        default: return 0
        }
    }

    /// Open-Meteo's dominant direction is the heading of the day's mean wind
    /// vector, so a day split between a west wind and a calm reads west.
    private static func dominantDirection(_ hours: [HourSample]) -> Double {
        var x = 0.0, y = 0.0
        for hour in hours {
            let radians = hour.windDirection * .pi / 180
            x += hour.windSpeed * sin(radians)
            y += hour.windSpeed * cos(radians)
        }
        guard x != 0 || y != 0 else { return hours.first?.windDirection ?? 0 }
        let degrees = atan2(x, y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func percent(_ value: Double?) -> Int {
        Int((value ?? 0).rounded())
    }

    // MARK: - Condition mapping

    /// Google condition type to the WMO code `WeatherCondition` understands.
    /// WMO has no code for wind, so WINDY reads as partly cloudy and the wind
    /// itself shows in its own row. Unknown or unspecified types fall back to
    /// a sky code from cloud cover, and to overcast without one.
    static func wmoCode(for conditionType: String, cloudCover: Int?) -> Int {
        switch conditionType {
        case "CLEAR": return 0
        case "MOSTLY_CLEAR": return 1
        case "PARTLY_CLOUDY", "WINDY": return 2
        case "MOSTLY_CLOUDY", "CLOUDY": return 3
        case "WIND_AND_RAIN": return 63
        case "LIGHT_RAIN_SHOWERS", "CHANCE_OF_SHOWERS", "SCATTERED_SHOWERS": return 80
        case "RAIN_SHOWERS": return 81
        case "HEAVY_RAIN_SHOWERS": return 82
        case "LIGHT_TO_MODERATE_RAIN", "LIGHT_RAIN": return 61
        case "MODERATE_TO_HEAVY_RAIN", "RAIN": return 63
        case "HEAVY_RAIN", "RAIN_PERIODICALLY_HEAVY": return 65
        case "LIGHT_SNOW_SHOWERS", "CHANCE_OF_SNOW_SHOWERS", "SCATTERED_SNOW_SHOWERS", "SNOW_SHOWERS": return 85
        case "HEAVY_SNOW_SHOWERS": return 86
        case "LIGHT_TO_MODERATE_SNOW", "LIGHT_SNOW": return 71
        case "MODERATE_TO_HEAVY_SNOW", "SNOW": return 73
        case "HEAVY_SNOW", "SNOWSTORM", "SNOW_PERIODICALLY_HEAVY", "HEAVY_SNOW_STORM", "BLOWING_SNOW": return 75
        case "RAIN_AND_SNOW": return 66
        case "HAIL", "HAIL_SHOWERS": return 96
        case "THUNDERSTORM", "THUNDERSHOWER", "LIGHT_THUNDERSTORM_RAIN", "SCATTERED_THUNDERSTORMS": return 95
        case "HEAVY_THUNDERSTORM": return 99
        default:
            guard let cloudCover else { return 3 }
            switch cloudCover {
            case ...12: return 0
            case ...37: return 1
            case ...75: return 2
            default: return 3
            }
        }
    }

    /// Google's condition enum has no fog or mist, so an hour of fog arrives as
    /// CLOUDY with the visibility and dew point telling the real story. The
    /// rule is the observer's: visibility under 1 km with the air within 1 °C
    /// of saturation. It only overrides a sky-only code (0 to 3), so rain or
    /// snow that happens to be foggy keeps its own, more severe, code. WMO 48
    /// (depositing rime fog) when the air is at or below freezing, else 45.
    /// Inputs are metres and Celsius from the wire, before any unit choice.
    static func fogCode(mappedCode: Int, visibilityMetres: Double?, temperatureC: Double?, dewPointC: Double?) -> Int {
        guard (0...3).contains(mappedCode),
              let visibilityMetres, visibilityMetres < 1000,
              let temperatureC, let dewPointC,
              temperatureC - dewPointC <= 1.0 else { return mappedCode }
        return temperatureC <= 0 ? 48 : 45
    }

    // MARK: - Time

    /// An RFC 3339 instant as Open-Meteo's local wall-clock string
    /// ("yyyy-MM-dd'T'HH:mm") in `tz`. Builds its formatters per call, so the
    /// adapter uses a shared `LocalClock` instead; this is for tests and
    /// one-off callers.
    static func localTimeString(_ rfc3339: String, in tz: TimeZone) -> String? {
        let clock = LocalClock(timeZone: tz)
        return clock.date(rfc3339).map(clock.dateTimeString)
    }

    /// RFC 3339 in, Open-Meteo-style local strings out. `displayDateTime.hours`
    /// is never consulted: proto3 drops it at midnight.
    nonisolated struct LocalClock {
        private let fractional: ISO8601DateFormatter
        private let whole: ISO8601DateFormatter
        private let dateTime: DateFormatter
        private let dateOnly: DateFormatter
        private let wholeHour: DateFormatter

        init(timeZone: TimeZone) {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            dateTime = DateFormatter()
            dateTime.locale = Locale(identifier: "en_US_POSIX")
            dateTime.timeZone = timeZone
            dateTime.dateFormat = "yyyy-MM-dd'T'HH:mm"
            dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = timeZone
            dateOnly.dateFormat = "yyyy-MM-dd"
            wholeHour = DateFormatter()
            wholeHour.locale = Locale(identifier: "en_US_POSIX")
            wholeHour.timeZone = timeZone
            wholeHour.dateFormat = "yyyy-MM-dd'T'HH':00'"
        }

        func date(_ rfc3339: String) -> Date? {
            fractional.date(from: rfc3339) ?? whole.date(from: rfc3339)
        }

        func dateTimeString(_ date: Date) -> String { dateTime.string(from: date) }
        func dateString(_ date: Date) -> String { dateOnly.string(from: date) }

        /// The Open-Meteo hour label for an hour-long interval starting at
        /// `start`. Google starts intervals on the UTC hour, so in a half- or
        /// quarter-hour zone the local start reads 01:30 or 01:45 and the app,
        /// which labels hours without minutes, would file it under 01:00. Such
        /// a record is filed under the local hour holding its midpoint instead
        /// (01:30 to 02:30 becomes 02:00). A start already on the hour is kept
        /// as is, so DST transitions in whole-hour zones are untouched.
        func hourLabel(_ start: Date) -> String {
            let exact = dateTimeString(start)
            if exact.hasSuffix(":00") { return exact }
            return wholeHour.string(from: start.addingTimeInterval(30 * 60))
        }
    }

    // MARK: - Units

    /// Conversions from whatever unit string arrived to what the app expects.
    /// Each reads the wire unit rather than trusting the METRIC request.
    static func temperature(_ value: Double, unit: String?, to target: TemperatureUnit) -> Double {
        let celsius = unit == "FAHRENHEIT" ? (value - 32) * 5 / 9 : value
        return target == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    static func speed(_ value: Double, unit: String?, to target: SpeedUnit) -> Double {
        let kmh = unit == "MILES_PER_HOUR" ? value * 1.609344 : value
        switch target {
        case .kmh: return kmh
        case .mph: return kmh / 1.609344
        case .ms: return kmh / 3.6
        }
    }

    static func depthMillimetres(_ value: Double, unit: String?) -> Double {
        unit == "INCHES" ? value * 25.4 : value
    }

    /// Millimetres to Open-Meteo's precipitation unit ("inch" or "mm").
    static func precipitationDepth(millimetres: Double, precipUnitAPI: String) -> Double {
        precipUnitAPI == "inch" ? millimetres / 25.4 : millimetres
    }

    /// Google's `snowQpf` is snow as liquid water equivalent; Open-Meteo's
    /// `snowfall_sum` is settled depth, centimetres under metric and inches
    /// under imperial (the thresholds in Insights and the notification planner
    /// assume those). Open-Meteo's own ratio is 7 cm of snow per 10 mm of
    /// water, so the depth is seven times the equivalent before the unit change.
    static func snowfallDepth(waterEquivalentMillimetres: Double, precipUnitAPI: String) -> Double {
        let depthMillimetres = waterEquivalentMillimetres * 7
        return precipUnitAPI == "inch" ? depthMillimetres / 25.4 : depthMillimetres / 10
    }

    static func distanceMetres(_ value: Double, unit: String?) -> Double {
        unit == "MILES" ? value * 1609.344 : value * 1000
    }

    private static func depthMillimetres(_ depth: Wire.Depth?) -> Double {
        depthMillimetres(depth?.quantity ?? 0, unit: depth?.unit)
    }

    /// The wire temperature in Celsius regardless of the user's unit, for the
    /// fog rule. Nil when the whole object is absent (unset, not 0 °C).
    private static func celsius(_ t: Wire.Temperature?) -> Double? {
        t.map { temperature($0.degrees ?? 0, unit: $0.unit, to: .celsius) }
    }

    /// Wire visibility in metres, nil when the object is absent.
    private static func visibilityMetres(_ v: Wire.Visibility?) -> Double? {
        v.map { distanceMetres($0.distance ?? 0, unit: $0.unit) }
    }

    /// The user's unit choice, applied to optional wire leaves with the
    /// proto3 zero default baked in before conversion (an absent 0 °C must
    /// become 32 °F, not 0 °F).
    private struct Units {
        let temperatureUnit: TemperatureUnit
        let speedUnit: SpeedUnit
        let precipAPI: String

        func temperature(_ t: Wire.Temperature?) -> Double {
            WeatherNextService.temperature(t?.degrees ?? 0, unit: t?.unit, to: temperatureUnit)
        }

        func speed(_ s: Wire.Speed?) -> Double {
            WeatherNextService.speed(s?.value ?? 0, unit: s?.unit, to: speedUnit)
        }

        func precipitation(_ d: Wire.Depth?) -> Double {
            WeatherNextService.precipitationDepth(
                millimetres: WeatherNextService.depthMillimetres(d?.quantity ?? 0, unit: d?.unit),
                precipUnitAPI: precipAPI)
        }

        /// Always metres: the display layer and SunQuality read metres, and
        /// WeatherService normalises the classic path to match.
        func visibility(_ v: Wire.Visibility?) -> Double {
            WeatherNextService.distanceMetres(v?.distance ?? 0, unit: v?.unit)
        }
    }
}
