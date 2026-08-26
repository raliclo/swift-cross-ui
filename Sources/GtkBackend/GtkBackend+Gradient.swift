import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    public func createLinearGradientWidget() -> Widget {
        Box()
    }

    public func updateLinearGradientWidget(
        _ widget: Widget,
        gradient: LinearGradient,
        withSize size: SIMD2<Int>,
        in environment: EnvironmentValues
    ) {
        let widget = widget as! Box

        let startPoint = UnitPoint(
            x: Double(size.x) * gradient.startPoint.x,
            y: Double(size.y) * gradient.startPoint.y
        )

        let endPoint = UnitPoint(
            x: Double(size.x) * gradient.endPoint.x,
            y: Double(size.y) * gradient.endPoint.y
        )

        let angle = Angle(origin: startPoint, destination: endPoint)

        let stops = cssStops(stops: gradient.gradient.stops, environment: environment)
            .joined(separator: ", ")

        let radians = (angle + Angle(degrees: 90)).radians

        widget.css.set(
            property: .init(
                key: "background",
                value: """
                    linear-gradient(\(radians)rad, \(stops))
                    """
            )
        )
    }

    public func createRadialGradientWidget() -> Widget {
        Box()
    }

    public func updateRadialGradientWidget(
        _ widget: Widget,
        gradient: RadialGradient,
        withSize size: SIMD2<Int>,
        in environment: EnvironmentValues
    ) {
        let widget = widget as! Box
        let stops = gradient.startRadius < gradient.endRadius
            ? gradient.gradient.stops
            : invertedStops(stops: gradient.gradient.stops)
        let cssStops = cssStops(stops: stops, environment: environment)
            .joined(separator: ", ")

        let centerXPercent = gradient.center.x * 100
        let centerYPercent = gradient.center.y * 100

        widget.css.set(
            property: .init(
                key: "background",
                value: """
                    radial-gradient(\
                    circle at \(centerXPercent)% \(centerYPercent)%, \
                    \(cssStops)\
                    )
                    """
            )
        )
    }

    public func createAngularGradientWidget() -> Widget {
        Box()
    }

    public func updateAngularGradientWidget(
        _ widget: Widget,
        gradient: AngularGradient,
        withSize size: SIMD2<Int>,
        in environment: EnvironmentValues
    ) {
        let widget = widget as! Box

        // CSS conic-gradient, the same route the linear and radial widgets take.
        // Angular gradients had no implementation at all before this, and a
        // missing conformance is not a degradation: @CastBackend turns it into
        // `fatalError("'GtkBackend' does not implement ...")`, so an
        // AngularGradient aborted the app on Linux and on Windows -gtk4.
        //
        // CSS conic-gradient，與 linear 和 radial widget 走同一條路。在此之前 angular gradient
        // 完全沒有實作，而缺少 conformance 並非降級：@CastBackend 會將其轉為
        // `fatalError("'GtkBackend' does not implement ...")`，因此 AngularGradient 會在 Linux
        // 與 Windows -gtk4 上使 app 中止。

        // CSS measures the angle clockwise from twelve o'clock; SwiftUI measures
        // it from three o'clock, so the start is a quarter turn earlier here.
        // CSS 的角度自十二點鐘方向順時針起算；SwiftUI 自三點鐘方向起算，因此此處的起點要早四分之
        // 一圈。
        let fromDegrees = gradient.startAngle.degrees - 90

        // A `nil` end angle means a full turn (the documented default). With an
        // end angle the stops occupy only that sweep, so they are rescaled into
        // it -- CSS has no "stop early" for a conic gradient, and leaving them
        // spread over the whole circle would draw a different gradient from the
        // one asked for.
        //
        // 未指定結束角度代表整整一圈（文件所載的預設）。若有結束角度，色標只佔該扇形，因此會被
        // 重新縮放至其中——CSS 的 conic gradient 沒有「提前結束」的表達方式，而讓色標散佈於整個圓
        // 會畫出與所要求者不同的漸層。
        let sweep = (gradient.endAngle?.degrees).map { $0 - gradient.startAngle.degrees } ?? 360
        let stops = gradient.gradient.stops.map { stop in
            Gradient.Stop(
                color: stop.color,
                location: stop.location * (sweep / 360)
            )
        }

        let cssStops = cssStops(stops: stops, environment: environment)
            .joined(separator: ", ")

        let centerXPercent = gradient.center.x * 100
        let centerYPercent = gradient.center.y * 100

        widget.css.set(
            property: .init(
                key: "background",
                value: """
                    conic-gradient(\
                    from \(fromDegrees)deg at \(centerXPercent)% \(centerYPercent)%, \
                    \(cssStops)\
                    )
                    """
            )
        )
    }

    private func invertedStops(stops: [Gradient.Stop]) -> [Gradient.Stop] {
        return stops.reversed().map { stop in
            Gradient.Stop(
                color: stop.color,
                location: 1.0 - stop.location
            )
        }
    }

    private func cssStops(stops: [Gradient.Stop], environment: EnvironmentValues) -> [String] {
        return stops.map { stop in
            let resolved = stop.color.resolve(in: environment)
            let red = resolved.red * 255
            let green = resolved.green * 255
            let blue = resolved.blue * 255
            let location = stop.location * 100

            return
                """
                rgba(\(red), \(green), \(blue), \
                \(resolved.opacity)) \(location)%
                """
        }
    }
}
