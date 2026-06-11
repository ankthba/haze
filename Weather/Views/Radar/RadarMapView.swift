//
//  RadarMapView.swift
//  Weather
//
//  A dark/light MapKit map with an animated radar tile overlay. Every frame is
//  an XYZ tile layer (IEM observed/forecast, or RainViewer); the coordinator
//  swaps the overlay per frame, keeping the previous one beneath so there's no
//  blank gap while tiles load. The camera is locked so the view can't scroll off
//  the data or into unsupported zoom levels.
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
    var span: CLLocationDegrees = 6

    /// Softened so the radar reads as a gentle wash over the map, not a slab.
    private let tileAlpha: CGFloat = 0.6

    func makeCoordinator() -> Coordinator { Coordinator(tileAlpha: tileAlpha) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = isDay ? .light : .dark

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        // Lock the camera: radar tiles only cover certain zoom levels/areas, so
        // free pan/zoom would scroll into emptiness or unsupported tiles.
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isZoomEnabled = false
        map.isScrollEnabled = false
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
        private let tileAlpha: CGFloat
        private var token: String?
        private var frames: [RadarFrame] = []
        private var queue: [MKTileOverlay] = []   // oldest → newest, capped at 2
        private var shownTemplate: String?

        init(tileAlpha: CGFloat) { self.tileAlpha = tileAlpha }

        func update(field: RadarField?, index: Int, on map: MKMapView) {
            guard let field else { return }
            if token != field.token {
                token = field.token
                frames = field.frames
                map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
                queue.removeAll()
                shownTemplate = nil
            }
            guard frames.indices.contains(index) else { return }
            show(frames[index].urlTemplate, on: map)
        }

        private func show(_ template: String, on map: MKMapView) {
            guard template != shownTemplate else { return }
            shownTemplate = template

            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 256, height: 256)
            overlay.minimumZ = 1
            overlay.maximumZ = 10
            map.addOverlay(overlay, level: .aboveLabels)
            queue.append(overlay)
            while queue.count > 2 { map.removeOverlay(queue.removeFirst()) }
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
            view.markerTintColor = UIColor(red: 0.20, green: 0.52, blue: 0.96, alpha: 1)
            view.displayPriority = .required
            view.animatesWhenAdded = false
            return view
        }
    }
}
