//
//  UVIndexTests.swift
//  WeatherTests
//
//  The UV index is computed, not fetched, so the thing to test is that the
//  pieces land where the published models say they should: a clear
//  September noon in Texas near the NWS figure of 10, nothing after dark,
//  an overcast sky letting a third through, and the captions telling the
//  right part of the day's story.
//

import Testing
import Foundation
@testable import Haze_Weather

private let utc = TimeZone(identifier: "UTC")!
private let austin = TimeZone(identifier: "America/Chicago")!

private func date(_ iso: String, in timezone: TimeZone) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timezone
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f.date(from: iso)!
}

struct SunElevationTests {
    @Test("Greenwich at equinox noon puts the sun 38 degrees up")
    func equinoxNoon() {
        let elevation = SunPosition.elevation(date: date("2026-03-20T12:00", in: utc),
                                              latitude: 51.48, longitude: 0)
        #expect(abs(elevation - 38.5) < 1)
    }

    @Test("A September afternoon in Austin, where declination matters, lands at 67 degrees")
    func austinAfternoon() {
        let elevation = SunPosition.elevation(date: date("2026-09-02T13:30", in: austin),
                                              latitude: 30.27, longitude: -97.74)
        #expect(abs(elevation - 67.4) < 0.5)
    }

    @Test("Greenwich at the June solstice noon reaches 62 degrees")
    func solsticeNoon() {
        let elevation = SunPosition.elevation(date: date("2026-06-21T12:00", in: utc),
                                              latitude: 51.48, longitude: 0)
        #expect(abs(elevation - 61.9) < 0.7)
    }

    @Test("The sun is below the horizon at midnight")
    func midnight() {
        let elevation = SunPosition.elevation(date: date("2026-09-02T00:00", in: austin),
                                              latitude: 30.27, longitude: -97.74)
        #expect(elevation < 0)
    }
}

struct UVIndexTests {
    @Test("A clear September noon in Austin lands near the NWS figure of 10")
    func austinNoon() {
        let value = UVIndex.value(at: date("2026-09-02T13:30", in: austin),
                                  latitude: 30.27, longitude: -97.74, elevation: 157)
        #expect(value > 9.9 && value < 11.1)
    }

