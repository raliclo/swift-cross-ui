import DebugFeatures

/// A control that displays an editable text interface, hiding characters
/// as they're typed.
public struct SecureField: ElementaryView, View {
    /// The ideal width of a `SecureField`.
    private static let idealWidth: Double = 100

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
                // out at the matching check in `TextField.swift`: the cost of
                // comparing text on every keystroke is why it is conditional at
                // all, and `#if DEBUG` made it conditional on a configuration
                // this project never builds.
                //
                // 改以 `SCUI_DEBUG` 為條件、而非 `#if DEBUG`，理由詳見 `TextField.swift` 中對應
                // 的檢查：每次按鍵都比較文字的代價，正是它必須帶條件的原因；而 `#if DEBUG` 讓它
                // 取決於一個本專案從不建置的組態。
                if DebugFeatures.isEnabled, self.text == newValue {
                    logger.warning(
                        """
                        Unnecessary write to text Binding of SecureField detected, \
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
        if text != backend.getContent(ofSecureField: widget) {
            backend.setContent(ofSecureField: widget, to: text)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }
}
