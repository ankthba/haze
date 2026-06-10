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

/// Builds a smooth heatmap image from a coarse grid of mm/h values (row-major,
/// north first). The grid is bilinearly upsampled to a high-resolution image so
/// it reads as soft blobs — not blocks — regardless of how MapKit scales it.
enum PrecipHeat {
    /// Output resolution of the rendered heatmap (px per side).
    private static let out = 256

    static func image(values: [Double], cols: Int, rows: Int) -> UIImage? {
        guard values.count == cols * rows, cols > 1, rows > 1 else { return nil }

        let outW = out, outH = out
        var px = [UInt8](repeating: 0, count: outW * outH * 4)

        for oy in 0..<outH {
            let gy = Double(oy) / Double(outH - 1) * Double(rows - 1)
            let y0 = min(Int(gy), rows - 2)
            let fy = gy - Double(y0)
            for ox in 0..<outW {
                let gx = Double(ox) / Double(outW - 1) * Double(cols - 1)
                let x0 = min(Int(gx), cols - 2)
                let fx = gx - Double(x0)

                // Bilinear interpolation of the rain rate.
                let v00 = values[y0 * cols + x0]
                let v01 = values[y0 * cols + x0 + 1]
                let v10 = values[(y0 + 1) * cols + x0]
                let v11 = values[(y0 + 1) * cols + x0 + 1]
                let top = v00 + (v01 - v00) * fx
                let bot = v10 + (v11 - v10) * fx
                let v = top + (bot - top) * fy

                let bucket = v <= 0 ? 0 : min(lut.count - 1, Int(v / lutMaxMM * Double(lut.count - 1)))
                let c = lut[bucket]
                let o = (oy * outW + ox) * 4
                px[o + 0] = c.0
                px[o + 1] = c.1
                px[o + 2] = c.2
                px[o + 3] = c.3
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &px, width: outW, height: outH, bitsPerComponent: 8,
                                  bytesPerRow: outW * 4, space: colorSpace, bitmapInfo: info),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Colour ramp

    private static let lutMaxMM = 24.0

    /// Premultiplied-RGBA lookup table sampled from the continuous ramp, so the
    /// per-pixel hot path is a single array read.
    private static let lut: [(UInt8, UInt8, UInt8, UInt8)] = (0..<256).map { i in
        let v = Double(i) / 255.0 * lutMaxMM
        let (r, g, b, a) = color(forMMPerHour: v)
        return (UInt8(Double(r) * a), UInt8(Double(g) * a), UInt8(Double(b) * a), UInt8(a * 255))
    }

    /// Soft, continuous palette mapping rain rate (mm/h) to colour + alpha — a
    /// gentle wash from pale blue through teal and soft yellow to a muted rose.
    private static func color(forMMPerHour v: Double) -> (Double, Double, Double, Double) {
        // (mm/h, r, g, b, alpha)
        let stops: [(Double, Double, Double, Double, Double)] = [
            (0.00, 0x6F, 0xBE, 0xEC, 0.00),
            (0.12, 0x6F, 0xBE, 0xEC, 0.20),
            (0.60, 0x57, 0xC6, 0x9E, 0.32),
            (1.50, 0xE3, 0xD2, 0x6E, 0.42),
            (4.00, 0xE6, 0x9A, 0x5A, 0.50),
            (10.0, 0xD9, 0x6A, 0x8E, 0.58),
        ]
        if v <= stops[0].0 { return (stops[0].1, stops[0].2, stops[0].3, stops[0].4) }
        for k in 1..<stops.count {
            let hi = stops[k]
            if v <= hi.0 {
                let lo = stops[k - 1]
                let t = hi.0 > lo.0 ? (v - lo.0) / (hi.0 - lo.0) : 0
                return (lo.1 + (hi.1 - lo.1) * t,
                        lo.2 + (hi.2 - lo.2) * t,
                        lo.3 + (hi.3 - lo.3) * t,
                        lo.4 + (hi.4 - lo.4) * t)
            }
        }
        let last = stops[stops.count - 1]
        return (last.1, last.2, last.3, last.4)
    }
}
