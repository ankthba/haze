//
//  UVIndex.swift
//  Weather
//
//  The UV index, computed here from the sun's height, the ozone column and
//  the app's own cloud forecast, instead of read off a feed.
//
//  Why: the index Open-Meteo relays comes from the CAMS global model at
//  40 km. Checked against the NWS/EPA forecast for the same afternoons it ran
//  about a quarter low under clear sky (Austin 7.8 against 10, Denver 7.5
//  against 10), and its own cloud field disagreed with the cloud cover the
//  app prints one row below it, so a 100% overcast hour could carry a
//  "High" UV. Building the number from first principles keeps the UV row
//  consistent with the rest of the forecast: the same sun, the same clouds.
//  The same two afternoons come out at 10.5 and 8.8 here.
//
//  The model, each piece published and well worn:
//    clear sky   Madronich (2007): UVI = 12.50 mu0^2.42 (O3/300)^-1.23, with
//                mu0 the cosine of the solar zenith angle and O3 the ozone
//                column in Dobson units. Within a few percent of full
//                radiative transfer for a clean, aerosol-free sea-level sky.
//    aerosol     a fixed 8% off that fit for the haze of an ordinary clear
//                sky; measured clear-sky UV runs 5 to 10% under the
//                aerosol-free calculation, and without it a clear Texas
//                afternoon reads a band higher than the NWS index.
//    ozone       monthly zonal means from the satellite record. Real columns
//                wander a few percent around them day to day, which moves
//                the index by under a point, the same order as the official
//                forecasts' own error.
//    altitude    +6% per kilometre, as in the NWS method (Long et al. 1996).
//    clouds      the NWS transmission anchors (Long et al. 1996): clear 100%,
//                scattered 89%, broken 73%, overcast 31%, applied to the
//                opaque low and mid decks. Thin high cloud costs at most 15%.
//

import Foundation

