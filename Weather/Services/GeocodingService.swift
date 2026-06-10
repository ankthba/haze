//
//  GeocodingService.swift
//  Weather
//
//  City search via Open-Meteo's geocoding API.
//

import Foundation

struct GeocodingService {
    func search(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "12"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.requestFailed
        }

        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (decoded.results ?? []).map {
            Place(
                name: $0.name,
                admin1: $0.admin1,
                country: $0.country,
                countryCode: $0.countryCode,
                latitude: $0.latitude,
                longitude: $0.longitude,
                timezone: $0.timezone
            )
        }
    }
}

private struct GeocodingResponse: Decodable {
    let results: [Result]?

    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let countryCode: String?
        let admin1: String?
        let timezone: String?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, country, admin1, timezone
            case countryCode = "country_code"
        }
    }
}