    @Test("The ozone column bends the index by its published exponent")
    func ozoneTerm() {
        let thin = UVIndex.clearSky(sunElevation: 60, ozone: 250)
        let thick = UVIndex.clearSky(sunElevation: 60, ozone: 350)
        #expect(abs(thin / thick - pow(350.0 / 250.0, 1.23)) < 0.01)
        // The date form resolves the day of year in UTC.
        #expect(UVIndex.ozoneColumn(latitude: 40, date: date("2026-01-01T00:00", in: utc))
                == UVIndex.ozoneColumn(latitude: 40, dayOfYear: 1))
        // A spring column at 40N (about 340 DU) trims the index against
        // an autumn one (about 285 DU) at the same sun.
        let spring = UVIndex.clearSky(sunElevation: 50, ozone: UVIndex.ozoneColumn(latitude: 40, dayOfYear: 100))
        let autumn = UVIndex.clearSky(sunElevation: 50, ozone: UVIndex.ozoneColumn(latitude: 40, dayOfYear: 290))
        #expect(spring < autumn * 0.85)
    }

    @Test("Nothing after dark")
    func night() {
        let value = UVIndex.value(at: date("2026-09-02T23:00", in: austin),
                                  latitude: 30.27, longitude: -97.74,
                                  cloudLow: 0, cloudMid: 0, cloudHigh: 0)
        #expect(value == 0)
    }

    @Test("Clouds follow the NWS anchors: clear, scattered, broken, overcast")
    func cloudAnchors() {
        #expect(UVIndex.cloudTransmission(low: 0, mid: 0, high: 0) == 1)
        #expect(abs(UVIndex.cloudTransmission(low: 40, mid: 0, high: 0) - 0.89) < 0.001)
        #expect(abs(UVIndex.cloudTransmission(low: 75, mid: 0, high: 0) - 0.73) < 0.001)
        #expect(abs(UVIndex.cloudTransmission(low: 100, mid: 0, high: 0) - 0.31) < 0.001)
        // Missing layers count as clear.
        #expect(UVIndex.cloudTransmission(low: nil, mid: nil, high: nil) == 1)
    }

    @Test("Thin high cloud costs a little, an opaque deck costs a lot")
    func highVersusLow() {
        let cirrus = UVIndex.cloudTransmission(low: 0, mid: 0, high: 100)
        let stratus = UVIndex.cloudTransmission(low: 100, mid: 0, high: 0)
        #expect(cirrus > 0.8)
        #expect(stratus < 0.4)
        // Two half decks block more than one.
        #expect(UVIndex.cloudTransmission(low: 50, mid: 50, high: 0)
                < UVIndex.cloudTransmission(low: 50, mid: 0, high: 0))
    }

    @Test("Transmission never rises as cover grows")
    func monotone() {
        var previous = 1.0
        for cover in stride(from: 0.0, through: 1.0, by: 0.05) {
            let t = UVIndex.opaqueTransmission(cover: cover)
            #expect(t <= previous + 1e-9)
            previous = t
        }
    }

    @Test("Altitude adds six percent a kilometre")
    func altitude() {
        let seaLevel = UVIndex.clearSky(sunElevation: 60, ozone: 300)
        let mile = UVIndex.clearSky(sunElevation: 60, ozone: 300, elevation: 1600)
        #expect(abs(mile / seaLevel - 1.096) < 0.001)
    }

    @Test("The ozone climatology stays in the physical range everywhere, poles included")
    func ozoneRange() {
        for latitude in stride(from: -90.0, through: 90.0, by: 5) {
            for day in stride(from: 1.0, through: 366.0, by: 7) {
                let column = UVIndex.ozoneColumn(latitude: latitude, dayOfYear: day)
                #expect(column > 150 && column < 470)
            }
        }
    }

    @Test("Mid-latitude ozone peaks in spring in either hemisphere")
    func ozoneSeason() {
        #expect(UVIndex.ozoneColumn(latitude: 45, dayOfYear: 100)
                > UVIndex.ozoneColumn(latitude: 45, dayOfYear: 290))
        #expect(UVIndex.ozoneColumn(latitude: -45, dayOfYear: 280)
                > UVIndex.ozoneColumn(latitude: -45, dayOfYear: 100))
    }

    @Test("Interpolation is seamless across the year's end")
    func ozoneWrap() {
        let lastDay = UVIndex.ozoneColumn(latitude: 40, dayOfYear: 365)
        let firstDay = UVIndex.ozoneColumn(latitude: 40, dayOfYear: 1)
        #expect(abs(lastDay - firstDay) < 3)
    }

    @Test("Denver's altitude lifts a September noon to within a point of the NWS figure")
    func denverNoon() {
        let denver = TimeZone(identifier: "America/Denver")!
        let value = UVIndex.value(at: date("2026-09-02T13:00", in: denver),
                                  latitude: 39.74, longitude: -104.99, elevation: 1599)
        #expect(value > 8.3 && value < 9.4)
    }
}

// MARK: - Outlook

