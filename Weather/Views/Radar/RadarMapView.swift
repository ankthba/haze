//
//  RadarMapView.swift
//  Weather
//
//  A dark/light MapKit map with an animated radar tile overlay. Every frame is
//  an XYZ tile layer (IEM observed/forecast, or RainViewer); the coordinator
//  swaps the overlay per frame, keeping the previous one beneath so there's no
//  blank gap while tiles load. Pinch and pan are fenced into the zoom levels and
//  the ground the tile services actually cover.
//
//  Tiles come from the app's own cache (see RadarTileLoader): the coordinator
//  notes which tile coordinates MapKit asks for while drawing the visible
//  frame, then hands that list to the prefetcher so every other frame is
//  downloaded before playback reaches it. Moving the camera invalidates that
//  list, and it's learned again from the new framing.
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
    /// Supplied by the animated radar view; nil for the static preview card,
    /// which shows one frame and has nothing to prefetch.
    var prefetcher: RadarPrefetcher? = nil
    /// Pinch to zoom and drag to pan, bounded to the radar's coverage.
    var isInteractive: Bool = false
    /// Bumped by the owner to fly back to the opening framing.
    var resetToken: Int = 0
    /// Reports whether the camera has been moved off that framing.
    var onCameraMoved: ((Bool) -> Void)? = nil

    /// Softened so the radar reads as a gentle wash over the map, not a slab.
    private let tileAlpha: CGFloat = 0.6

    func makeCoordinator() -> Coordinator {
        Coordinator(tileAlpha: tileAlpha, isInteractive: isInteractive)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = isDay ? .light : .dark

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        // Rotation and pitch stay off — radar tiles are flat, north-up imagery.
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isZoomEnabled = isInteractive
        map.isScrollEnabled = isInteractive
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false

        // Zoom and pan limits can't be set yet: `setRegion` fits the region to
        // the view's aspect, so what's actually on screen isn't known until
        // layout. They're derived from the real camera in the coordinator.

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
        context.coordinator.prefetcher = prefetcher
        context.coordinator.onCameraMoved = onCameraMoved
        context.coordinator.update(field: field, index: currentIndex, on: map)
        context.coordinator.applyReset(token: resetToken, on: map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var prefetcher: RadarPrefetcher?
        var onCameraMoved: ((Bool) -> Void)?

        private let tileAlpha: CGFloat
        private let isInteractive: Bool
        private var token: String?
        private var frames: [RadarFrame] = []
        /// One persistent overlay per frame, all added the moment the field
        /// arrives and never removed — removal cancels in-flight tile loads and
        /// used to leave the map blank after a manual scrub. Visibility is
        /// flipped purely via renderer alpha.
        private var overlays: [Int: RadarTileOverlay] = [:]
        private var currentIndex = -1
        private var previousIndex = -1
        /// Tile coordinates MapKit has asked for at the current framing — which
        /// is the tile set *every* frame needs, since they all cover the same
        /// screen. Cleared whenever the camera moves.
        private var requestedPaths: Set<RadarTilePath> = []
        private var settle: Task<Void, Never>?
        /// The opening framing, captured once the map has been laid out — what
        /// "reset" returns to and what "moved" is measured against.
        private var homeRegion: MKCoordinateRegion?
        private var resetToken = 0
        private var isMoved = false

        init(tileAlpha: CGFloat, isInteractive: Bool) {
            self.tileAlpha = tileAlpha
            self.isInteractive = isInteractive
        }

        func update(field: RadarField?, index: Int, on map: MKMapView) {
            if homeRegion == nil, map.bounds.width > 0 {
                homeRegion = map.region
                applyCameraLimits(on: map)
            }
            guard let field else { return }
            if token != field.token {
                token = field.token
                frames = field.frames
                map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
                overlays.removeAll()
                currentIndex = -1
                previousIndex = -1
                requestedPaths.removeAll()
                settle?.cancel()

                // An overlay per frame, added up front. They don't self-load:
                // MapKit never draws an alpha-0 renderer, so it never asks for
                // those tiles — the prefetcher is what fills the cache.
                var onRequest: (@MainActor (RadarTilePath) -> Void)?
                if prefetcher != nil {
                    onRequest = { [weak self] path in self?.record(path) }
                }
                for (i, frame) in frames.enumerated() {
                    let overlay = RadarTileOverlay(urlTemplate: frame.urlTemplate,
                                                   onRequest: onRequest)
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

        // MARK: - Camera

        /// Measured from the framing the map actually settled on, not from the
        /// requested span — `setRegion` widens the region to fit the screen's
        /// aspect, so a formula-derived limit lands in the wrong place and
        /// MapKit clamps the opening camera to it.
        private func applyCameraLimits(on map: MKMapView) {
            guard isInteractive, let home = homeRegion else { return }
            let distance = map.camera.centerCoordinateDistance
            guard distance > 0 else { return }

            // The tile services publish a limited range of zoom levels, and the
            // composite only covers so much ground — so movement is fenced to
            // roughly six times in, half again out, and one screen of panning.
            map.setCameraZoomRange(
                MKMapView.CameraZoomRange(minCenterCoordinateDistance: distance / 6,
                                          maxCenterCoordinateDistance: distance * 1.5),
                animated: false)
            map.setCameraBoundary(
                MKMapView.CameraBoundary(coordinateRegion: MKCoordinateRegion(
                    center: home.center,
                    span: MKCoordinateSpan(latitudeDelta: home.span.latitudeDelta * 2,
                                           longitudeDelta: home.span.longitudeDelta * 2))),
                animated: false)
        }

        func applyReset(token: Int, on map: MKMapView) {
            guard token != resetToken else { return }
            resetToken = token
            guard let homeRegion else { return }
            // Out of the SwiftUI update pass: moving the camera calls back into
            // the delegate, which touches state the view is reading right now.
            Task { @MainActor in map.setRegion(homeRegion, animated: true) }
        }

        /// A pinch or drag changes which tiles are on screen, so the set learned
        /// for the old framing is stale — drop it and let the redraw teach us
        /// the new one. Playback deliberately keeps running on what it has:
        /// blocking it here froze the timeline whenever MapKit had the new
        /// tiles cached already and so never asked for any.
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard prefetcher != nil, homeRegion != nil else { return }
            settle?.cancel()
            requestedPaths.removeAll()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // The map settling into its laid-out region is the first reliable
            // read of the opening framing — `updateUIView` can run before the
            // view has any bounds, and with playback paused it may not run again.
            if homeRegion == nil, mapView.bounds.width > 0 {
                homeRegion = mapView.region
                applyCameraLimits(on: mapView)
                return
            }
            let moved = isOffHome(mapView)
            guard moved != isMoved else { return }
            isMoved = moved
            let report = onCameraMoved
            Task { @MainActor in report?(moved) }
        }

        private func isOffHome(_ map: MKMapView) -> Bool {
            guard let home = homeRegion else { return false }
            let region = map.region
            let zoom = region.span.latitudeDelta / home.span.latitudeDelta
            if zoom < 0.95 || zoom > 1.05 { return true }
            return abs(region.center.latitude - home.center.latitude) > home.span.latitudeDelta * 0.05
                || abs(region.center.longitude - home.center.longitude) > home.span.longitudeDelta * 0.05
        }

        // MARK: - Prefetch

        /// MapKit only requests tiles for the frame it's drawing, so we learn
        /// the tile set from that frame and reuse it for all the others.
        private func record(_ path: RadarTilePath) {
            guard prefetcher != nil, requestedPaths.insert(path).inserted else { return }
            // The requests arrive in one burst a few milliseconds wide; just
            // long enough to catch all of it before deciding the tile set.
            settle?.cancel()
            settle = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.startPrefetch()
            }
        }

        private func startPrefetch() {
            guard let prefetcher, let token, !requestedPaths.isEmpty else { return }
            let paths = requestedPaths.sorted { ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x) }
            let urls = (0..<frames.count).map { index -> [URL] in
                guard let overlay = overlays[index] else { return [] }
                return paths.map { overlay.url(forTilePath: $0.overlayPath) }
            }
            // The signature covers the tile coordinates themselves, not just how
            // many: zooming can land on the same tile count over different
            // ground, and that has to count as new work.
            var hasher = Hasher()
            paths.forEach { hasher.combine($0) }
            prefetcher.start(signature: "\(token)|\(hasher.finalize())",
                             urls: urls,
                             from: max(currentIndex, 0))
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
