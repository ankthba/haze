//
//  RadarMapView.swift
//  Weather
//
//  A dark/light MapKit map that renders a hybrid radar timeline. Detailed past
//  frames are real RainViewer radar tiles; forecast frames are the Open-Meteo
//  heatmap. The coordinator switches layer type as the current frame changes.
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
    var span: CLLocationDegrees = 3.5

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = isDay ? .light : .dark

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        // Lock the camera: the radar data only covers a fixed box and a limited
        // set of zoom levels, so free pan/zoom would scroll off into emptiness
        // and trigger "unsupported zoom" tile errors. A fixed frame just works.
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
        private var token: String?
        private var frames: [RadarFrame] = []
        private var gridImages: [UIImage?] = []      // aligned to frames; nil for tile frames

        private var heatOverlay: PrecipHeatOverlay?
        private weak var heatRenderer: PrecipHeatRenderer?
        private var pendingHeatImage: UIImage?

        private var tileQueue: [MKTileOverlay] = []   // oldest → newest, capped at 2
        private var shownTemplate: String?

        func update(field: RadarField?, index: Int, on map: MKMapView) {
            guard let field else { return }

            if token != field.token {
                token = field.token
                frames = field.frames
                map.removeOverlays(map.overlays)
                tileQueue.removeAll(); shownTemplate = nil
                gridImages = field.frames.map { frame in
                    if case .grid(let v) = frame.layer {
                        return PrecipHeat.image(values: v, cols: field.cols, rows: field.rows)
                    }
                    return nil
                }
                let heat = PrecipHeatOverlay(center: field.center, halfSpan: field.halfSpan)
                heatOverlay = heat
                map.addOverlay(heat, level: .aboveLabels)
            }

            guard frames.indices.contains(index) else { return }
            switch frames[index].layer {
            case .grid:
                clearTiles(on: map)
                pendingHeatImage = gridImages[index]
                heatRenderer?.image = pendingHeatImage
            case .tiles(let template):
                pendingHeatImage = nil
                heatRenderer?.image = nil
                showTile(template, on: map)
            }
        }

        /// Show the requested radar tile frame, keeping the previous one beneath
        /// it so there's no blank gap while tiles load.
        private func showTile(_ template: String, on map: MKMapView) {
            guard template != shownTemplate else { return }
            shownTemplate = template
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 256, height: 256)
            // RainViewer serves a limited zoom range; clamp so MapKit scales the
            // nearest level instead of requesting unsupported tiles (404s).
            overlay.minimumZ = 1
            overlay.maximumZ = 10
            map.addOverlay(overlay, level: .aboveLabels)
            tileQueue.append(overlay)
            while tileQueue.count > 2 { map.removeOverlay(tileQueue.removeFirst()) }
        }

        private func clearTiles(on map: MKMapView) {
            for o in tileQueue { map.removeOverlay(o) }
            tileQueue.removeAll()
            shownTemplate = nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heat = overlay as? PrecipHeatOverlay {
                let r = PrecipHeatRenderer(overlay: heat)
                r.image = pendingHeatImage
                heatRenderer = r
                return r
            }
            if let tile = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tile)
                r.alpha = 0.85
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
            view.markerTintColor = UIColor(red: 0.20, green: 0.52, blue: 0.96, alpha: 1)
            view.displayPriority = .required
            view.animatesWhenAdded = false
            return view
        }
    }
}