/// A day in Austin whose hours carry the given index profile.
private func makeBundle(now: Date, hourly uv: [Double], tomorrowPeak: Double? = nil,
                        currentUV: Double? = nil, fetchedDaysAgo: Int = 0) -> WeatherBundle {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = austin
    let startOfDay = cal.startOfDay(for: now)

    let hours: [HourPoint] = (0..<24).map { hour in
        HourPoint(date: startOfDay.addingTimeInterval(Double(hour) * 3600),
                  temperature: 85, apparentTemperature: 85, code: 1, isDay: (7..<20).contains(hour),
                  precipitationProbability: 0, precipitation: 0,
                  windSpeed: 5, windDirection: 180, humidity: 50,
                  uvIndex: uv[hour])
    }
    func day(_ start: Date, peak: Double) -> DayForecast {
        DayForecast(date: start, code: 1, tempMax: 95, tempMin: 72, apparentMax: 98, apparentMin: 72,
                    sunrise: start.addingTimeInterval(7 * 3600 + 5 * 60),
                    sunset: start.addingTimeInterval(19 * 3600 + 50 * 60),
                    uvIndexMax: peak, precipitationSum: 0, precipitationProbabilityMax: 0,
                    windSpeedMax: 8, windGustMax: 12, windDirectionDominant: 180)
    }
    var days: [DayForecast] = []
    for back in stride(from: fetchedDaysAgo, to: 0, by: -1) {
        days.append(day(startOfDay.addingTimeInterval(-86_400 * Double(back)), peak: 9))
    }
    days.append(day(startOfDay, peak: uv.max() ?? 0))
    if let tomorrowPeak {
        days.append(day(startOfDay.addingTimeInterval(86_400), peak: tomorrowPeak))
    }
    // The live figure: the hour's value unless the test says otherwise.
    let hourNow = cal.component(.hour, from: now)
    return WeatherBundle(
        place: Place(name: "Austin", admin1: "Texas", country: "United States",
                     countryCode: "US", latitude: 30.27, longitude: -97.74,
                     timezone: austin.identifier),
        timezone: austin,
        current: CurrentWeather(
            date: now, temperature: 85, apparentTemperature: 85, code: 1,
            isDay: (7..<20).contains(hourNow), humidity: 50, precipitation: 0, cloudCover: 10,
            pressure: 1014, windSpeed: 5, windGust: 8, windDirection: 180,
            uvIndex: currentUV ?? uv[hourNow], visibility: 16000, dewPoint: 60),
        hourly: hours, daily: days, airQuality: nil, fetchedAt: now)
}

/// The hour label exactly as the app prints it (the formatter may use a
/// narrow no-break space before "PM"), so expectations never hand-type it.
private func hour(_ iso: String) -> String {
    Fmt.hour(date(iso, in: austin), timezone: austin)
}

/// A textbook clear day: up from 8, ten at one, gone by eight.
private let clearDay: [Double] = [0, 0, 0, 0, 0, 0, 0, 0.2, 1.2, 2.9, 4.7, 6.4, 8.1, 9.6, 10, 9.4,
                                  7.6, 5.2, 2.9, 1.1, 0.2, 0, 0, 0]

