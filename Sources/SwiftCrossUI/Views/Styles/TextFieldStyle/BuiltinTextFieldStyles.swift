import DebugFeatures

/// The four built-in text field styles, and the view that draws them.
///
/// The `where Self == …` extensions keep `.textFieldStyle(.roundedBorder)`
/// reading exactly as it does in SwiftUI, while the protocol underneath is open
/// -- see ``TextFieldStyle`` for why that divergence is deliberate.
///
/// 這四個 `where Self == …` 擴充讓 `.textFieldStyle(.roundedBorder)` 讀起來與 SwiftUI 完全一致，
/// 而底下的 protocol 是開放的——這項刻意的偏離，其理由見 ``TextFieldStyle``。

/// The platform's own text field appearance.
///
/// See ``BackendTextFieldStyle/automatic`` for what that is on each of the five
/// backends; it is not an alias for any of the other three.
public struct AutomaticTextFieldStyle: TextFieldStyle, _BuiltinTextFieldStyle {
    public nonisolated init() {}

    public func _asBackendTextFieldStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendTextFieldStyle
    {
        .automatic
    }
}

extension TextFieldStyle where Self == AutomaticTextFieldStyle {
    /// The platform's own text field appearance.
    public static nonisolated var automatic: Self { Self() }
}

/// A text field with no border, bezel or background of its own.
public struct PlainTextFieldStyle: TextFieldStyle, _BuiltinTextFieldStyle {
    public nonisolated init() {}

    public func _asBackendTextFieldStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendTextFieldStyle
    {
        .plain
    }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    /// A text field with no border, bezel or background of its own.
    public static nonisolated var plain: Self { Self() }
}

/// A text field with a rounded border.
public struct RoundedBorderTextFieldStyle: TextFieldStyle, _BuiltinTextFieldStyle {
    public nonisolated init() {}

    public func _asBackendTextFieldStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendTextFieldStyle
    {
        .roundedBorder
    }
}

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    /// A text field with a rounded border.
    public static nonisolated var roundedBorder: Self { Self() }
}

/// A text field with a square border.
///
/// Available on every backend, unlike SwiftUI's macOS-only `squareBorder`; see
/// ``BackendTextFieldStyle/squareBorder`` for why the restriction was not
/// copied.
///
/// 與 SwiftUI 僅限 macOS 的 `squareBorder` 不同，此處於每一個 backend 上皆可用；未照抄該限制的
/// 理由見 ``BackendTextFieldStyle/squareBorder``。
public struct SquareBorderTextFieldStyle: TextFieldStyle, _BuiltinTextFieldStyle {
    public nonisolated init() {}

    public func _asBackendTextFieldStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendTextFieldStyle
    {
        .squareBorder
    }
}

extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    /// A text field with a square border.
    public static nonisolated var squareBorder: Self { Self() }
}

/// What the four built-in styles draw: the backend's own text field, told which
/// border to use.
///
/// This is ``TextField``'s old body, moved rather than rewritten -- the widget
/// creation, the layout, the binding write-back and the `SCUI_DEBUG` check are
/// all unchanged. The one addition is the line that puts ``style`` into the
/// environment handed to `updateTextField`.
///
/// **Why the environment and not a new parameter.** `updateTextField` already
/// receives `EnvironmentValues`, so the style can reach a backend without
/// changing a signature that seven backends implement. That is the same channel
/// ``EnvironmentValues/backendListStyle`` and
/// ``EnvironmentValues/backendDatePickerStyle`` use, and for the same reason.
///
/// **Why it is set here rather than by the modifier.** `textFieldStyle(_:)`
/// writes ``EnvironmentValues/textFieldStyle``, an `any TextFieldStyle`, which
/// no backend can read. Resolving it to a `BackendTextFieldStyle` needs
/// `_asBackendTextFieldStyle`, which only a *built-in* style has -- so the
/// resolution belongs to the built-in path, not to the modifier. Setting it in
/// the modifier would also leak the value onto every other widget in the
/// subtree, which is harmless today only because nothing else reads it.
///
/// **為何走 environment 而非新增參數。** `updateTextField` 本來就會收到 `EnvironmentValues`，
/// 因此 style 不必更動一個有七個 backend 實作的簽章就能抵達 backend。這與
/// ``EnvironmentValues/backendListStyle``、``EnvironmentValues/backendDatePickerStyle`` 使用的是
/// 同一條通道，理由也相同。
///
/// **為何在此處設定、而非由 modifier 設定。** `textFieldStyle(_:)` 寫入的是
/// ``EnvironmentValues/textFieldStyle``，一個 `any TextFieldStyle`，沒有任何 backend 讀得懂。
/// 要把它解析成 `BackendTextFieldStyle` 需要 `_asBackendTextFieldStyle`，而只有**內建** style 才有
/// 該方法——所以這項解析屬於內建路徑，不屬於 modifier。在 modifier 中設定還會把該值洩漏到子樹中
/// 其他每一個 widget 上；那今天之所以無害，僅僅是因為目前沒有別的東西會讀它。
public struct _BuiltinTextFieldImplementation: ElementaryView, View {
    /// The ideal width of a text field.
    private static let idealWidth: Double = 100

    var style: BackendTextFieldStyle
    var placeholder: String
    var text: Binding<String>

    init(style: BackendTextFieldStyle, placeholder: String, text: Binding<String>) {
        self.style = style
        self.placeholder = placeholder
        self.text = text
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
            environment: environment.with(\.backendTextFieldStyle, style),
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
                if DebugFeatures.isEnabled, self.text.wrappedValue == newValue {
                    logger.warning(
                        """
                        Unnecessary write to text Binding of TextField detected, \
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
        if text != backend.getContent(ofTextField: widget) {
            backend.setContent(ofTextField: widget, to: text)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }
}
