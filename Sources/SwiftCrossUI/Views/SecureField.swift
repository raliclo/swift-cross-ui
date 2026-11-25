import DebugFeatures

/// A control that displays an editable text interface, hiding characters
/// as they're typed.
public struct SecureField: View {
    /// The label to show when the field is empty.
    private var placeholder: String
    /// The field's content.
    @Binding private var text: String

    /// Creates an editable secure text field with a given placeholder.
    ///
    /// - Parameters:
    ///   - placeholder: The label to show when the field is empty.
    ///   - text: The field's content.
    public init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    // The field is drawn at `controlSize(_:)`, as a built-in `TextField` style
    // is. `SecureField` used to be the leaf view itself, and a leaf has no
    // child to put `ControlSizeScaler` around; the widget now lives in
    // `SecureFieldImplementation`, and this body wraps it in the scaler. The
    // initializer and the `View` conformance are unchanged.
    //
    // 欄位以 `controlSize(_:)` 繪製，與內建 `TextField` style 相同。`SecureField` 過去本身就是葉節點
    // view,而葉節點沒有 child 可以讓 `ControlSizeScaler` 包住；現在 widget 移到
    // `SecureFieldImplementation`,由這個 body 把它包進 scaler。initializer 與 `View` conformance 不變。
    public var body: some View {
        SecureFieldImplementation(placeholder: placeholder, text: $text)
            .scaledToControlSize()
    }
}

/// The platform's secure field, laid out and updated for a ``SecureField``.
///
/// 平台的安全文字欄位，為 ``SecureField`` 排版與更新。
struct SecureFieldImplementation: ElementaryView, View {
    /// The ideal width of a `SecureField`.
    private static let idealWidth: Double = 100

    /// The label to show when the field is empty.
    var placeholder: String
    /// The field's content.
    var text: Binding<String>

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        return backend.createSecureField()
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
        backend.updateSecureField(
            widget,
            placeholder: placeholder,
            environment: environment,
            onChange: { newValue in
                // On `SCUI_DEBUG` rather than `#if DEBUG`, for the reasons set
                // out at the matching check in `BuiltinTextFieldStyles.swift`: the cost of
                // comparing text on every keystroke is why it is conditional at
                // all, and `#if DEBUG` made it conditional on a configuration
                // this project never builds.
                //
                // 改以 `SCUI_DEBUG` 為條件、而非 `#if DEBUG`，理由詳見 `BuiltinTextFieldStyles.swift` 中對應
                // 的檢查：每次按鍵都比較文字的代價，正是它必須帶條件的原因；而 `#if DEBUG` 讓它
                // 取決於一個本專案從不建置的組態。
                if DebugFeatures.isEnabled, self.text.wrappedValue == newValue {
                    logger.warning(
                        """
                        Unnecessary write to text Binding of SecureField detected, \
                        please open an issue at \(Meta.issueReportingURL) \
                        so we can fix it for \(type(of: backend)).
                        """
                    )
                }

                self.text.wrappedValue = newValue
            },
            onSubmit: environment.onSubmit ?? {}
        )

        let text = text.wrappedValue
        if text != backend.getContent(ofSecureField: widget) {
            backend.setContent(ofSecureField: widget, to: text)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }
}
