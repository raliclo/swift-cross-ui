/// A control that displays an editable text interface.
///
/// Depending on the value of ``EnvironmentValues/textFieldStyle``, this control
/// can appear with the platform's own chrome, with no chrome at all, or with a
/// rounded or square border. See ``TextFieldStyle`` and
/// ``View/textFieldStyle(_:)``.
public struct TextField: View {
    @Environment(\.self) var environment
    @Environment(\.textFieldStyle) var textFieldStyle

    /// The label to show when the field is empty.
    private var placeholder: String
    /// The field's content.
    @Binding private var text: String

    /// Creates an editable text field with a given placeholder.
    ///
    /// - Parameters:
    ///   - placeholder: The label to show when the field is empty.
    ///   - text: The field's content.
    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    /// Creates an editable text field with a given placeholder.
    @available(*, deprecated, renamed: "init(_:text:)")
    public init(_ placeholder: String = "", _ value: Binding<String>? = nil) {
        self.placeholder = placeholder
        var dummy = ""
        self._text = value ?? Binding(get: { dummy }, set: { dummy = $0 })
    }

    /// Creates an editable text field bound to a binary integer value.
    ///
    /// The field's content is kept in sync with `value` via simple string
    /// conversion. When the user enters text that cannot be parsed as the
    /// target integer type, the binding is not updated (the previous value
    /// is preserved), mirroring the behaviour of SwiftUI's
    /// `TextField(_:value:formatter:)` when the formatter fails.
    ///
    /// - Parameters:
    ///   - placeholder: The label to show when the field is empty.
    ///   - value: A binding to the integer value to edit.
    public init<V: BinaryInteger & LosslessStringConvertible>(
        _ placeholder: String = "",
        value: Binding<V>
    ) {
        self.placeholder = placeholder
        self._text = Binding(
            get: { String(value.wrappedValue) },
            set: { newString in
                if let parsed = V(newString), parsed != value.wrappedValue {
                    value.wrappedValue = parsed
                }
            }
        )
    }

    /// Creates an editable text field bound to a binary floating-point value.
    ///
    /// The field's content is kept in sync with `value` via simple string
    /// conversion. When the user enters text that cannot be parsed as the
    /// target floating-point type, the binding is not updated (the previous
    /// value is preserved), mirroring the behaviour of SwiftUI's
    /// `TextField(_:value:formatter:)` when the formatter fails.
    ///
    /// - Parameters:
    ///   - placeholder: The label to show when the field is empty.
    ///   - value: A binding to the floating-point value to edit.
    public init<V: BinaryFloatingPoint & LosslessStringConvertible>(
        _ placeholder: String = "",
        value: Binding<V>
    ) {
        self.placeholder = placeholder
        self._text = Binding(
            get: { String(value.wrappedValue) },
            set: { newString in
                if let parsed = V(newString), parsed != value.wrappedValue {
                    value.wrappedValue = parsed
                }
            }
        )
    }

    public var body: some View {
        // Routed through the style, exactly as `Toggle` is. The four built-in
        // styles reach `_BuiltinTextFieldImplementation`, the `ElementaryView`
        // with `asWidget`, `computeLayout` and `commit`; a style written outside
        // this module draws whatever it likes instead. `AnyView` because the
        // style is existential and its `Body` is not known here.
        //
        // This is what makes `TextFieldStyle` open rather than SwiftUI's
        // closed-and-empty protocol. Resolving the style inside `commit` and
        // leaving `TextField` elementary would support only the four shapes a
        // backend can draw -- an application's own style has a view to render,
        // and a leaf view has nowhere to render it.
        //
        // 交由 style 繪製，與 `Toggle` 完全相同。四個內建 style 取用 `_BuiltinTextFieldImplementation`
        // ——帶有 `asWidget`、`computeLayout`、`commit` 的 `ElementaryView`;而在本模組之外撰寫的 style
        // 則想畫什麼就畫什麼。使用 `AnyView`，因為此處的 style 是 existential，其 `Body` 型別在這裡
        // 無從得知。
        //
        // 正是這一點讓 `TextFieldStyle` 得以開放，而非比照 SwiftUI 那個封閉且空白的 protocol。
        // 在 `commit` 之中解析 style、並讓 `TextField` 維持為 elementary，只能支援 backend 畫得出來的
        // 那四種外形——應用程式自訂的 style 帶著一個 view 要算繪，而一個葉節點 view 沒有地方可以算繪它。
        AnyView(
            textFieldStyle.makeView(
                placeholder: placeholder,
                text: $text,
                environment: environment
            )
        )
    }
}
