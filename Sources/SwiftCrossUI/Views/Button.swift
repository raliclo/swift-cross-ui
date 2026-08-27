/// A control that initiates an action.
public struct Button: Sendable {
    /// The label to show on the button.
    @_spi(Backends) public var label: String
    /// The action to be performed when the button is clicked.
    @_spi(Backends) public var action: @MainActor @Sendable () -> Void
    /// What the button is for, when that changes how it should look.
    @_spi(Backends) public var role: ButtonRole?
    /// The button's forced width if provided.
    var width: Int?

    /// Creates a button that displays a custom label.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - action: The action to be performed when the button is clicked.
    public init(_ label: String, action: @escaping @MainActor @Sendable () -> Void = {}) {
        self.label = label
        self.action = action
    }

    /// Creates a button with a role, which platforms may render differently.
    ///
    /// - Parameters:
    ///   - label: The label to show on the button.
    ///   - role: What the button is for. `.destructive` marks an action that is
    ///     hard to undo.
    ///   - action: The action to be performed when the button is clicked.
    ///
    /// SwiftUI spells this `Button(_:role:action:)`, and this matches. It is
    /// separate from the initialiser above rather than a defaulted parameter
    /// because adding a default would change the existing one's signature for
    /// no benefit.
    ///
    /// 建立一個帶有 role 的按鈕，各平台可能會以不同方式繪製它。
    ///
    /// SwiftUI 中寫作 `Button(_:role:action:)`，此處與之一致。之所以獨立為另一個建構式而非在原有
    /// 建構式上加預設參數，是因為加上預設值會改動既有建構式的簽名，卻換不到任何好處。
    public init(
        _ label: String,
        role: ButtonRole?,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.label = label
        self.role = role
        self.action = action
    }

    /// A temporary button width solution until arbitrary labels are supported.
    public func _buttonWidth(_ width: Int?) -> Button {
        var button = self
        button.width = width
        return button
    }
}

extension Button: View {
    public var _asMenuItems: [MenuItem] {
        [.button(self)]
    }
}

extension Button: ElementaryView {
    public func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        return backend.createButton()
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // TODO: Implement button sizing within SwiftCrossUI so that we can move this to
        //   commit. Relying on the backend for button sizing also makes the Gtk 3 backend
        //   basically impossible to implement correctly, hence the
        //   `finalContentSize != contentSize` check in WindowGroupNode to catch any weird
        //   behaviour. Without that extra safety net logic, buttons all end up label-less
        //   whenever the window grows due to a view containing buttons appearing. Not sure
        //   why all buttons lose their labels (until you click off the window, forcing it to
        //   refresh), but the reason Gtk 3 doesn't like it is that the window gets set smaller
        //   than its content I think.
        //   See: https://github.com/moreSwift/swift-cross-ui/blob/27f50579c52e79323c3c368512d37e95af576c25/Sources/SwiftCrossUI/Scenes/WindowGroupNode.swift#L140
        backend.updateButton(
            widget,
            label: label,
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
        let naturalSize = backend.naturalSize(of: widget)
        let size = SIMD2(
            width ?? naturalSize.x,
            naturalSize.y
        )

        return ViewLayoutResult.leafView(size: ViewSize(size))
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
    }
}
