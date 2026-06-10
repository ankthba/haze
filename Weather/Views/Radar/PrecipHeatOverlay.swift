//
//  PrecipHeatOverlay.swift
//  Weather
//
//  Renders a precipitation-grid frame as a soft heatmap over the map. The grid
//  is tiny (one value per sample point); the renderer upsamples it with high-
//  quality interpolation so it reads as smooth, gentle blobs rather than blocks.
//

import MapKit
import UIKit

/// A map overlay covering the sampled precipitation box.
final class PrecipHeatOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(center: CLLocationCoordinate2D, halfSpan: CLLocationDegrees) {
        coordinate = center
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude + halfSpan,
                                                   longitude: center.longitude - halfSpan))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: center.latitude - halfSpan,
                                                   longitude: center.longitude + halfSpan))
        boundingMapRect = MKMapRect(x: min(nw.x, se.x), y: min(nw.y, se.y),
                                    width: abs(se.x - nw.x), height: abs(se.y - nw.y))
        super.init()
    }
}

/// Draws the current frame's image; swapping the image animates the loop with no
/// network or tile loading, so playback is instant and flicker-free.
final class PrecipHeatRenderer: MKOverlayRenderer {
    var image: UIImage? {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image else { return }
        let rect = self.rect(for: overlay.boundingMapRect)
        context.interpolationQuality = .high
        // UIImage.draw handles the context flip so north stays up.
        UIGraphicsPushContext(context)
        image.draw(in: rect)
        UIGraphicsPopContext()
    }
}

/// Builds a tiny RGBA image from a grid of mm/h values (row-major, north first).
enum PrecipHeat {
    static func image(values: [Double], cols: Int, rows: Int) -> UIImage? {
        guard values.count == cols * rows, cols > 0, rows > 0 else { return nil }

        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for idx in 0..<(cols * rows) {
            let (r, g, b, a) = color(forMMPerHour: values[idx])
            // Premultiplied alpha.
            px[idx * 4 + 0] = UInt8(Double(r) * a)
            px[idx * 4 + 1] = UInt8(Double(g) * a)
            px[idx * 4 + 2] = UInt8(Double(b) * a)
            px[idx * 4 + 3] = UInt8(a * 255)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &px, width: cols, height: rows, bitsPerComponent: 8,
                                  bytesPerRow: cols * 4, space: colorSpace, bitmapInfo: info),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Soft palette (low alpha) mapping rain rate (mm/h) to colour — a gentle
    /// wash from pale blue through teal, soft yellow, to a muted rose.
    private static func color(forMMPerHour v: Double) -> (UInt8, UInt8, UInt8, Double) {
        switch v {
        case ..<0.1:  return (0, 0, 0, 0)
        case ..<0.4:  return (0x6F, 0xBE, 0xEC, 0.24)
        case ..<1.0:  return (0x57, 0xC6, 0x9E, 0.34)
        case ..<2.5:  return (0xE3, 0xD2, 0x6E, 0.42)
        case ..<6.0:  return (0xE6, 0x9A, 0x5A, 0.50)
        default:      return (0xD9, 0x6A, 0x8E, 0.58)
        }
    }
}
