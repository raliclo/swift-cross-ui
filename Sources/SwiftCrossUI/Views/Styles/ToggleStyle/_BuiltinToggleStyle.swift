/// A built-in toggle style backed by a control the backend already has.
///
/// Each of the three lands on a different opt-in backend feature, so support is
/// asked per style rather than answered once for toggles as a whole: a backend
/// may have ``BackendFeatures/Switches`` and not ``BackendFeatures/Checkboxes``.
///
/// 三者各自落在不同的選用 backend 功能上，因此「是否支援」是逐一詢問，而非對「toggle」整體回答
/// 一次：某個 backend 可能有 ``BackendFeatures/Switches`` 卻沒有 ``BackendFeatures/Checkboxes``。
public protocol _BuiltinToggleStyle {
    @MainActor
    func _asBackendToggleStyle<Backend: BaseAppBackend>(backend: Backend) -> BackendToggleStyle
}

extension ToggleStyle where Self: _BuiltinToggleStyle {
    public func makeView(
        label: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> _BuiltinToggleImplementation {
        _BuiltinToggleImplementation(
            style: _asBackendToggleStyle(backend: environment.backend),
            label: label,
            isOn: isOn
        )
    }

    // `isSupported` is deliberately not overridden here, and the three built-in
    // styles take `ToggleStyle`'s default `true`.
    //
    // There was an override, and it asked `backend is any
    // BackendFeatures.Switches` per style. The compiler said the test was
    // always true and it was right: `BaseAppBackend` composes
    // `BackendFeatures.Controls`, which is `Buttons & ToggleButtons & Switches
    // & Checkboxes & ...`, so every backend that can be passed here already
    // conforms to all three at compile time. The switch computed an answer that
    // could only be `true`, and nothing called it -- the only `isSupported`
    // call sites in this package are the picker and date-picker modifiers.
    //
    // `_BuiltinPickerStyle` is the shape a real query takes:
    // `backend.supportedPickerStyles.contains(...)`, answered by the backend at
    // run time, because `Pickers` has styles a backend may lack. Toggles have
    // no such list because the three controls are mandatory, so `true` is the
    // honest answer rather than a shortcut.
    //
    // 此處刻意不覆寫 `isSupported`，三個內建 style 使用 `ToggleStyle` 的預設值 `true`。
    //
    // 這裡原本有一個覆寫，逐一 style 詢問 `backend is any BackendFeatures.Switches`。編譯器說該
    // 測試恆為真，而它是對的：`BaseAppBackend` 組合了 `BackendFeatures.Controls`，後者即
    // `Buttons & ToggleButtons & Switches & Checkboxes & ...`，因此任何能被傳進此處的 backend
    // 在編譯期就已遵循全部三者。那個 switch 算出的答案只可能是 `true`，而且沒有任何人呼叫它
    // ——本套件中僅有的 `isSupported` 呼叫點是 picker 與 date picker 的 modifier。
    //
    // `_BuiltinPickerStyle` 才是「真正的查詢」該有的形狀：
    // `backend.supportedPickerStyles.contains(...)`，由 backend 在執行期回答，因為 `Pickers`
    // 帶有某些 backend 可能沒有的 style。Toggle 沒有這樣一份清單，因為那三個控制項是必備的
    // ——所以 `true` 是如實的答案，而不是便宜行事。
}
