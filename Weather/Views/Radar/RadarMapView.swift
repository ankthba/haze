//
//  RadarMapView.swift
//  Weather
//
//  A dark, muted MapKit map with a preloaded stack of precipitation-radar tile
//  overlays — one per frame. Only the current frame is shown (others sit at zero
//  alpha), so stepping through time is an instant cel-flip with no reload flicker
//  once tiles have cached. Pass a single frame for a static preview.
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
    /// `path` of the frame to show; others stay hidden.
    let currentPath: String?
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

        let marker = MKPointAnnotation()
        marker.coordinate = center
        map.addAnnotation(marker)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.sync(frames: frames, host: host, color: colorScheme,
                                 current: currentPath, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let visibleAlpha: CGFloat = 0.85
        private var pathByOverlay: [ObjectIdentifier: String] = [:]
        private var rendererByPath: [String: MKTileOverlayRenderer] = [:]
        private var builtKey: String?
        private var currentPath: String?

        /// Build the overlay stack once per frame set, then show only `current`.
        func sync(frames: [RadarFrame], host: String, color: Int, current: String?, on map: MKMapView) {
            let key = "\(color)|" + frames.map(\.path).joined(separator: ",")
            if key != builtKey {
                builtKey = key
                map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
                pathByOverlay.removeAll()
                rendererByPath.removeAll()
                for frame in frames {
                    let template = RainViewerService.tileTemplate(host: host, frame: frame, color: color)
                    let overlay = MKTileOverlay(urlTemplate: template)
                    overlay.canReplaceMapContent = false
                    overlay.tileSize = CGSize(width: 256, height: 256)
                    pathByOverlay[ObjectIdentifier(overlay)] = frame.path
                    map.addOverlay(overlay, level: .aboveLabels)
                }
            }

            currentPath = current
            for (path, renderer) in rendererByPath {
                let target: CGFloat = (path == current) ? visibleAlpha : 0
                if renderer.alpha != target {
                    renderer.alpha = target
                    renderer.setNeedsDisplay()
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            let path = pathByOverlay[ObjectIdentifier(tile)]
            renderer.alpha = (path != nil && path == currentPath) ? visibleAlpha : 0
            if let path { rendererByPath[path] = renderer }
            return renderer
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
