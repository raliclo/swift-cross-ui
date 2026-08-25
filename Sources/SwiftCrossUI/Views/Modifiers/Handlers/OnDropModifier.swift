import Foundation

extension View {
    /// Accepts content dropped onto this view.
    ///
    /// The typed-data form. Each dropped payload arrives as a ``DropItem`` with
    /// the type it was delivered as and its bytes verbatim; see ``DropItem`` for
    /// why the bytes are not normalised. For the file case there is a URL
    /// convenience overload, ``onDrop(of:isTargeted:perform:)-(_,_,([URL])->Bool)``.
    ///
    /// - Parameters:
    ///   - acceptedTypes: The types this view will accept. A drag offering none
    ///     of them is refused rather than silently swallowed.
    ///   - isTargeted: A binding set to `true` while a drag this view accepts is
    ///     over it, and `false` otherwise. This is the hover-feedback stage, and
    ///     it changes before the drop, so a view can highlight itself as a valid
    ///     target before the pointer is released.
    ///   - action: Runs when a drop lands, with the dropped items. Return
    ///     whether the drop was accepted.
    public func onDrop(
        of acceptedTypes: [DropType],
        isTargeted: Binding<Bool>? = nil,
        perform action: @escaping ([DropItem]) -> Bool
    ) -> some View {
        OnDropModifier(
            body: TupleView1(self),
            acceptedTypes: acceptedTypes,
            isTargeted: isTargeted,
            action: action
        )
    }

    /// Accepts files dropped onto this view, as URLs.
    ///
    /// The convenience form over ``onDrop(of:isTargeted:perform:)-(_,_,([DropItem])->Bool)``:
    /// it collects the URLs out of the dropped items (see ``DropItem/urls``) and
    /// hands them over as a plain `[URL]`. It refuses a drop that carried no URL,
    /// so the typed-data form's contract -- an unaccepted type is refused, not
    /// swallowed -- still holds.
    ///
    /// - Parameters:
    ///   - acceptedTypes: The types this view will accept, e.g. ``DropType/fileURL``.
    ///   - isTargeted: A binding set to `true` while an accepted drag is over the
    ///     view. See the typed-data form.
    ///   - action: Runs with the dropped URLs. Return whether the drop was
    ///     accepted.
    public func onDrop(
        of acceptedTypes: [DropType],
        isTargeted: Binding<Bool>? = nil,
        perform action: @escaping ([URL]) -> Bool
    ) -> some View {
        onDrop(of: acceptedTypes, isTargeted: isTargeted) { items in
            let urls = items.flatMap(\.urls)
            guard !urls.isEmpty else { return false }
            return action(urls)
        }
    }
}

struct OnDropModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var acceptedTypes: [DropType]
    var isTargeted: Binding<Bool>?
    var action: ([DropItem]) -> Bool

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    @CastBackend<BackendFeatures.DragAndDrop>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createDropTarget(wrapping: children.child0.widget.into())
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
    }

    @CastBackend<BackendFeatures.DragAndDrop>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size.vector
        backend.setSize(of: widget, to: size)
        let isTargeted = isTargeted
        backend.updateDropTarget(
            widget,
            acceptedTypes: acceptedTypes,
            environment: environment,
            onHover: { hovering in
                isTargeted?.wrappedValue = hovering
            },
            onDrop: action
        )
    }
}
