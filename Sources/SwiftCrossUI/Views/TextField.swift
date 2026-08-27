import DebugFeatures

/// A control that displays an editable text interface.
public struct TextField: ElementaryView, View {
    /// The ideal width of a `TextField`.
    private static let idealWidth: Double = 100

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

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        return backend.createTextField()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let naturalHeight = backend.naturalSize(of: widget).y
        let size = ViewSize(
            proposedSize.width ?? Self.idealWidth,
            Double(naturalHeight)
        )

        // TODO: Allow backends to set their own ideal text field width
        return ViewLayoutResult.leafView(size: size)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.updateTextField(
            widget,
            placeholder: placeholder,
            environment: environment,
            onChange: { newValue in
                // This check catches backends that cause unnecessary binding
                // writes, usually the handler firing because we called
                // backend.setContent(ofTextField:to:). Comparing text on every
                // keystroke is often more expensive than the extra write it
                // detects, so it is not done unconditionally.
                //
                // It was `#if DEBUG`, which put it in no configuration this
                // project builds: `testapp/compile.zsh` builds release, so the
                // very backends the check exists to catch were never checked.
                // `DebugFeatures.isEnabled` keeps the cost argument intact -- it
                // is a `static let` that is `false` and foldable in a build
                // without `SCUI_DEBUG` -- while making the check reachable in a
                // release binary built and run with the flag.
                //
                // 此檢查用於揪出會造成不必要 binding 寫入的 backend，通常是因為我們呼叫
                // backend.setContent(ofTextField:to:) 而反過來觸發了 handler。每次按鍵都比較
                // 文字，往往比它所偵測到的那次多餘寫入還昂貴，因此不無條件執行。
                //
                // 它原本是 `#if DEBUG`，而那讓它不存在於本專案建置的任何組態中：
                // `testapp/compile.zsh` 建置的是 release，於是此檢查存在的目的——揪出有問題的
                // backend——從來沒有被執行過。`DebugFeatures.isEnabled` 保留了原本的成本論證
                // ——在未設定 `SCUI_DEBUG` 的建置中，它是一個為 `false` 且可被摺除的
                // `static let`——同時使該檢查在「以該旗標建置並執行」的 release 執行檔中可觸及。
                if DebugFeatures.isEnabled, self.text == newValue {
                    logger.warning(
                        """
                        Unnecessary write to text Binding of TextField detected, \
                        please open an issue at \(Meta.issueReportingURL) \
                        so we can fix it for \(type(of: backend)).
                        """
                    )
                }

                self.text = newValue
            },
            onSubmit: environment.onSubmit ?? {}
        )

        let text = text
        if text != backend.getContent(ofTextField: widget) {
            backend.setContent(ofTextField: widget, to: text)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }
}
