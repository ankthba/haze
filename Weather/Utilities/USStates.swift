//
//  USStates.swift
//  Weather
//
//  Apple's reverse geocoder gives US states as 2-letter codes ("VA"), while
//  Open-Meteo's search gives full names ("Virginia"). This expands the codes so
//  the location subtitle reads consistently across both sources.
//

import Foundation

enum USStates {
    /// Expand a US state code to its full name. Leaves anything else untouched
    /// (non-US, already-full names, nil).
    static func expand(_ value: String?, countryCode: String?) -> String? {
        guard let value else { return nil }
        let isUS = (countryCode?.uppercased() == "US") || countryCode == nil
        guard isUS, value.count == 2 else { return value }
        return names[value.uppercased()] ?? value
    }

    private static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "District of Columbia"
    ]
}
