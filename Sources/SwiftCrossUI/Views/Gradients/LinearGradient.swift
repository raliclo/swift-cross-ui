/// A linear gradient.
/// `Sendable` is stated here rather than picked up from the `ShapeStyle`
/// conformance in ShapeStyle.swift. `ShapeStyle` refines `Sendable`, so
/// conforming to it in another file made this a retroactive `Sendable`
/// conformance -- a warning today and an error in a future language mode.
/// `Gradient`, `UnitPoint` and `Double` are all `Sendable`, so this is the
/// checked conformance and not `@unchecked`.
///
/// `Sendable` 寫在此處，而不是從 ShapeStyle.swift 中的 `ShapeStyle` conformance 順帶取得。
/// `ShapeStyle` 精煉自 `Sendable`，因此在另一個檔案中遵循它，會使這裡變成一個追溯性的
/// `Sendable` conformance——今天是警告，在未來的語言模式中會是錯誤。`Gradient`、`UnitPoint`
/// 與 `Double` 皆為 `Sendable`，因此這是經檢查的 conformance，而非 `@unchecked`。
public struct LinearGradient: ElementaryView, Sendable {
    /// The gradient represented as an array of color stops, each having a parametric location value.
    public let gradient: Gradient
    /// The normalized point where the gradient begins, defined in the view's coordinate space.
    ///
    /// Use values like `.top`, `.leading`, or custom `UnitPoint(x:y:)` offsets.
    public let startPoint: UnitPoint
    /// The normalized point where the gradient ends, defined in the views coordinate space.
    ///
    /// The color interpolation moves linearly from the start point to this point.
    public let endPoint: UnitPoint

    private static let idealSize = ViewSize(10, 10)

    /// Creates a linear gradient from a base gradient.
    public init(
        gradient: Gradient,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    @CastBackend<BackendFeatures.LinearGradients>(returnsWidget: true)
    public func asWidget<Backend: BaseAppBackend>(
        backend: Backend
    ) -> Backend.Widget {
        backend.createLinearGradientWidget()
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        ViewLayoutResult.leafView(
            size: proposedSize.replacingUnspecifiedDimensions(by: Self.idealSize)
        )
    }

    @CastBackend<BackendFeatures.LinearGradients>
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
        backend.updateLinearGradientWidget(
            widget,
            gradient: self,
            withSize: layout.size.vector,
            in: environment
        )
    }
}

extension LinearGradient {
    /// Creates a linear gradient from a collection of colors.
    public init(
        stops: [Gradient.Stop],
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.init(
            gradient: Gradient(stops: stops),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// Creates a linear gradient from a collection of color stops.
    public init(
        colors: [Color],
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.init(
            gradient: Gradient(colors: colors),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
