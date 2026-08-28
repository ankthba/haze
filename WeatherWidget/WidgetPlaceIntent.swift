//
//  WidgetPlaceIntent.swift
//  WeatherWidget
//
//  Widget configuration: by default a widget follows the device, but editing
//  it offers the app's saved cities so a widget can be pinned to one. The app
//  mirrors its saved-places list into the App Group; the entity query reads it.
//

import AppIntents
import Foundation

/// The saved-places mirror the app writes. Matches the app's copy in
/// `Weather/Services/WidgetSharing.swift` — keep the two in sync.
nonisolated struct WidgetSavedPlace: Codable {
    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
}

extension WeatherSnapshotStore {
    /// Called from the entity query's nonisolated async context.
    nonisolated static func readSavedPlaces() -> [WidgetSavedPlace] {
        guard let data = UserDefaults(suiteName: appGroup)?
            .data(forKey: "weather_widget_saved_places_v1") else { return [] }
        return (try? JSONDecoder().decode([WidgetSavedPlace].self, from: data)) ?? []
    }

    // MARK: Per-place snapshot cache (pinned widgets)

    /// The temperature unit is part of the key, so a unit change is a cache
    /// miss instead of an hour of stale Fahrenheit on a pinned widget.
    private static func snapshotKey(forPlaceID id: String, unit: String) -> String {
        "weather_widget_snapshot_v1_place_\(id)_\(unit)"
    }

    static func read(forPlaceID id: String, unit: String) -> WeatherWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?
            .data(forKey: snapshotKey(forPlaceID: id, unit: unit)) else { return nil }
        return try? JSONDecoder().decode(WeatherWidgetSnapshot.self, from: data)
    }

    static func cache(_ snapshot: WeatherWidgetSnapshot, forPlaceID id: String, unit: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: snapshotKey(forPlaceID: id, unit: unit))
    }
}

// MARK: - Entity

struct WidgetPlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static let defaultQuery = WidgetPlaceQuery()

    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: subtitle.isEmpty ? nil : "\(subtitle)")
    }

    init(place: WidgetSavedPlace) {
        id = place.id
        name = place.name
        subtitle = place.subtitle
        latitude = place.latitude
        longitude = place.longitude
    }
}

struct WidgetPlaceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetPlaceEntity] {
        WeatherSnapshotStore.readSavedPlaces()
            .filter { identifiers.contains($0.id) }
            .map(WidgetPlaceEntity.init(place:))
    }

    func suggestedEntities() async throws -> [WidgetPlaceEntity] {
        WeatherSnapshotStore.readSavedPlaces().map(WidgetPlaceEntity.init(place:))
    }
}

// MARK: - Configuration intent

struct WidgetPlaceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "City"
    static let description = IntentDescription("Choose which city this widget shows.")

    /// nil = follow the device (the app's current location snapshot).
    @Parameter(title: "City")
    var place: WidgetPlaceEntity?
}