nonisolated enum UVIndex {

    // MARK: - The index at a moment

    /// The erythemal UV index at `date` for a place, given the cloud layers
    /// the forecast carries for that hour (percent; any may be missing, and a
    /// missing layer counts as clear).
    static func value(at date: Date, latitude: Double, longitude: Double,
                      elevation: Double = 0,
                      cloudLow: Double? = nil, cloudMid: Double? = nil,
                      cloudHigh: Double? = nil) -> Double {
        let sun = SunPosition.elevation(date: date, latitude: latitude, longitude: longitude)
        guard sun > 0 else { return 0 }
        let ozone = ozoneColumn(latitude: latitude, date: date)
        let clear = clearSky(sunElevation: sun, ozone: ozone, elevation: elevation)
        return clear * cloudTransmission(low: cloudLow, mid: cloudMid, high: cloudHigh)
    }

    // MARK: - Clear sky

    /// Madronich's clear-sky index for a sun `sunElevation` degrees above the
    /// horizon, an `ozone` column in Dobson units, and a surface `elevation`
    /// in metres.
    static func clearSky(sunElevation: Double, ozone: Double, elevation: Double = 0) -> Double {
        guard sunElevation > 0 else { return 0 }
        let mu0 = sin(sunElevation * .pi / 180)
        let aerosolFree = 12.50 * pow(mu0, 2.42) * pow(ozone / 300, -1.23)
        return aerosolFree * aerosolTransmission * (1 + 0.06 * max(0, elevation) / 1000)
    }

    /// What an ordinary clear sky's haze lets through of the aerosol-free fit.
    static let aerosolTransmission = 0.92

    // MARK: - Ozone

    /// The total ozone column (Dobson units) for a latitude and date.
    static func ozoneColumn(latitude: Double, date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        return ozoneColumn(latitude: latitude, dayOfYear: Double(day))
    }

    /// Monthly zonal means from the satellite record (the TOMS/OMI era),
    /// read bilinearly across latitude and the year. Day to day the real
    /// column wanders a few percent either side of these, which moves the
    /// index by well under a point.
    static func ozoneColumn(latitude: Double, dayOfYear: Double) -> Double {
        // Latitude bands run 80S to 80N in ten-degree steps; months run
        // January to December with each value pinned to mid-month.
        let lat = min(80, max(-80, latitude))
        let row = (lat + 80) / 10
        let r0 = Int(row.rounded(.down)), r1 = min(zonalOzone.count - 1, r0 + 1)
        let rt = row - Double(r0)

        let month = ((dayOfYear - 15.2) / 30.44).truncatingRemainder(dividingBy: 12)
        let m = month < 0 ? month + 12 : month
        let m0 = Int(m.rounded(.down)) % 12, m1 = (m0 + 1) % 12
        let mt = m - Double(Int(m.rounded(.down)))

        func at(_ r: Int) -> Double {
            zonalOzone[r][m0] + (zonalOzone[r][m1] - zonalOzone[r][m0]) * mt
        }
        return at(r0) + (at(r1) - at(r0)) * rt
    }

    /// Dobson units, 80S to 80N by January to December.
    private static let zonalOzone: [[Double]] = [
        // Jan  Feb  Mar  Apr  May  Jun  Jul  Aug  Sep  Oct  Nov  Dec
        [300, 285, 275, 270, 265, 265, 260, 240, 190, 200, 260, 300],  // 80S
        [300, 285, 275, 270, 270, 275, 275, 265, 225, 210, 260, 300],  // 70S
        [300, 290, 285, 285, 295, 310, 325, 335, 320, 295, 305, 305],  // 60S
        [300, 292, 288, 292, 305, 320, 335, 350, 355, 350, 330, 312],  // 50S
        [285, 280, 278, 282, 292, 305, 320, 335, 340, 335, 315, 298],  // 40S
        [270, 265, 265, 268, 275, 285, 298, 310, 315, 310, 292, 278],  // 30S
        [258, 255, 255, 258, 262, 268, 278, 288, 292, 288, 275, 265],  // 20S
        [250, 248, 250, 252, 258, 262, 268, 272, 275, 272, 262, 255],  // 10S
        [248, 246, 248, 254, 259, 262, 265, 266, 265, 262, 255, 250],  // Equator
        [246, 246, 250, 260, 266, 266, 265, 264, 262, 258, 250, 245],  // 10N
        [252, 257, 268, 278, 282, 280, 274, 268, 265, 260, 250, 248],  // 20N
        [278, 288, 302, 308, 302, 294, 284, 278, 278, 272, 268, 270],  // 30N
        [305, 322, 340, 338, 326, 314, 300, 292, 288, 282, 285, 292],  // 40N
        [330, 352, 368, 362, 345, 326, 310, 296, 292, 285, 292, 312],  // 50N
        [340, 372, 395, 388, 365, 336, 315, 300, 293, 285, 292, 318],  // 60N
        [335, 380, 420, 410, 380, 345, 320, 302, 292, 282, 290, 315],  // 70N
        [320, 370, 430, 425, 390, 350, 322, 303, 290, 280, 285, 305],  // 80N
    ]

    // MARK: - Clouds

    /// The fraction of clear-sky UV that reaches the ground under the given
    /// cloud layers (percent cover, any may be missing).
    static func cloudTransmission(low: Double?, mid: Double?, high: Double?) -> Double {
        let lowCover = fraction(low), midCover = fraction(mid), highCover = fraction(high)
        // Two opaque decks overlapping at random: blocked wherever either is.
        let opaque = 1 - (1 - lowCover) * (1 - midCover)
        return opaqueTransmission(cover: opaque) * (1 - 0.15 * highCover)
    }

    /// Long et al.'s forecaster anchors, joined by straight lines: clear 1.00,
    /// scattered (about 4 oktas) 0.89, broken (about 6 oktas) 0.73,
    /// overcast 0.31.
    static func opaqueTransmission(cover: Double) -> Double {
        let anchors: [(cover: Double, transmission: Double)] = [
            (0, 1.0), (0.4, 0.89), (0.75, 0.73), (1, 0.31)
        ]
        let c = min(1, max(0, cover))
        for (a, b) in zip(anchors, anchors.dropFirst()) where c <= b.cover {
            let t = (c - a.cover) / (b.cover - a.cover)
            return a.transmission + (b.transmission - a.transmission) * t
        }
        return anchors.last?.transmission ?? 1
    }

    private static func fraction(_ percent: Double?) -> Double {
        min(1, max(0, (percent ?? 0) / 100))
    }
}

