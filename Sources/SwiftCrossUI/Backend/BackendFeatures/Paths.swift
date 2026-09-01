extension BackendFeatures {
    /// Backend methods for path rendering.
    ///
    /// These are used by ``Shape`` and related types and modifiers.
    @MainActor
    public protocol Paths<Path>: Core {
        /// The underlying path type. Can be a wrapper or subclass.
        associatedtype Path

        /// Create a widget that can contain a path.
        ///
        /// - Returns: A path widget.
        func createPathWidget() -> Widget

        /// Create a path.
        ///
        /// The path will not be shown until
        /// ``renderPath(_:container:strokeColor:fillColor:overrideStrokeStyle:)``
        /// is called.
        ///
        /// - Returns: A path.
        func createPath() -> Path

        /// Update a path.
        ///
        /// The updates do not need to be visible before
        /// ``renderPath(_:container:strokeColor:fillColor:overrideStrokeStyle:)``
        /// is called.
        ///
        /// - Parameters:
        ///   - path: The path to be updated.
        ///   - source: The source to copy the path from.
        ///   - bounds: The bounds that the path is getting rendered in. This gets
        ///     passed to backends because AppKit uses a different coordinate system
        ///     (with a flipped y axis) and therefore needs to perform coordinate
        ///     conversions.
        ///   - pointsChanged: If `false`, the ``Path/actions`` of the source have not changed.
        ///   - environment: The environment of the path.
        func updatePath(
            _ path: Path,
            _ source: SwiftCrossUI.Path,
            bounds: SwiftCrossUI.Path.Rect,
            pointsChanged: Bool,
            environment: EnvironmentValues
        )

        /// Draw a path to the screen.
        ///
        /// - Parameters:
        ///   - path: The path to be rendered.
        ///   - container: The container widget that the path will render in.
        ///     Created with ``createPathWidget()``.
        ///   - strokeColor: The color to draw the path's stroke.
        ///   - fillColor: The color to shade the path's fill.
        ///   - overrideStrokeStyle: A value to override the path's stroke style.
        func renderPath(
            _ path: Path,
            container: Widget,
            strokeColor: Color.Resolved,
            fillColor: Color.Resolved,
            overrideStrokeStyle: StrokeStyle?
        )

        /// Draw a path filled and stroked with something that need not be a flat
        /// colour.
        ///
        /// Additive on purpose. Changing the signature above would break five
        /// backends at once, and two of them -- AppKit and UIKit -- cannot be
        /// compiled without a Mac, so the change would be written blind for 40%
        /// of the implementations and land as a build break for whoever pulled
        /// next. A backend opts in by overriding this; until it does, the
        /// default below keeps it compiling and drawing.
        ///
        /// 刻意採加法式。改動上方的簽章會同時破壞五個 backend，而其中兩個——AppKit 與 UIKit
        /// ——沒有 Mac 就無法編譯，因此那樣的改動等於為其中 40% 的實作盲寫，並讓下一個 pull
        /// 的人拿到建置失敗。backend 以覆寫本方法的方式選擇加入；在它這麼做之前，下方的預設
        /// 實作會讓它繼續編譯、繼續繪製。
        func renderPath(
            _ path: Path,
            container: Widget,
            strokeStyle: ResolvedFillStyle,
            fillStyle: ResolvedFillStyle,
            overrideStrokeStyle: StrokeStyle?,
            environment: EnvironmentValues
        )
    }
}

extension BackendFeatures.Paths {
    /// Flattens both styles to one colour each and draws through the flat call.
    ///
    /// **This is a degradation, and it says so.** Project policy is that a
    /// silent no-op is not an acceptable implementation of an advertised
    /// feature, and this is worse than a no-op: it draws *something* plausible,
    /// which reads as a rendering bug rather than as a feature this backend has
    /// not implemented. So it logs, once per backend -- the same reason
    /// `GtkBackend.scrollBarWidth` reports its measured branch, which would
    /// otherwise be a number no one can see.
    ///
    /// 將兩個樣式各壓成一個顏色，並經由平面色的呼叫繪製。
    ///
    /// **這是降級，而且它會說出來。** 專案政策是「靜默的 no-op 不能算是已宣告功能的實作」，
    /// 而此處比 no-op 更糟：它會畫出一個**看似合理的東西**，讀起來像算繪 bug，而不是「這個
    /// backend 尚未實作此功能」。因此它會記錄，每個 backend 一次——理由與
    /// `GtkBackend.scrollBarWidth` 回報其實測分支相同，否則那會是一個沒人看得見的數字。
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        if case .color = strokeStyle, case .color = fillStyle {
            // Nothing was lost, so nothing to announce.
            // 沒有損失任何東西，因此無需宣告。
        } else {
            ResolvedFillStyleDegradation.reportOnce(backend: "\(Self.self)")
        }

        renderPath(
            path,
            container: container,
            strokeColor: strokeStyle.flattened(in: environment),
            fillColor: fillStyle.flattened(in: environment),
            overrideStrokeStyle: overrideStrokeStyle
        )
    }
}

/// One report per backend, so a shape redrawn every frame does not fill the log.
/// 每個 backend 只回報一次，避免每幀重繪的形狀塞爆日誌。
enum ResolvedFillStyleDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            \(backend) cannot paint a gradient into a path, so the shape is \
            filled with the gradient's midpoint colour instead. The shape is \
            drawn, and drawn wrong -- this is not a missing shape.
            """
        )
    }
}
