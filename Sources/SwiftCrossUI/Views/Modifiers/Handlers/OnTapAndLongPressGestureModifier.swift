extension View {
    /// Runs `onTap` for a tap or click on this view and `onLongPress` for a
    /// press held about half a second; a long press is not also a tap.
    ///
    /// ```swift
    /// Text(emoji)
    ///     .onTapAndLongPressGesture {
    ///         isOn.toggle()
    ///     } onLongPress: {
    ///         isPickerPresented = true
    ///     }
    /// ```
    ///
    /// SwiftUI writes this as `.onTapGesture { }` plus
    /// `.onLongPressGesture { }` and resolves the two through its gesture
    /// graph. This package attaches one gesture per modifier (see
    /// ``onDragGesture(onChanged:onEnded:)``), and stacking
    /// `onTapGesture(gesture: .primary)` on `onTapGesture(gesture: .longPress)`
    /// does not tell them apart on every backend -- so the pair is one
    /// modifier on ``BackendFeatures/TapAndLongPressGestures``.
    ///
    /// 點按或點擊這個 view 時執行 `onTap`,按住約半秒時執行 `onLongPress`;長按不會同時算成點按。SwiftUI 寫成
    /// `.onTapGesture { }` 加 `.onLongPressGesture { }`,由它的手勢圖解決兩者。本套件每個 modifier 掛一個手勢，
    /// 而把 `onTapGesture(gesture: .primary)` 疊在 `onTapGesture(gesture: .longPress)` 上，並不是每個 backend
    /// 都分得開——所以這一對是 ``BackendFeatures/TapAndLongPressGestures`` 上的一個 modifier。
    public func onTapAndLongPressGesture(
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        OnTapAndLongPressGestureModifier(
            body: TupleView1(self),
            onTap: onTap,
            onLongPress: onLongPress
        )
    }
}

struct OnTapAndLongPressGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onTap: () -> Void
    var onLongPress: () -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    // A backend outside the shipped five without the capability keeps the tap
    // (through plain TapGestures) and loses the long press, said once. The
    // shipped five all conform; see CLAUDE.md.
    // 五個已發布 backend 以外、沒有這項能力的 backend:保留點按(經由一般的 TapGestures)、失去長按，並說明一次。
    // 五個已發布的 backend 全部 conform;見 CLAUDE.md。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child = children.child0.widget.into() as Backend.Widget
        if let capable = backend as? any BackendFeatures.TapAndLongPressGestures {
            func wrap<B: BackendFeatures.TapAndLongPressGestures>(_ backend: B) -> Backend.Widget {
                backend.createTapAndLongPressTarget(wrapping: child as! B.Widget) as! Backend.Widget
            }
            return wrap(capable)
        }
        logger.warnOnce(
            "\(type(of: backend)) can't tell a tap from a long press; onTapAndLongPressGesture keeps only the tap"
        )
        if let tappable = backend as? any BackendFeatures.TapGestures {
            func wrap<B: BackendFeatures.TapGestures>(_ backend: B) -> Backend.Widget {
                backend.createTapGestureTarget(wrapping: child as! B.Widget, gesture: .primary)
                    as! Backend.Widget
            }
            return wrap(tappable)
        }
        return child
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

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        if let capable = backend as? any BackendFeatures.TapAndLongPressGestures {
            func update<B: BackendFeatures.TapAndLongPressGestures>(_ backend: B) {
                let target = widget as! B.Widget
                backend.setSize(of: target, to: size.vector)
                backend.updateTapAndLongPressTarget(
                    target,
                    environment: environment,
                    onTap: onTap,
                    onLongPress: onLongPress
                )
            }
            update(capable)
        } else if let tappable = backend as? any BackendFeatures.TapGestures {
            func update<B: BackendFeatures.TapGestures>(_ backend: B) {
                let target = widget as! B.Widget
                backend.setSize(of: target, to: size.vector)
                backend.updateTapGestureTarget(
                    target,
                    gesture: .primary,
                    environment: environment,
                    action: onTap
                )
            }
            update(tappable)
        }
    }
}