// MARK: - Today's story

/// Today's UV, read out of a bundle for the captions and the detail sheet:
/// what it is now, when it peaks, and the stretch of the day that calls for
/// protection.
nonisolated struct UVOutlook {
    /// An index at or above this calls for protection (WHO guidance).
    static let protectionThreshold: Double = 3

    /// Whether a reading counts as strong, judged on the whole number the
    /// user sees, so a 2.6 that prints as "3" is treated as a 3.
    static func isStrong(_ value: Double) -> Bool {
        max(0, value).rounded() >= protectionThreshold
    }

    /// The index now.
    let now: Double
    let sunIsUp: Bool
    /// True once today's sun has gone down (not merely not yet risen).
    let sunHasSet: Bool
    /// Today's strongest hour, if the sun gets up at all.
    let peak: (value: Double, date: Date)?
    /// Today's stretch at or above the threshold, clipped to the live
    /// reading so it never contradicts the headline number.
    let protection: ClosedRange<Date>?
    /// Tomorrow's peak, for the evening caption.
    let tomorrowPeak: Double?
    let referenceDate: Date

    init(bundle: WeatherBundle, now: Date = Date()) {
        referenceDate = now
        self.now = bundle.current.uvIndex ?? 0

        // The day that contains `now`, found by date rather than by position:
        // a cached bundle can be a day old, and its first day is then
        // yesterday.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = bundle.timezone
        let todayIndex = bundle.daily.firstIndex { cal.isDate($0.date, inSameDayAs: now) }
        let today = todayIndex.map { bundle.daily[$0] }

        if let sunrise = today?.sunrise, let sunset = today?.sunset {
            sunIsUp = now >= sunrise && now < sunset
            sunHasSet = now >= sunset
        } else {
            let up = SunPosition.elevation(date: now, latitude: bundle.place.latitude,
                                           longitude: bundle.place.longitude) > 0
            sunIsUp = up
            // Without sun times, "set" means the sun is down in the local
            // afternoon or later.
            sunHasSet = !up && cal.component(.hour, from: now) >= 12
        }

        let hours = bundle.hours(on: now)
        if let strongest = hours.max(by: { $0.uvIndex < $1.uvIndex }), strongest.uvIndex >= 0.5 {
            peak = (strongest.uvIndex, strongest.date)
        } else {
            peak = nil
        }

        let strong = hours.filter { Self.isStrong($0.uvIndex) }
        var window: ClosedRange<Date>?
        if let first = strong.first, let last = strong.last {
            var start = first.date
            var finish = last.date.addingTimeInterval(3600)
            // Clip to what the live reading says: if it already prints as
            // strong the window is open now; if it has dropped below after
            // the peak, the window is over.
            let strongNow = Self.isStrong(self.now)
            if strongNow, now < start { start = now }
            if !strongNow, let peak {
                if now > peak.date, now < finish {
                    finish = now
                } else if now < peak.date, now >= start, let next = strong.first(where: { $0.date > now }) {
                    start = next.date
                }
            }
            window = start <= finish ? start...finish : nil
        }
        protection = window

        tomorrowPeak = todayIndex.flatMap { index in
            bundle.daily.indices.contains(index + 1) ? bundle.daily[index + 1].uvIndexMax : nil
        }
    }

    // MARK: Bands

    struct Band: Equatable {
        let name: String
        let range: String
        let advice: String
        /// The lowest whole-number index in the band.
        let lower: Double
    }

    /// The WHO bands with their advice, in one line each.
    static let bands: [Band] = [
        Band(name: "Low", range: "0–2", advice: "Safe to stay outside", lower: 0),
        Band(name: "Moderate", range: "3–5", advice: "Shade at midday, hat and sunscreen", lower: 3),
        Band(name: "High", range: "6–7", advice: "Cover up, shade through midday", lower: 6),
        Band(name: "Very High", range: "8–10", advice: "Extra care, stay out of the midday sun", lower: 8),
        Band(name: "Extreme", range: "11+", advice: "Avoid the midday sun altogether", lower: 11),
    ]

    static func band(for value: Double) -> Band {
        let rounded = max(0, value).rounded()
        return bands.last { rounded >= $0.lower } ?? bands[0]
    }

    // MARK: Copy

    /// The one-line caption under the UV row on the home screen: the band,
    /// then the part of the day's story that is still ahead.
    func caption(timezone: TimeZone) -> String {
        let band = Fmt.uvLabel(now)
        if !sunIsUp {
            if let peak, peak.date > referenceDate {
                return "Sun's down, reaches \(Fmt.uv(peak.value)) near \(Fmt.hour(peak.date, timezone: timezone))"
            }
            if let tomorrowPeak, tomorrowPeak >= 0.5 {
                return "Sun's down, reaches \(Fmt.uv(tomorrowPeak)) tomorrow"
            }
            return "Sun's down"
        }
        if let peak, peak.date > referenceDate.addingTimeInterval(1800), peak.value > now + 0.5 {
            return "\(band), reaches \(Fmt.uv(peak.value)) near \(Fmt.hour(peak.date, timezone: timezone))"
        }
        if let protection, protection.upperBound > referenceDate, Self.isStrong(now) {
            return "\(band), easing by \(Fmt.hour(protection.upperBound, timezone: timezone))"
        }
        return "\(band) for the rest of the day"
    }

    /// The sentence on the detail sheet: when to cover up, in either voice.
    func protectionLine(timezone: TimeZone, voice: Voice) -> String {
        let threshold = Fmt.uv(Self.protectionThreshold)
        if let protection, protection.upperBound > referenceDate {
            let until = Fmt.hour(protection.upperBound, timezone: timezone)
            if protection.lowerBound > referenceDate {
                let from = Fmt.hour(protection.lowerBound, timezone: timezone)
                return voice.pick(
                    "Sun protection from \(from) to \(until), while the index sits at \(threshold) or higher.",
                    whimsy: "Hat and sunscreen territory from \(from) to \(until), when the index sits at \(threshold) or higher.")
            }
            return voice.pick(
                "Sun protection until \(until), while the index stays at \(threshold) or higher.",
                whimsy: "Hat and sunscreen until \(until), the index is still \(threshold) or higher.")
        }
        if sunHasSet, let tomorrowPeak, Self.isStrong(tomorrowPeak) {
            return voice.pick(
                "Nothing to shade from tonight. Tomorrow reaches \(Fmt.uv(tomorrowPeak)).",
                whimsy: "Nothing to shade from tonight. Tomorrow climbs to \(Fmt.uv(tomorrowPeak)).")
        }
        guard let peak else {
            // The sun never gets up enough to register: polar night, or the
            // depths of a high-latitude winter.
            return voice.pick(
                "The index stays at 0 today, so no sun protection needed.",
                whimsy: "Barely any sun to speak of today, nothing to shield against.")
        }
        if Self.isStrong(peak.value) {
            return voice.pick(
                "Past the strong hours. The index stays under \(threshold) for the rest of the day.",
                whimsy: "The strong hours are behind you, easy sun from here.")
        }
        return voice.pick(
            "The index stays under \(threshold) today, so no sun protection needed.",
            whimsy: "A gentle sun today, nothing to shield against.")
    }
}
