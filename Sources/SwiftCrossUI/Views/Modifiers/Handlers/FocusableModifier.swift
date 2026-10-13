extension View {
    /// Lets this view hold the keyboard focus although it is not a control.
    ///
    /// ```swift
    /// @FocusState var focused: Bool
    ///
    /// Color.blue
    ///     .frame(width: 120, height: 80)
    ///     .focusable()
    ///     .focused($focused)
    ///     .onKeyPress { press in typed += press.characters }
    /// ```
    ///
    /// The view becomes a Tab stop and takes the focus when it is pressed;
    /// `.focused` can then move the focus to it and `.onKeyPress` hears the
    /// keys typed while it has it. Write `.focusable()` first and the other two
    /// after it, as above: they act on the focusable view inside them.
    ///
    /// Tab and Shift-Tab move the focus on and are not reported to `.onKeyPress`
    /// on AppKit, GTK and UIKit; on Android the system moves the focus and the key is reported too.
    ///
    /// **`.onKeyPress` around a focusable view waits for the focus.** On its own
    /// it takes the focus when it appears, so that a view with only a key
    /// handler hears keys at all; around a `.focusable()` view it does not, and
    /// hears the keys typed while that view has the focus.
    ///
    /// `.focusable(false)` leaves the view as it was: no Tab stop, and a request
    /// through `.focused` is refused and written back as not focused.
    ///
    /// 讓這個不是控制項的 view 能持有鍵盤焦點。它成為 Tab 停駐點，被按下時取得焦點;之後 `.focused` 可以把焦點
    /// 移給它，`.onKeyPress` 聽得到它持有焦點時打的字。請像上面那樣先寫 `.focusable()`、再寫另外兩個:它們作用在
    /// 自己裡面那個可聚焦的 view 上。Tab 與 Shift-Tab 用來移走焦點，在 AppKit、GTK 與 UIKit 上不回報給 `.onKeyPress`;
    /// Android 由系統移動焦點，按鍵也照樣回報。包在可聚焦 view 外面的 `.onKeyPress` 會等焦點:它單獨使用時一出現就取得焦點，
    /// 包著 `.focusable()` 時則不會，只聽該 view 持有焦點時的按鍵。`.focusable(false)` 讓 view 維持原狀:
    /// 不是 Tab 停駐點，經由 `.focused` 的要求會被拒絕並寫回未聚焦。
    public func focusable(_ isFocusable: Bool = true) -> some View {
        FocusableModifier(body: TupleView1(self), isFocusable: isFocusable)
    }
}

struct FocusableModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var isFocusable: Bool

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.FocusableTargets
        else {
            FocusableDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.FocusableTargets>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createFocusableTarget(wrapping: child as! Backend.Widget)
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
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.FocusableTargets
        else { return }
        update(backend, widget: widget, size: size, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.FocusableTargets>(
        _ backend: Backend,
        widget: Any,
        size: ViewSize,
        environment: EnvironmentValues
    ) {
        backend.setSize(of: widget as! Backend.Widget, to: size.vector)
        backend.updateFocusableTarget(
            widget as! Backend.Widget,
            environment: environment,
            isFocusable: isFocusable
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次，因為一個 view 每次更新都會 commit。
enum FocusableDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.FocusableTargets, so .focusable \
            changes nothing on this backend -- the view is no Tab stop, a press does not \
            focus it and .focused on it is refused. What to change: implement the two \
            methods of that protocol with a wrapper that can hold the focus, takes it when \
            pressed without taking the press, and moves it on at Tab. AppKitBackend \
            overrides acceptsFirstResponder; UIKitBackend canBecomeFirstResponder and \
            canBecomeFocused; GtkBackend calls gtk_widget_set_focusable; AndroidBackend \
            sets isFocusable and isFocusableInTouchMode; WinUI has IsTabStop on a Control.
            """
        )
    }
}