struct UVOutlookTests {
    @Test("Before the peak the caption looks ahead to it")
    func morning() {
        let now = date("2026-09-02T08:30", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay), now: now)
        #expect(outlook.sunIsUp)
        #expect(outlook.caption(timezone: austin) == "Low, reaches 10 near \(hour("2026-09-02T14:00"))")
        // The 9 AM sample of 2.9 prints as 3, so the window opens at 9.
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Sun protection from \(hour("2026-09-02T09:00")) to \(hour("2026-09-02T19:00")), while the index sits at 3 or higher.")
        #expect(outlook.protectionLine(timezone: austin, voice: .whimsical)
                == "Hat and sunscreen territory from \(hour("2026-09-02T09:00")) to \(hour("2026-09-02T19:00")), when the index sits at 3 or higher.")
    }

    @Test("After the peak the caption says when it eases")
    func afternoon() {
        let now = date("2026-09-02T17:10", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay), now: now)
        #expect(outlook.caption(timezone: austin) == "Moderate, easing by \(hour("2026-09-02T19:00"))")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Sun protection until \(hour("2026-09-02T19:00")), while the index stays at 3 or higher.")
        #expect(outlook.protectionLine(timezone: austin, voice: .whimsical)
                == "Hat and sunscreen until \(hour("2026-09-02T19:00")), the index is still 3 or higher.")
    }

    @Test("Once it has faded, the rest of the day is low")
    func evening() {
        let now = date("2026-09-02T19:20", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay), now: now)
        #expect(outlook.caption(timezone: austin) == "Low for the rest of the day")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Past the strong hours. The index stays under 3 for the rest of the day.")
    }

    @Test("At night the caption points at tomorrow, and before dawn at today")
    func night() {
        let late = date("2026-09-02T22:00", in: austin)
        let evening = UVOutlook(bundle: makeBundle(now: late, hourly: clearDay, tomorrowPeak: 7.4),
                                now: late)
        #expect(!evening.sunIsUp)
        #expect(evening.caption(timezone: austin) == "Sun's down, reaches 7 tomorrow")
        #expect(evening.protectionLine(timezone: austin, voice: .editorial)
                == "Nothing to shade from tonight. Tomorrow reaches 7.")

        let early = date("2026-09-02T05:00", in: austin)
        let dawn = UVOutlook(bundle: makeBundle(now: early, hourly: clearDay), now: early)
        #expect(dawn.caption(timezone: austin) == "Sun's down, reaches 10 near \(hour("2026-09-02T14:00"))")
    }

    @Test("A mild day needs no protection")
    func mildDay() {
        let profile: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0.3, 0.8, 1.4, 1.9, 2.2, 2.3, 2.1, 1.7,
                                 1.1, 0.6, 0.2, 0, 0, 0, 0, 0]
        let now = date("2026-09-02T11:00", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: profile), now: now)
        #expect(outlook.protection == nil)
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "The index stays under 3 today, so no sun protection needed.")
    }

    @Test("The window opens as soon as the live reading prints as 3")
    func opensWithTheHeadline() {
        let now = date("2026-09-02T08:40", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay, currentUV: 2.6), now: now)
        #expect(outlook.caption(timezone: austin) == "Moderate, reaches 10 near \(hour("2026-09-02T14:00"))")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Sun protection until \(hour("2026-09-02T19:00")), while the index stays at 3 or higher.")
    }

    @Test("A morning reading still under 3 pushes the window to the next strong hour")
    func waitsForTheHeadline() {
        let now = date("2026-09-02T09:40", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay, currentUV: 2.4), now: now)
        #expect(outlook.caption(timezone: austin) == "Low, reaches 10 near \(hour("2026-09-02T14:00"))")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Sun protection from \(hour("2026-09-02T10:00")) to \(hour("2026-09-02T19:00")), while the index sits at 3 or higher.")
    }

    @Test("The window closes as soon as the live reading drops below 3 after the peak")
    func closesWithTheHeadline() {
        let now = date("2026-09-02T18:40", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: clearDay, currentUV: 2.2), now: now)
        #expect(outlook.caption(timezone: austin) == "Low for the rest of the day")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "Past the strong hours. The index stays under 3 for the rest of the day.")
    }

    @Test("A bundle fetched yesterday still finds today's sun and tomorrow's peak")
    func staleBundle() {
        let now = date("2026-09-02T10:00", in: austin)
        let bundle = makeBundle(now: now, hourly: clearDay, tomorrowPeak: 7.4, fetchedDaysAgo: 1)
        let outlook = UVOutlook(bundle: bundle, now: now)
        #expect(outlook.sunIsUp)
        #expect(!outlook.sunHasSet)
        #expect(outlook.tomorrowPeak == 7.4)
        #expect(outlook.caption(timezone: austin) == "Moderate, reaches 10 near \(hour("2026-09-02T14:00"))")
    }

    @Test("Before dawn on a mild day the card talks about today, not tonight")
    func mildDawn() {
        let profile: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0.3, 0.8, 1.4, 1.9, 2.2, 2.3, 2.1, 1.7,
                                 1.1, 0.6, 0.2, 0, 0, 0, 0, 0]
        let now = date("2026-09-02T05:30", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: profile, tomorrowPeak: 7), now: now)
        #expect(outlook.caption(timezone: austin) == "Sun's down, reaches 2 near \(hour("2026-09-02T13:00"))")
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "The index stays under 3 today, so no sun protection needed.")
    }

    @Test("When the sun never registers, neither voice invents one")
    func polarNight() {
        let now = date("2026-09-02T12:00", in: austin)
        let outlook = UVOutlook(bundle: makeBundle(now: now, hourly: Array(repeating: 0, count: 24)), now: now)
        #expect(outlook.peak == nil)
        #expect(outlook.protectionLine(timezone: austin, voice: .editorial)
                == "The index stays at 0 today, so no sun protection needed.")
        #expect(outlook.protectionLine(timezone: austin, voice: .whimsical)
                == "Barely any sun to speak of today, nothing to shield against.")
    }

    @Test("Bands follow the displayed whole number")
    func bands() {
        #expect(UVOutlook.band(for: 2.4).name == "Low")
        #expect(UVOutlook.band(for: 2.6).name == "Moderate")
        #expect(UVOutlook.band(for: 7.5).name == "Very High")
        #expect(UVOutlook.band(for: 11.2).name == "Extreme")
        #expect(Fmt.uvLabel(2.6) == "Moderate")
        #expect(Fmt.uv(2.6) == "3")
    }
}
