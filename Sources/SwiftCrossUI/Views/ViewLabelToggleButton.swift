/// A button-style toggle whose label is an arbitrary view.
///
/// This corresponds to the ``ToggleStyle/button`` toggle style when the
/// ``Toggle`` was given a view label (`Toggle(isOn:label:)`). The label is
/// hosted inside the backend's toggle button through
/// ``BackendFeatures/ViewLabelToggleButtons/createToggle(wrapping:)`` and is
/// sized the way ``Button`` sizes its label: the label's own size plus the
/// padding the backend reports. ``Toggle`` only uses this view on a backend that
/// conforms to ``BackendFeatures/ViewLabelToggleButtons``.
///
/// 標籤為任意 view 的按鈕樣式 toggle。
///
/// 當 ``Toggle`` 帶的是 view 標籤(`Toggle(isOn:label:)`)時，它對應 ``ToggleStyle/button`` 樣式。標籤透過
/// ``BackendFeatures/ViewLabelToggleButtons/createToggle(wrapping:)`` 容納在 backend 的 toggle 按鈕裡，並以 ``Button``
/// 決定其標籤大小的方式決定大小：標籤本身的大小加上 backend 回報的 padding。``Toggle`` 只會在遵循
/// ``BackendFeatures/ViewLabelToggleButtons`` 的 backend 上使用這個 view。
struct ViewLabelToggleButton<Label: View>: TypeSafeView, View {
    typealias Children = TupleViewChildren1<Label>

    /// The label drawn inside the toggle. / 畫在 toggle 裡面的標籤。
    var label: Label
    /// Whether the toggle is on. / toggle 是否開啟。
    var isOn: Binding<Bool>

    var body: TupleView1<Label> {
        label
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(
            label,
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let toggleBackend = backend as! any BaseAppBackend & BackendFeatures.ViewLabelToggleButtons
        func create<ToggleBackend: BaseAppBackend & BackendFeatures.ViewLabelToggleButtons>(
            _ backend: ToggleBackend
        ) -> Backend.Widget {
            backend.createToggle(wrapping: children.child0.widget.into()) as! Backend.Widget
        }
        return create(toggleBackend)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let toggleBackend = backend as! any BaseAppBackend & BackendFeatures.ViewLabelToggleButtons
        let isOn = self.isOn
        func layout<ToggleBackend: BaseAppBackend & BackendFeatures.ViewLabelToggleButtons>(
            _ backend: ToggleBackend
        ) -> ViewLayoutResult {
            let padding = backend.toggleButtonPadding(in: environment)
            let labelEnvironment = backend.computeToggleLabelEnvironment(
                from: environment,
                isOn: isOn.wrappedValue
            )

            // Proposed as `Button` proposes to its label: the space left after
            // the padding, with the height left free unless the window's size is
            // fixed.
            // 與 `Button` 對其標籤的提議相同：扣掉 padding 後剩下的空間；除非視窗大小固定，否則高度不設限。
            var childProposal = proposedSize
            if let proposedWidth = proposedSize.width {
                childProposal.width = max(proposedWidth - Double(padding.x), 0)
            }
            if environment.windowSizeIsFixed, let proposedHeight = proposedSize.height {
                childProposal.height = max(proposedHeight - Double(padding.y), 0)
            } else {
                childProposal.height = nil
            }
            if proposedSize.width == 0 && !environment.windowSizeIsFixed {
                childProposal.width = nil
            }

            let childResult = children.child0.computeLayout(
                with: label,
                proposedSize: childProposal,
                environment: labelEnvironment
            )

            backend.updateToggle(
                widget as! ToggleBackend.Widget,
                environment: environment
            ) { newState in
                if isOn.wrappedValue != newState {
                    isOn.wrappedValue = newState
                }
            }

            let size = SIMD2(
                Int(childResult.size.width) + padding.x,
                Int(childResult.size.height) + padding.y
            )
            return ViewLayoutResult.leafView(size: ViewSize(size))
        }
        return layout(toggleBackend)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()
        let toggleBackend = backend as! any BaseAppBackend & BackendFeatures.ViewLabelToggleButtons
        let state = isOn.wrappedValue
        func apply<ToggleBackend: BaseAppBackend & BackendFeatures.ViewLabelToggleButtons>(
            _ backend: ToggleBackend
        ) {
            backend.setState(ofViewLabelToggle: widget as! ToggleBackend.Widget, to: state)
        }
        apply(toggleBackend)
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
