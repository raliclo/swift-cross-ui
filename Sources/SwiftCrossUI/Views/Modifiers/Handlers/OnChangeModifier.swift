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
    // ~~TODO: This probably doesn't have to trigger view updates. We're only
    //   really using @State here to persist the data.~~ Done 2026-11-12: it did
    // trigger them. Assigning `@State previousValue` inside `computeLayout`
    // published a change on the first layout, so every `.onChange` re-laid out
    // its whole subtree once after the window opened, and (its first bottom-up
    // update) asked the window to lay out again on top. P998 with two
    // `.onChange` around a 1750-node page: 1753 commits in the first update,
    // then 3500 + 3499 from the two modifiers. The value now lives in a box
    // inside `@State`, which keeps it as long as the node and publishes nothing,
    // as `ScrollViewReader`'s `RegistryHolder` does.
    // ~~TODO:這大概不必觸發 view 更新。這裡用 @State 只是為了保存資料。~~ 2026-11-12 完成：它確實觸發了。在
    // `computeLayout` 裡賦值 `@State previousValue` 會在第一次排版時發出變更，於是每個 `.onChange` 在視窗開啟後都把
    // 整棵子樹重排一次，而且(它的第一次由下往上更新)還要求視窗再排一次。P998 以兩個 `.onChange` 包住 1750 個節點的頁面：
    // 第一次更新 1753 次 commit,接著兩個 modifier 各 3500、3499 次。現在值放在 `@State` 裡的 box 中，跟節點一樣長壽且
    // 不發出任何通知，與 `ScrollViewReader` 的 `RegistryHolder` 相同。
    @State var previous = PreviousValueHolder<Value>()

    private var previousValue: Value? {
        get { previous.box.value }
        nonmutating set { previous.box.value = newValue }
    }

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

/// The last value an `.onChange` saw, kept without change notifications; see
/// `OnChangeModifier.previous`. / `.onChange` 上次看到的值，不發出變更通知;見 `OnChangeModifier.previous`。
struct PreviousValueHolder<Value> {
    let box = Box<Value?>(nil)
}
