import Foundation
@_spi(Backends) import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.AngularGradients {
    public func createAngularGradientWidget() -> Widget {
        AngularGradientCanvas()
    }

    public func updateAngularGradientWidget(
        _ widget: Widget,
        gradient: AngularGradient,
        withSize size: SIMD2<Int>,
        in environment: EnvironmentValues
    ) {
        let widget = widget as! AngularGradientCanvas
        widget.render(gradient, size: size, in: environment)
    }
}

/// A canvas that draws a conic gradient into a bitmap of its own.
///
/// Neither XAML nor the composition layer has a conic brush -- `LinearGradientBrush`
/// and `RadialGradientBrush` are the only two, which is why this backend had the
/// other two gradients and not this one. Missing the conformance was not a mild
/// degradation: `@CastBackend` turns it into
/// `fatalError("'WinUIBackend' does not implement 'AngularGradients'")`, so an
/// `AngularGradient` aborted the app on Windows.
///
/// So the gradient is rasterised in software and shown through a `WriteableBitmap`,
/// the same mechanism `updateImageView` already uses for image data. The angle
/// convention follows the GTK backend, which follows SwiftUI: zero degrees is
/// three o'clock and the sweep runs clockwise.
///
/// A `Canvas` holding an `Image` rather than an `Image` itself, because
/// `WinUI.Image` is final and the render cache has to live somewhere.
final class AngularGradientCanvas: WinUI.Canvas {
    /// Everything the rendered pixels depend on.
    ///
    /// Rendering runs on every commit, and a commit happens for any layout pass
    /// at all, so an unconditional rasterise would redraw a full-window gradient
    /// on every unrelated state change. Colors are compared after resolution
    /// because that is what the pixels are made of -- a color that resolves the
    /// same in the new environment does not need a redraw.
    private struct Key: Equatable {
        var size: SIMD2<Int>
        var center: SIMD2<Double>
        var startDegrees: Double
        var sweepDegrees: Double
        var stops: [Stop]
    }

    private struct Stop: Equatable {
        var location: Double
        var color: SwiftCrossUI.Color.Resolved
    }

    private var key: Key?
    private let image = WinUI.Image()

    override init() {
        super.init()

        image.stretch = .fill
        children.append(image)
    }

    @MainActor
    func render(_ gradient: AngularGradient, size: SIMD2<Int>, in environment: EnvironmentValues) {
        guard size.x > 0, size.y > 0 else { return }

        // A nil end angle means a full turn (the documented default). With an end
        // angle the stops occupy only that sweep, so they are rescaled into it.
        //
        // `adjustedStops` does the rescaling. This used to do it inline -- and
        // said so, citing the GTK backend, which had copied the same mistake:
        // multiplying by `sweep / 360` without `abs` sends every location
        // negative when the end angle precedes the start angle. `color(at:)`
        // then finds no stop above any position in 0..<1 and returns the last
        // stop's color for every pixel, so a reversed sweep rasterised as one
        // flat block. Measured 2026-08-27 with P27's "Sweep reversed" sample,
        // where GtkBackend drew the gradient and this drew flat red.
        let sweep = (gradient.endAngle?.degrees).map { $0 - gradient.startAngle.degrees } ?? 360
        let stops = gradient.adjustedStops.map {
            Stop(
                location: $0.location,
                color: $0.color.resolve(in: environment)
            )
        }

        let key = Key(
            size: size,
            center: SIMD2(gradient.center.x, gradient.center.y),
            startDegrees: gradient.startAngle.degrees,
            sweepDegrees: sweep,
            stops: stops
        )
        guard key != self.key, !stops.isEmpty else { return }
        self.key = key

        rasterize(key)
    }

    private func rasterize(_ key: Key) {
        let width = key.size.x
        let height = key.size.y

        image.width = Double(width)
        image.height = Double(height)

        let bitmap: WriteableBitmap
        if let existing = image.source as? WriteableBitmap,
           existing.pixelWidth == Int32(width),
           existing.pixelHeight == Int32(height)
        {
            bitmap = existing
        } else {
            bitmap = WriteableBitmap(Int32(width), Int32(height))
            image.source = bitmap
        }

        guard let buffer = try? bitmap.pixelBuffer.buffer else {
            logger.warning("WriteableBitmap.pixelBuffer.buffer unavailable, skipping gradient")
            return
        }
        let pixels = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: UInt32.self)

        let centerX = key.center.x * Double(width)
        let centerY = key.center.y * Double(height)

        for y in 0..<height {
            let dy = Double(y) + 0.5 - centerY
            for x in 0..<width {
                let dx = Double(x) + 0.5 - centerX

                // atan2 with a downward y axis already increases clockwise on
                // screen, which is the direction SwiftUI sweeps in, so no sign
                // flip is needed here -- only the wrap into [0, 360).
                var degrees = atan2(dy, dx) * 180 / .pi - key.startDegrees
                degrees.formTruncatingRemainder(dividingBy: 360)
                if degrees < 0 { degrees += 360 }

                pixels[y * width + x] = Self.bgra(color(at: degrees / 360, in: key.stops))
            }
        }

        try? bitmap.invalidate()
    }

    /// The gradient's color at a parametric position, with the ends held.
    ///
    /// Before the first stop and after the last, the nearest stop's color
    /// continues unchanged. That is what CSS does past the end of a conic
    /// gradient's stops, and it is what the documented "everything after is
    /// filled with the last used color" asks for.
    private func color(at position: Double, in stops: [Stop]) -> SwiftCrossUI.Color.Resolved {
        if position <= stops[0].location { return stops[0].color }
        guard let index = stops.firstIndex(where: { $0.location > position }) else {
            return stops[stops.count - 1].color
        }

        let previous = stops[index - 1]
        let next = stops[index]
        let span = next.location - previous.location
        guard span > 0 else { return next.color }

        let t = Float((position - previous.location) / span)
        return SwiftCrossUI.Color.Resolved(
            red: previous.color.red + (next.color.red - previous.color.red) * t,
            green: previous.color.green + (next.color.green - previous.color.green) * t,
            blue: previous.color.blue + (next.color.blue - previous.color.blue) * t,
            opacity: previous.color.opacity + (next.color.opacity - previous.color.opacity) * t
        )
    }

    /// A color as one premultiplied BGRA word, the format `WriteableBitmap` uses.
    ///
    /// Premultiplication is not optional here: the bitmap is declared BGRA8
    /// premultiplied, and writing straight alpha instead makes a partly
    /// transparent gradient render brighter than it should rather than failing
    /// in any way that would be noticed.
    private static func bgra(_ color: SwiftCrossUI.Color.Resolved) -> UInt32 {
        let alpha = max(0, min(1, color.opacity))
        let component = { (value: Float) -> UInt32 in
            UInt32(max(0, min(1, value)) * alpha * 255)
        }
        return (UInt32(alpha * 255) << 24)
            | (component(color.red) << 16)
            | (component(color.green) << 8)
            | component(color.blue)
    }
}
