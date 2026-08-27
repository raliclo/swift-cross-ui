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

        // `adjustedStops`, the helper SwiftCrossUI ships for backends that
        // cannot express two radii natively, rather than the local
        // `invertedStops`. It covers both radii; `invertedStops` covered only
        // the direction, so `startRadius` was discarded and there was no solid
        // inner disc. AppKit, UIKit and WinUI already call it.
        //
        // 使用 SwiftCrossUI 為「無法原生表達兩個半徑的 backend」所準備的 `adjustedStops`，而非本檔
        // 原有的 `invertedStops`。前者涵蓋兩個半徑；後者只涵蓋方向，因此 `startRadius` 被丟棄，
        // 也就不存在實心的內圓。AppKit、UIKit 與 WinUI 早已在呼叫它。
        let cssStops = cssStops(stops: gradient.adjustedStops, environment: environment)
            .joined(separator: ", ")

        let centerXPercent = gradient.center.x * 100
        let centerYPercent = gradient.center.y * 100

        // The extent, written out. A CSS `radial-gradient` with no `<extent>`
        // defaults to `farthest-corner`, so the gradient filled the widget
        // whatever `endRadius` said.
        //
        // The larger of the two radii, not `endRadius`, because that is the
        // edge `adjustedStops` normalises to: with `startRadius > endRadius` it
        // reverses the stops and spreads them over 0...`startRadius`. WinUI
        // computes its `radiusX`/`radiusY` from the same `max` for the same
        // reason.
        //
        // 明確寫出 extent。CSS 的 `radial-gradient` 若未指定 `<extent>` 會預設為 `farthest-corner`，
        // 因此無論 `endRadius` 為何，漸層都會填滿整個 widget。
        //
        // 取兩個半徑中較大者而非 `endRadius`，因為那才是 `adjustedStops` 所歸一化到的邊界：當
        // `startRadius > endRadius` 時它會反轉色標，並將其鋪展於 0...`startRadius` 之上。WinUI 的
        // `radiusX`／`radiusY` 基於相同理由取相同的 `max`。
        let radius = max(gradient.startRadius, gradient.endRadius)

        widget.css.set(
            property: .init(
                key: "background",
                value: """
                    radial-gradient(\
                    circle \(radius)px at \(centerXPercent)% \(centerYPercent)%, \
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
        // `adjustedStops` does that rescaling, and does it in both directions.
        // The local version this replaces multiplied by `sweep / 360` without
        // taking `abs`, so an end angle *before* the start angle gave every stop
        // a negative location and emitted CSS like `rgba(...) -37.5%`. CSS
        // clamps that, so a reversed sweep drew a flat block of the last colour
        // instead of a reversed gradient -- wrong output, no diagnostic.
        //
        // 未指定結束角度代表整整一圈（文件所載的預設）。若有結束角度，色標只佔該扇形，因此會被
        // 重新縮放至其中——CSS 的 conic gradient 沒有「提前結束」的表達方式，而讓色標散佈於整個圓
        // 會畫出與所要求者不同的漸層。
        //
        // `adjustedStops` 會完成該重新縮放，且兩個方向皆能處理。被它取代的原有版本直接乘上
        // `sweep / 360` 而未取絕對值，因此當結束角度早於起始角度時，每個色標的位置都會是負數，
        // 輸出如 `rgba(...) -37.5%` 的 CSS。CSS 會將其夾限，於是反向掃掠畫出的是一整片最後一個顏色
        // 的色塊，而非反向漸層——輸出錯誤，且無任何診斷訊息。
        let cssStops = cssStops(stops: gradient.adjustedStops, environment: environment)
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
