//
//  RadarMapView.swift
//  Weather
//
//  A dark, muted MapKit map with an animated precipitation-radar tile overlay.
//  The visible frame is driven from SwiftUI; the coordinator swaps tile overlays
//  as the frame changes. MapKit caches tiles by URL, so playback is smooth once
//  a loop has been seen.
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
    let host: String
    let frame: RadarFrame?
    let colorScheme: Int
    /// Degrees of latitude shown — smaller is more zoomed in.
    var span: CLLocationDegrees = 5

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        map.setRegion(region, animated: false)

        // A quiet pin for the selected place.
        let marker = MKPointAnnotation()
        marker.coordinate = center
        map.addAnnotation(marker)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.show(frame: frame, host: host, color: colorScheme, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var shownPath: String?

        func show(frame: RadarFrame?, host: String, color: Int, on map: MKMapView) {
            guard let frame, frame.path != shownPath else { return }
            shownPath = frame.path

            let template = RainViewerService.tileTemplate(host: host, frame: frame, color: color)
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 256, height: 256)

            // Paint the new frame above the old, then drop the previous overlays a
            // beat later so there's no gap mid-swap (cached tiles appear instantly).
            let previous = map.overlays.compactMap { $0 as? MKTileOverlay }
            map.addOverlay(overlay, level: .aboveLabels)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                for old in previous { map.removeOverlay(old) }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.82
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "place"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.glyphImage = UIImage(systemName: "mappin")
            view.markerTintColor = .white
            view.displayPriority = .required
            view.animatesWhenAdded = false
            return view
        }
    }
}
