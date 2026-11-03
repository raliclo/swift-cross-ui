extension View {
    /// A view modifier that runs an action whenever a piece of state changes.
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes. Must be `Equatable`.
    ///   - initial: Whether to call `action` when the view first appears.
    ///   - action: The action to perform.
    public func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        perform action: @escaping () -> Void
    ) -> some View {
        OnChangeModifier(
            body: TupleView1(self),
            value: value,
            action: { _, _ in action() },
            initial: initial
        )
    }

    /// A view modifier that runs an action with the old and new value
    /// whenever a piece of state changes, as SwiftUI's
    /// `onChange(of:initial:_:)` does.
    ///
    /// When `initial` is true the action also runs when the view first
    /// appears, with the current value as both arguments.
    ///
    /// 每當一份狀態改變時，以舊值與新值執行一個動作的 view modifier,與 SwiftUI 的 `onChange(of:initial:_:)`
    /// 相同。`initial` 為 true 時，動作也會在 view 首次出現時執行，兩個引數都是目前的值。
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes. Must be `Equatable`.
    ///   - initial: Whether to call `action` when the view first appears.
    ///   - action: The action to perform, given the old value and the new one.
    public func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        OnChangeModifier(
            body: TupleView1(self),
            value: value,
            action: action,
            initial: initial
        )
    }
}

struct OnChangeModifier<Value: Equatable, Content: View>: View {
    // TODO: This probably doesn't have to trigger view updates. We're only
    //   really using @State here to persist the data.
    @State var previousValue: Value?

    var body: TupleView1<Content>

    var value: Value
    /// Given the old value and the new one; both are the current value for
    /// the `initial` call.
    /// 傳入舊值與新值;`initial` 那一次兩者都是目前的值。
    var action: (_ oldValue: Value, _ newValue: Value) -> Void
    var initial: Bool

    // TODO: Should this go in computeLayout or commit?
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        if let previousValue, value != previousValue {
            action(previousValue, value)
        } else if initial, previousValue == nil {
            action(value, value)
        }

        if previousValue != value {
            previousValue = value
        }

        return defaultComputeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }
}
