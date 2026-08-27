/// An action that dismisses the current presentation context.
///
/// Use the `dismiss` environment value to get an instance of this action,
/// then call it to dismiss (close) the enclosing sheet.
///
/// If you want to close the enclosing window, use ``EnvironmentValues/dismissWindow``
/// instead.
///
/// Example usage:
/// ```swift
/// struct SheetContentView: View {
///     @Environment(\.dismiss) var dismiss
///
///     var body: some View {
///         VStack {
///             Text("Sheet Content")
///             Button("Close") {
///                 dismiss()
///             }
///         }
///     }
/// }
/// ```
@MainActor
public struct DismissAction {
    private let action: @Sendable @MainActor () -> Void

    nonisolated internal init(action: @escaping @Sendable @MainActor () -> Void) {
        self.action = action
    }

    /// Dismisses the current presentation context.
    public func callAsFunction() {
        action()
    }
}

/// Environment key for the dismiss action.
private struct DismissActionKey: EnvironmentKey {
    static var defaultValue: DismissAction {
        DismissAction(action: {
            // Ungated. The default action is a no-op, so a `dismiss()` reached
            // outside any presentation context does nothing and looks like a
            // sheet that will not close. Under `#if DEBUG` the explanation was
            // absent from every release build -- which is what this project
            // builds by default -- leaving the author with a dead button and no
            // message. The warning only fires on the mistake, so it costs a
            // correct app nothing.
            //
            // 不設條件。預設動作是空的，因此在任何 presentation context 之外呼叫 `dismiss()`
            // 什麼也不會發生，看起來就像一個關不掉的 sheet。原本置於 `#if DEBUG` 之下，使得
            // 這段說明在每個 release 建置中都不存在——而 release 正是本專案的預設建置方式——
            // 作者只會看到一顆沒有反應的按鈕，卻收不到任何訊息。此警告僅在犯錯時觸發，因此對
            // 正確的 app 不構成任何代價。
            logger.warning("dismiss() called but no presentation context is available")
        })
    }
}

extension EnvironmentValues {
    /// An action that dismisses the current presentation context.
    ///
    /// Use this environment value to get a dismiss action that can be called
    /// to dismiss (close) the enclosing sheet, popover, or other presentation.
    ///
    /// If you want to close the enclosing window, use ``EnvironmentValues/dismissWindow``
    /// instead.
    ///
    /// Example:
    /// ```swift
    /// struct SheetContentView: View {
    ///     @Environment(\.dismiss) var dismiss
    ///
    ///     var body: some View {
    ///         Button("Close") {
    ///             dismiss()
    ///         }
    ///     }
    /// }
    /// ```
    @MainActor
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}
