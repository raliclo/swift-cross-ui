import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// Painting a gradient into a shape on Android, rather than flattening it.
///
/// Without this overload `BackendFeatures.Paths` supplies a default that
/// flattens both styles to a single colour and warns. P43 showed what that
/// looks like: three shapes that are supposed to carry a red-to-blue ramp,
/// drawn in flat red.
///
/// **Flat to the first stop, not to a midpoint.** The default calls
/// `ResolvedFillStyle.midpoint(of:)`, which takes the stop nearest location 0.5
/// via `min(by:)`. For the ordinary two-stop gradient both stops are exactly
/// 0.5 away, `min(by:)` keeps the first, and the "midpoint" is the start
/// colour. That is worth knowing wherever the default is still in use; it is no
/// longer in use here.
///
/// The warning it logs was also invisible: an Android app's `print` does not
/// reach logcat, so on this platform the degradation was silent as well.
///
/// 在 Android 上把漸層畫進形狀裡，而不是把它壓平。
///
/// 若沒有這個 overload，`BackendFeatures.Paths` 會提供一個預設實作：把兩種樣式都壓成單一顏色並發出
/// 警告。P43 呈現了那看起來是什麼樣子：三個本應帶有紅到藍漸變的形狀，被畫成平面的紅色。
///
/// **壓平後得到的是第一個 stop，而不是中點。** 該預設實作呼叫 `ResolvedFillStyle.midpoint(of:)`，
/// 它以 `min(by:)` 取「位置最接近 0.5」的 stop。對於常見的雙 stop 漸層，兩個 stop 距 0.5 都恰好是
/// 0.5，`min(by:)` 保留第一個，於是「中點」就是起始色。在任何仍在使用該預設實作的地方，這件事都值得
/// 知道；而此處已不再使用它。
///
/// 它所記錄的那則警告同樣是看不見的：Android app 的 `print` 不會抵達 logcat，因此在這個平台上，
/// 該降級連警告都是靜默的。
extension AndroidBackend {
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        // The flat call first, so every Paint property is set exactly as it was
        // before this file existed. A gradient is a Shader on top of that
        // colour, and the colour is what remains if the shader cannot be built
        // -- a zero-extent path, a zero radius.
        //
        // 先呼叫平面色的版本，使每一個 Paint 屬性都與本檔存在之前完全相同地被設定。漸層是疊在該顏色
        // 之上的一個 Shader，而當該 shader 無法被建構時（範圍為零的路徑、半徑為零），留下的就是
        // 這個顏色。
        renderPath(
            path,
            container: container,
            strokeColor: strokeStyle.flattened(in: environment),
            fillColor: fillStyle.flattened(in: environment),
            overrideStrokeStyle: overrideStrokeStyle
        )

        let view = container.as(PathView.self)!
        apply(fillStyle, to: view, stroke: false, environment: environment)
        apply(strokeStyle, to: view, stroke: true, environment: environment)
    }

    /// Unit space throughout: `PathView` resolves against the path's own bounds
    /// at draw time. See PathView.kt.
    /// 全程使用單位空間：`PathView` 會在繪製時針對路徑自身的邊界框解析。見 PathView.kt。
    private func apply(
        _ style: ResolvedFillStyle,
        to view: PathView,
        stroke: Bool,
        environment: EnvironmentValues
    ) {
        switch style {
            case .color:
                view.clearGradient(stroke)

            case .linearGradient(let gradient, let start, let end):
                view.setGradient(
                    stroke,
                    false,
                    Float(start.x),
                    Float(start.y),
                    Float(end.x),
                    Float(end.y),
                    0,
                    0
                )
                addStops(of: gradient, to: view, stroke: stroke, environment: environment)

            case .radialGradient(let gradient, let center, let startRadius, let endRadius):
                view.setGradient(
                    stroke,
                    true,
                    Float(center.x),
                    Float(center.y),
                    Float(center.x),
                    Float(center.y),
                    Float(startRadius),
                    Float(endRadius)
                )
                addStops(of: gradient, to: view, stroke: stroke, environment: environment)
        }
    }

    /// One call per stop rather than two arrays.
    ///
    /// swift-java has no marshalling for `IntArray` and `FloatArray` here, and
    /// a gradient has a handful of stops; the same shape as `TableContainer`'s
    /// `addCell`.
    ///
    /// 每個 stop 一次呼叫，而不是傳兩個陣列。
    ///
    /// swift-java 在此處沒有 `IntArray` 與 `FloatArray` 的封送處理，而一個漸層只有寥寥數個 stop；
    /// 與 `TableContainer` 的 `addCell` 是同一種形狀。
    private func addStops(
        of gradient: Gradient,
        to view: PathView,
        stroke: Bool,
        environment: EnvironmentValues
    ) {
        for stop in gradient.stops {
            view.addGradientStop(
                stroke,
                stop.color.resolve(in: environment).asColorInt(),
                Float(stop.location)
            )
        }
    }
}
