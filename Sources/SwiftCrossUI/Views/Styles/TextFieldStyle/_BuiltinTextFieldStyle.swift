/// A built-in text field style backed by the backend's own text field widget.
///
/// The counterpart of ``_BuiltinToggleStyle`` and ``_BuiltinDatePickerStyle``.
/// Conforming supplies ``TextFieldStyle``'s ``TextFieldStyle/makeView(placeholder:text:environment:)``:
/// the view is the backend's own control, told which border to draw.
///
/// 對應於 ``_BuiltinToggleStyle`` 與 ``_BuiltinDatePickerStyle``。遵循它即供應
/// ``TextFieldStyle`` 的 ``TextFieldStyle/makeView(placeholder:text:environment:)``：
/// 該 view 就是 backend 自身的控制項，只是被告知要畫哪一種邊框。
public protocol _BuiltinTextFieldStyle {
    @MainActor
    func _asBackendTextFieldStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendTextFieldStyle
}

extension TextFieldStyle where Self: _BuiltinTextFieldStyle {
    public func makeView(
        placeholder: String,
        text: Binding<String>,
        environment: EnvironmentValues
    ) -> _BuiltinTextFieldImplementation {
        _BuiltinTextFieldImplementation(
            style: _asBackendTextFieldStyle(backend: environment.backend),
            placeholder: placeholder,
            text: text
        )
    }

    // `isSupported` is deliberately not overridden, and the four built-in
    // styles take `TextFieldStyle`'s default `true`. This is the
    // `_BuiltinToggleStyle` situation rather than the `_BuiltinPickerStyle`
    // one, and the distinction is worth stating because the two look alike.
    //
    // `_BuiltinPickerStyle` asks `backend.supportedPickerStyles.contains(...)`,
    // a real run-time query, because a picker style names a *different widget*
    // -- a wheel is not a menu -- and a backend may genuinely have one and not
    // the other. `_BuiltinDatePickerStyle` does the same, and additionally has
    // to cast, because date pickers are an opt-in feature a backend may lack
    // entirely.
    //
    // Text fields have neither problem. All four shapes are the *same* widget,
    // the one `createTextField()` already returns, with different border
    // properties set on it; and `BackendFeatures.TextFields` is composed into
    // `BackendFeatures.Controls` and so into `BaseAppBackend`, meaning every
    // backend that can be passed here has text fields at compile time. There is
    // no `supportedTextFieldStyles` to consult and adding one would only be a
    // list that is always full. `true` is the honest answer.
    //
    // 此處刻意不覆寫 `isSupported`，四個內建 style 使用 `TextFieldStyle` 的預設值 `true`。這屬於
    // `_BuiltinToggleStyle` 的情形而非 `_BuiltinPickerStyle` 的情形，而兩者外觀相似，因此值得說明
    // 其差別。
    //
    // `_BuiltinPickerStyle` 執行的是 `backend.supportedPickerStyles.contains(...)`，一次真正的
    // 執行期查詢，因為 picker style 指名的是**不同的 widget**——滾輪不是選單——某個 backend 確實
    // 可能只有其中一個。`_BuiltinDatePickerStyle` 亦然，且還必須額外做 cast，因為日期選擇器是
    // backend 可能完全不具備的選用功能。
    //
    // 文字輸入框沒有這兩個問題。四種外形都是**同一個** widget，即 `createTextField()` 本來就會回傳
    // 的那一個，只是設定了不同的邊框屬性；而 `BackendFeatures.TextFields` 被組合進
    // `BackendFeatures.Controls`、進而組合進 `BaseAppBackend`，因此任何能被傳進此處的 backend 在
    // 編譯期就已具備文字輸入框。沒有 `supportedTextFieldStyles` 可查，就算加一份，也只會是一份
    // 永遠是滿的清單。`true` 是如實的答案。
}
