/// A radial gradient.
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
public struct RadialGradient: ElementaryView, Sendable {
    /// The gradient represented as an array of color stops, each having a parametric location value.
    public let gradient: Gradient
    /// The radius at which the first gradient stop will be placed.
    ///
    /// All space inside this radius gets filled with the color of the first gradient stop.
    public let startRadius: Double
    /// The radius at which the last gradient stop will be placed.
    ///
    /// All space outside this radius gets filled with the color of the last gradient stop.
    public let endRadius: Double
    /// The normalized center point of the gradient in its coordinate space.
    public let center: UnitPoint

    private static let idealSize = ViewSize(10, 10)

    /// Creates a radial gradient from a base gradient.
    public init(
        gradient: Gradient,
        center: UnitPoint,
        startRadius: Double,
        endRadius: Double
    ) {
        self.gradient = gradient
        self.startRadius = startRadius
        self.center = center
        self.endRadius = endRadius
    }

    @CastBackend<BackendFeatures.RadialGradients>(returnsWidget: true)
    public func asWidget<Backend: BaseAppBackend>(
        backend: Backend
    ) -> Backend.Widget {
        backend.createRadialGradientWidget()
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

    @CastBackend<BackendFeatures.RadialGradients>
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
        backend.updateRadialGradientWidget(
            widget,
            gradient: self,
            withSize: layout.size.vector,
            in: environment
        )
    }
}

extension RadialGradient {
    /// Creates a radial gradient from a collection of colors.
    public init(
        stops: [Gradient.Stop],
        center: UnitPoint,
        startRadius: Double,
        endRadius: Double
    ) {
        self.init(
            gradient: Gradient(stops: stops),
            center: center,
            startRadius: startRadius,
            endRadius: endRadius
        )
    }

    /// Creates a radial gradient from a collection of color stops.
    public init(
        colors: [Color],
        center: UnitPoint,
        startRadius: Double,
        endRadius: Double
    ) {
        self.init(
            gradient: Gradient(colors: colors),
            center: center,
            startRadius: startRadius,
            endRadius: endRadius
        )
    }

    /// Stops adjusted to accomodate startRadius on backends without native support.
    @_spi(Backends) public var adjustedStops: [Gradient.Stop] {
        guard startRadius != 0 else { return gradient.stops }

        let range = endRadius - startRadius

        if range < 0 {
            let dividableRange = abs(range) / startRadius
            let innerCircle = (startRadius - abs(range)) / startRadius

            let invertedStops = gradient.stops.reversed().map { stop in
                Gradient.Stop(
                    color: stop.color,
                    location: innerCircle + (1.0 - stop.location) * dividableRange
                )
            }

            return invertedStops
        }

        let dividableRange = range / endRadius
        let innerCircle = (endRadius - range) / endRadius

        return gradient.stops.map { stop in
            Gradient.Stop(
                color: stop.color,
                location: innerCircle + stop.location * dividableRange
            )
        }
    }
}
