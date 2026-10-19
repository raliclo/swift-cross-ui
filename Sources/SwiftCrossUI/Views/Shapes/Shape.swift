/// A 2D shape that can be drawn as a view.
///
/// If no stroke color or fill color is specified, the default is no stroke and
/// a fill of the current foreground color.
public protocol Shape: View, Sendable, _RemoveGlobalActorIsolation where Content == EmptyView {
    /// Draw the path for this shape.
    ///
    /// The bounds passed to a shape that is immediately drawn as a view will
    /// always have an origin of (0, 0). However, you may pass a different
    /// bounding box to subpaths. For example, this code draws a rectangle in
    /// the left half of the bounds and an ellipse in the right half:
    /// ```swift
    /// func path(in bounds: Path.Rect) -> Path {
    ///     Path()
    ///         .addSubpath(
    ///             Rectangle().path(
    ///                 in: Path.Rect(
    ///                     x: bounds.x,
    ///                     y: bounds.y,
    ///                     width: bounds.width / 2.0,
    ///                     height: bounds.height
    ///                 )
    ///             )
    ///         )
    ///         .addSubpath(
    ///             Ellipse().path(
    ///                 in: Path.Rect(
    ///                     x: bounds.center.x,
    ///                     y: bounds.y,
    ///                     width: bounds.width / 2.0,
    ///                     height: bounds.height
    ///                 )
    ///             )
    ///         )
    /// }
    /// ```
    ///
    /// - Parameter bounds: The bounds of this shape.
    func path(in bounds: Path.Rect) -> Path

    /// Determine the ideal size of this shape given the proposed bounds.
    ///
    /// The default implementation accepts the proposal, replacing unspecified
    /// dimensions with 10.
    ///
    /// - Parameter proposal: The proposed bounds of this shape.
    /// - Returns: The shape's size for the given proposal.
    func size(fitting proposal: ProposedViewSize) -> ViewSize
}

extension Shape {
    public var body: EmptyView { return EmptyView() }

    public func size(fitting proposal: ProposedViewSize) -> ViewSize {
        proposal.replacingUnspecifiedDimensions(by: ViewSize(10, 10))
    }

    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        ShapeStorage()
    }

    @MainActor
    @CastBackend<BackendFeatures.Paths>(returnsWidget: true)
    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createPathWidget()
        let storage = children as! ShapeStorage
        storage.backendPath = backend.createPath()
        storage.oldPath = nil
        return container
    }

    @MainActor
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = size(fitting: proposedSize)
        return ViewLayoutResult.leafView(size: size)
    }

    @MainActor
    @CastBackend<BackendFeatures.Paths>(backendGenericName: "NewBackend")
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let bounds = Path.Rect(
            x: 0.0,
            y: 0.0,
            width: layout.size.width,
            height: layout.size.height
        )
        let path = path(in: bounds)

        let storage = children as! ShapeStorage
        let pointsChanged = storage.oldPath?.actions != path.actions
        storage.oldPath = path

        let backendPath = storage.backendPath as! NewBackend.Path
        backend.updatePath(
            backendPath,
            path,
            bounds: bounds,
            pointsChanged: pointsChanged,
            environment: environment
        )

        backend.setSize(of: widget, to: layout.size.vector)
        // Filled with the foreground: the foreground colour, or the gradient
        // `.foregroundStyle(_:)` gave. It tweens when it changes under an
        // animation, redrawn on each frame with no re-layout (FillDrawing in
        // StyleAnimation.swift).
        // 以前景填色：前景色，或 `.foregroundStyle(_:)` 給的漸層。它在動畫中改變時會補間，每一幀重畫、不重新排版
        // (StyleAnimation.swift 的 FillDrawing)。
        let stroke = ResolvedFillStyle.color(Color.clear.resolve(in: environment))
        let fill = storage.fill ?? ParameterTween<FillDrawing>()
        storage.fill = fill
        let draw = { (drawn: FillDrawing) in
            backend.renderPath(
                backendPath,
                container: widget,
                strokeStyle: stroke,
                fillStyle: drawn.style(in: environment),
                overrideStrokeStyle: nil,
                environment: environment
            )
            drawn.record(environment, "fill")
        }
        fill.onFrame = { [weak fill] in
            guard let drawn = fill?.drawn else { return }
            draw(drawn)
        }
        draw(
            fill.resolve(
                FillDrawing.foreground(in: environment),
                transaction: EffectTransaction.current(in: environment)
            )
        )
    }
}

final class ShapeStorage: ViewGraphNodeChildren {
    let widgets: [AnyWidget] = []
    let erasedNodes: [ErasedViewGraphNode] = []
    var backendPath: Any!
    var oldPath: Path?
    /// The drawn fill and stroke (colours or gradients); made at the first
    /// commit, on the main actor.
    /// 畫出的填色與筆畫(顏色或漸層);在第一次 commit 時(於 main actor 上)建立。
    var fill: ParameterTween<FillDrawing>?
    var stroke: ParameterTween<FillDrawing>?
}
