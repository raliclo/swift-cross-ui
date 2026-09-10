extension View {
    /// Adds padding to a view.
    ///
    /// Separate from ``View/padding(_:_:)`` because overload resolution didn't
    /// like the double default parameters.
    ///
    /// - Parameter amount: The amount of padding to use. If `nil`, a
    ///   backend-specific default value is used.
    public func padding(_ amount: Double? = nil) -> some View {
        return padding(.all, amount)
    }

    /// Adds padding to a view.
    ///
    /// - Parameters:
    ///   - edges: The edges to apply the padding to. Defaults to
    ///     ``Edge/Set/all``.
    ///   - amount: The amount of padding to use. If `nil`, a backend-specific
    ///     default value is used.
    public func padding(_ edges: Edge.Set = .all, _ amount: Double? = nil) -> some View {
        let insets = EdgeInsets.Internal(edges: edges, amount: amount)
        return PaddingModifierView(body: TupleView1(self), insets: insets)
    }

    /// Adds padding to a view with a different amount for each edge.
    ///
    /// - Parameter insets: The edge insets to use.
    public func padding(_ insets: EdgeInsets) -> some View {
        return PaddingModifierView(body: TupleView1(self), insets: EdgeInsets.Internal(insets))
    }
}

/// Insets for the sides of a rectangle. Generally used to represent view padding.
///
/// The insets are `Double` rather than `Int` so that a padding can be a
/// fraction of a point -- `.padding(0.5)`, or an inset derived by dividing
/// something. SwiftUI's `EdgeInsets` is `CGFloat` for the same reason. Rounding
/// happens once, at the point a position is handed to a backend, via
/// ``Position/vector``; it does not happen here, so a chain of insets does not
/// accumulate a rounding error per step.
///
/// 這些 inset 採用 `Double` 而非 `Int`,如此一來 padding 便可以是「一個 point 的分數」——
/// `.padding(0.5)`,或是某個東西相除得出的 inset。SwiftUI 的 `EdgeInsets` 是 `CGFloat`,
/// 理由相同。**取整只發生一次**,即位置交給 backend 的那一刻,經由 ``Position/vector``;
/// 它不發生在此處,因此一連串的 inset 不會每一步累積一次捨入誤差。
public struct EdgeInsets: Equatable {
    /// The top inset.
    public var top: Double
    /// The bottom inset.
    public var bottom: Double
    /// The leading inset.
    public var leading: Double
    /// The trailing inset.
    public var trailing: Double

    /// The total inset along each axis.
    var axisTotals: SIMD2<Double> {
        SIMD2(
            leading + trailing,
            top + bottom
        )
    }

    /// Constructs edge insets from individual insets.
    ///
    /// - Parameters:
    ///   - top: The top inset.
    ///   - bottom: The bottom inset.
    ///   - leading: The leading inset.
    ///   - trailing: The trailing inset.
    public init(top: Double = 0, bottom: Double = 0, leading: Double = 0, trailing: Double = 0) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    init(_ insets: Internal, defaultAmount: Double) {
        top = insets.top ?? defaultAmount
        bottom = insets.bottom ?? defaultAmount
        leading = insets.leading ?? defaultAmount
        trailing = insets.trailing ?? defaultAmount
    }

    struct Internal {
        var top: Double?
        var bottom: Double?
        var leading: Double?
        var trailing: Double?
    }
}

extension EdgeInsets.Internal {
    init(edges: Edge.Set, amount: Double?) {
        self.top = edges.contains(.top) ? amount : 0
        self.bottom = edges.contains(.bottom) ? amount : 0
        self.leading = edges.contains(.leading) ? amount : 0
        self.trailing = edges.contains(.trailing) ? amount : 0
    }

    init(_ insets: EdgeInsets) {
        top = insets.top
        bottom = insets.bottom
        leading = insets.leading
        trailing = insets.trailing
    }
}

/// The implementation for the ``View/padding(_:_:)`` modifier.
struct PaddingModifierView<Child: View>: TypeSafeView {
    var body: TupleView1<Child>

    /// The insets for each edge.
    var insets: EdgeInsets.Internal

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> TupleViewChildren1<Child> {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: TupleViewChildren1<Child>,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        backend.insert(children.child0.widget.into(), into: container, at: 0)
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ container: Backend.Widget,
        children: TupleViewChildren1<Child>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // This first block of calculations is somewhat repeated in `commit`,
        // make sure to update things in both places.
        let insets = EdgeInsets(insets, defaultAmount: Double(backend.defaultPaddingAmount))
        let horizontalPadding = insets.leading + insets.trailing
        let verticalPadding = insets.top + insets.bottom

        var childProposal = proposedSize
        if let proposedWidth = proposedSize.width {
            childProposal.width = max(proposedWidth - horizontalPadding, 0)
        }
        if let proposedHeight = proposedSize.height {
            childProposal.height = max(proposedHeight - verticalPadding, 0)
        }

        let childResult = children.child0.computeLayout(
            with: body.view0,
            proposedSize: childProposal,
            environment: environment
        )

        var size = childResult.size
        size.width += horizontalPadding
        size.height += verticalPadding

        return ViewLayoutResult(
            size: size,
            childResults: [childResult]
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ container: Backend.Widget,
        children: TupleViewChildren1<Child>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()

        let size = layout.size
        backend.setSize(of: container, to: size.vector)

        let insets = EdgeInsets(insets, defaultAmount: Double(backend.defaultPaddingAmount))
        // Rounded HERE and only here, through the same `Position.vector` every
        // other backend hand-off uses, so a fractional inset does not invent a
        // second rounding rule.
        // **只在此處取整**,而且走的是其他每一次交給 backend 時都用的同一個
        // `Position.vector`,如此一來「帶分數的 inset」不會另外發明第二套捨入規則。
        let childPosition = Position(insets.leading, insets.top)
        backend.setPosition(ofChildAt: 0, in: container, to: childPosition.vector)
    }
}
