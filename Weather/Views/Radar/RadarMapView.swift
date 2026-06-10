//
//  RadarMapView.swift
//  Weather
//
//  A dark/light MapKit map with an animated precipitation-forecast heatmap. The
//  per-hour frames are precomputed into tiny images once; stepping through time
//  just swaps the renderer's image, so playback is instant and flicker-free.
//

import SwiftUI
import MapKit
import UIKit

extension Place {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RadarMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let field: RadarField?
    let currentIndex: Int
    /// Light Apple Maps by day, dark by night — matched to the location.
    var isDay: Bool = false
    /// Degrees of latitude shown — smaller is more zoomed in.
    var span: CLLocationDegrees = 4.5

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = isDay ? .light : .dark

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false

        map.setRegion(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        ), animated: false)

        let marker = MKPointAnnotation()
        marker.coordinate = center
        map.addAnnotation(marker)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let style: UIUserInterfaceStyle = isDay ? .light : .dark
        if map.overrideUserInterfaceStyle != style { map.overrideUserInterfaceStyle = style }
        context.coordinator.update(field: field, index: currentIndex, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var token: String?
        private var images: [UIImage?] = []
        private var index = 0
        private var overlay: PrecipHeatOverlay?
        private weak var renderer: PrecipHeatRenderer?

        func update(field: RadarField?, index: Int, on map: MKMapView) {
            guard let field else { return }
            self.index = index

            // Rebuild the overlay + frame images only when a new field arrives.
            if token != field.token {
                token = field.token
                if let overlay { map.removeOverlay(overlay) }
                images = field.frames.map {
                    PrecipHeat.image(values: $0.values, cols: field.cols, rows: field.rows)
                }
                let o = PrecipHeatOverlay(center: field.center, halfSpan: field.halfSpan)
                overlay = o
                map.addOverlay(o, level: .aboveLabels)
            }

            if let renderer, images.indices.contains(index) {
                renderer.image = images[index]
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heat = overlay as? PrecipHeatOverlay {
                let r = PrecipHeatRenderer(overlay: heat)
                r.image = images.indices.contains(index) ? images[index] : nil
                renderer = r
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "place"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.glyphImage = UIImage(systemName: "mappin")
            // A friendly blue reads on both the light (day) and dark (night) map.
            view.markerTintColor = UIColor(red: 0.20, green: 0.52, blue: 0.96, alpha: 1)
            view.displayPriority = .required
            view.animatesWhenAdded = false
            return view
        }
    }
}
