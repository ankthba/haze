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

        // Drop the Apple Maps attribution below the floating controls panel:
        // by default it hugs the safe area, which is exactly where the panel
        // sits, leaving the logo covered. Ignoring the safe-area margin lets
        // it sit near the very bottom edge, in the clear.
        map.insetsLayoutMarginsFromSafeArea = false
        map.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 6, right: 12)

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
        /// One persistent overlay per frame, all added the moment the field
        /// arrives — the locked camera means each frame is only a handful of
        /// tiles, and preloading them all is what makes playback and scrubbing
        /// flicker-free. Overlays are never removed (removal cancels in-flight
        /// tile loads and used to leave the map blank after a manual scrub);
        /// visibility is flipped purely via renderer alpha.
        private var overlays: [Int: MKTileOverlay] = [:]
        private var currentIndex = -1
        private var previousIndex = -1

        init(tileAlpha: CGFloat) { self.tileAlpha = tileAlpha }

        func update(field: RadarField?, index: Int, on map: MKMapView) {
            guard let field else { return }
            if token != field.token {
                token = field.token
                frames = field.frames
                map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
                overlays.removeAll()
                currentIndex = -1
                previousIndex = -1

                // Add every frame's overlay now (alpha 0) so all tiles start
                // caching immediately instead of on first visit.
                for (i, frame) in frames.enumerated() {
                    let overlay = MKTileOverlay(urlTemplate: frame.urlTemplate)
                    overlay.canReplaceMapContent = false
                    overlay.tileSize = CGSize(width: 256, height: 256)
                    overlay.minimumZ = 1
                    overlay.maximumZ = 10
                    overlays[i] = overlay
                    map.addOverlay(overlay, level: .aboveLabels)
                }
            }
            guard frames.indices.contains(index), index != currentIndex else { return }
            previousIndex = currentIndex
            currentIndex = index
            applyAlphas(on: map)
        }

        /// The current frame draws at full strength; the frame we just left
        /// stays at full strength *beneath* it so radar echoes never blink out
        /// while the new frame's tiles finish painting. Everything else is
        /// transparent but stays cached.
        private func applyAlphas(on map: MKMapView) {
            for (index, overlay) in overlays {
                guard let renderer = map.renderer(for: overlay) as? MKTileOverlayRenderer else { continue }
                renderer.alpha = alpha(for: index)
            }
        }

        private func alpha(for index: Int) -> CGFloat {
            if index == currentIndex || index == previousIndex { return tileAlpha }
            return 0
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                let index = overlays.first(where: { $0.value === tile })?.key
                renderer.alpha = index.map(alpha(for:)) ?? tileAlpha
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
