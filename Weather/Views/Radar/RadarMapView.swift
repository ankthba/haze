//
//  RadarMapView.swift
//  Weather
//
//  A dark, muted MapKit map with a single precipitation-radar tile overlay that
//  is swapped as the current frame changes. MapKit caches tiles by URL, so once
//  a loop has played the replay is smooth. (Preloading one overlay per frame and
//  toggling renderer alpha does NOT work — MKOverlayRenderer caches its drawn
//  tiles and won't repaint on a live alpha change.) Pass a single frame for a
//  static preview.
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
    let frames: [RadarFrame]
    /// `path` of the frame to show.
    let currentPath: String?
    let colorScheme: Int
    /// Light Apple Maps by day, dark by night — matched to the location.
    var isDay: Bool = false
    /// Degrees of latitude shown — smaller is more zoomed in.
    var span: CLLocationDegrees = 5

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

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        map.setRegion(region, animated: false)

        let marker = MKPointAnnotation()
        marker.coordinate = center
        map.addAnnotation(marker)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let style: UIUserInterfaceStyle = isDay ? .light : .dark
        if map.overrideUserInterfaceStyle != style { map.overrideUserInterfaceStyle = style }
        context.coordinator.show(currentPath: currentPath, frames: frames,
                                 host: host, color: colorScheme, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        /// Soft, translucent radar so the colours read as a gentle wash.
        private let tileAlpha: CGFloat = 0.55
        private var queue: [MKTileOverlay] = []   // oldest → newest, capped at 2
        private var shownPath: String?

        /// Show the requested frame on top, keeping the immediately-previous frame
        /// beneath it so there's never a blank gap while the new tiles load — this
        /// is what kills the flicker. Anything older is dropped.
        func show(currentPath: String?, frames: [RadarFrame], host: String, color: Int, on map: MKMapView) {
            guard let currentPath, currentPath != shownPath,
                  let frame = frames.first(where: { $0.path == currentPath }) else { return }
            shownPath = currentPath

            // 512px tiles cover 4× the area each, so a frame fills in with far fewer
            // requests — much quicker to paint, and smoother on replay.
            let template = RainViewerService.tileTemplate(host: host, frame: frame, color: color, size: 512)
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 512, height: 512)

            map.addOverlay(overlay, level: .aboveLabels)
            queue.append(overlay)
            while queue.count > 2 {
                map.removeOverlay(queue.removeFirst())
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = tileAlpha
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
            // A friendly blue reads on both the light (day) and dark (night) map.
            view.markerTintColor = UIColor(red: 0.20, green: 0.52, blue: 0.96, alpha: 1)
            view.displayPriority = .required
            view.animatesWhenAdded = false
            return view
        }
    }
}
