/// A control that initiates an action.
public struct Button<Label: View> {
    public typealias Content = TupleView1<Label>
    /// The label to show on the button.
    @_spi(Backends) public var label: () -> Label
    /// The action to be performed when the button is clicked.
    @_spi(Backends) public var action: @MainActor @Sendable () -> Void
    /// What the button is for, when that changes how it should look.
    ///
    /// Kept across upstream's move to arbitrary view labels (#590). `width` went
    /// with that change -- `_buttonWidth` is now a frame on the label -- but
    /// `role` is orthogonal to what the label is, and nothing about a generic
    /// label makes a destructive button less destructive.
    ///
    /// 這個按鈕是做什麼用的——當它會改變外觀時。
    ///
    /// 在 upstream 改為任意 view label(#590)之後保留。`width` 隨那次改動一併移除
    /// ——`_buttonWidth` 現在是套在 label 上的一個 frame——但 `role` 與「label 是什麼」正交,
    /// 而「label 是泛型的」這件事不會讓一個破壞性按鈕變得比較不破壞性。
    @_spi(Backends) public var role: ButtonRole?

    /// Creates a button that displays a text label.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - action: The action to be performed when the button is clicked.
    public init(
        _ label: String,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) where Label == TupleView1<Text> {
        self.label = { TupleView1(Text(label)) }
        self.action = action
    }

    /// Creates a button that displays a custom view as label.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - action: The action to be performed when the button is clicked.
    @MainActor
    public init (
        action: @escaping @MainActor @Sendable () -> Void = {},
        @ViewBuilder label: @escaping @MainActor @Sendable () -> Label
    ) {
        self.label = label
        self.action = action
    }

    /// Creates a button with a role, which platforms may render differently.
    ///
    /// SwiftUI spells this `Button(_:role:action:)` and this matches. Separate
    /// from the string initialiser above rather than a defaulted parameter,
    /// because a default would change that one's signature for no benefit.
    ///
    /// Constrained to a `Text` label like its sibling: a role is about what
    /// pressing the button does, and every platform that renders one differently
    /// does so by restyling text. A role on an arbitrary view label has no
    /// agreed meaning, so it is not offered rather than being offered and
    /// ignored.
    ///
    /// 建立一個帶有 role 的按鈕,各平台可能會以不同方式繪製它。
    ///
    /// SwiftUI 中寫作 `Button(_:role:action:)`,此處與之一致。之所以獨立於上方的字串建構式而非加上
    /// 預設參數,是因為預設值會改動那一個的簽名,卻換不到任何好處。
    ///
    /// 與其兄弟一樣限定為 `Text` label:role 講的是「按下去會做什麼」,而每一個會據此改變繪製方式的
    /// 平台,都是透過重新設定文字樣式來做到的。role 套在任意 view label 上並沒有公認的意義,因此
    /// 此處不提供它——而不是提供了卻忽略它。
    public init(
        _ label: String,
        role: ButtonRole?,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) where Label == TupleView1<Text> {
        self.label = { TupleView1(Text(label)) }
        self.role = role
        self.action = action
    }

    private struct ConstrainedButtonLabel<ConstrainedLabel: View>: View {
        @Environment(\.buttonPadding.x) var horizontalPadding

        var content: ConstrainedLabel
        var width: Int?

        var body: some View {
            content.ifLet(width) { view, width in
                view.frame(width: Double(width - horizontalPadding))
            }
        }
    }

    @MainActor
    @available(
        *,
        deprecated,
        message: "Use @ViewBuilder init of Button instead and apply a frame modifier to the label."
    )
    public func _buttonWidth(_ width: Int?) -> Button<some View> {
        return Button<TupleView1<ConstrainedButtonLabel<TupleView1<Label>>>>(
            action: action,
            label: { ConstrainedButtonLabel(content: body, width: width) }
        )
    }
}

@MainActor
extension Button: TypeSafeView {
    public var body: TupleView1<Label> {
        label()
    }

    typealias Children = TupleViewChildren1<Label>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(label(), backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createButton(wrapping: children.child0.widget.into())
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let buttonPadding = backend.buttonPadding(in: environment)
        let childEnvironment = backend.computeButtonLabelEnvironment(from: environment)

        var childProposal = proposedSize
        if let proposedWidth = proposedSize.width {
            childProposal.width = max(proposedWidth - Double(buttonPadding.x), 0)
        }
        if let proposedHeight = proposedSize.height {
            childProposal.height = max(proposedHeight - Double(buttonPadding.y), 0)
        }

        let childResult = children.child0.computeLayout(
            with: body.view0,
            proposedSize: childProposal,
            environment: childEnvironment
        )

        backend.updateButton(
            widget,
            // The role rides in on the environment rather than as a parameter,
            // so that adding it does not change `updateButton`'s signature and
            // break every backend at once. Written unconditionally, including
            // the nil case, because a widget is reused across updates and a
            // button that stops being destructive has to stop looking it.
            // role 是搭著 environment 傳入，而非作為參數，如此新增它便不會改動 `updateButton` 的
            // 簽名、一次弄壞所有 backend。此處無條件寫入（包含 nil 的情況），因為 widget 會在多次
            // 更新之間被重複使用，而一個不再具有破壞性的按鈕也必須不再看起來具有破壞性。
            environment: environment.with(\.buttonRole, role),
            action: action
        )

        // Buttons should always be set to label size + padding.
        // The backend representation of a button is expected not to have a minSize.
        let size = SIMD2(
            Int(childResult.size.width) + buttonPadding.x,
            Int(childResult.size.height) + buttonPadding.y
        )

        return ViewLayoutResult.leafView(size: ViewSize(size))
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.child0.commit()
        backend.setSize(of: widget, to: layout.size.vector)
    }

    public var _asMenuItems: [MenuItem] {
        if let self = self as? Button<TupleView1<Text>> {
            return [.button(self)]
        } else {
            // TODO(stackotter): Figure out a better fallback for non-text buttons in menus
            return body._asMenuItems
        }
    }
}
