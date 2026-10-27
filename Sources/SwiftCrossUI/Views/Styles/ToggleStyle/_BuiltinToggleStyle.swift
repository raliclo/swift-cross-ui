/// A built-in toggle style backed by a control the backend already has.
///
/// Each of the three maps to its own control (``BackendFeatures/Switches``,
/// ``BackendFeatures/Checkboxes``, ``BackendFeatures/ToggleButtons``), and
/// `BaseAppBackend` requires all three through ``BackendFeatures/Controls``.
///
/// 三者各自對應一種控制項(``BackendFeatures/Switches``、``BackendFeatures/Checkboxes``、
/// ``BackendFeatures/ToggleButtons``),而 `BaseAppBackend` 經由 ``BackendFeatures/Controls`` 要求全部三者。
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
    // An override asking `backend is any BackendFeatures.Switches` per style
    // is always true, as the compiler reports: `BaseAppBackend` composes
    // `BackendFeatures.Controls`, which is `Buttons & ToggleButtons & Switches
    // & Checkboxes & ...`, so every backend that can be passed here already
    // conforms to all three at compile time.
    //
    // `_BuiltinPickerStyle` is the shape a real query takes:
    // `backend.supportedPickerStyles.contains(...)`, answered by the backend at
    // run time, because `Pickers` has styles a backend may lack. Toggles have
    // no such list because the three controls are mandatory, so `true` is the
    // honest answer rather than a shortcut.
    //
    // 此處刻意不覆寫 `isSupported`，三個內建 style 使用 `ToggleStyle` 的預設值 `true`。
    //
    // 逐一 style 詢問 `backend is any BackendFeatures.Switches` 的覆寫恆為真(編譯器也這麼說):
    // `BaseAppBackend` 組合了 `BackendFeatures.Controls`,後者即
    // `Buttons & ToggleButtons & Switches & Checkboxes & ...`,因此任何能被傳進此處的 backend
    // 在編譯期就已遵循全部三者。
    //
    // `_BuiltinPickerStyle` 才是「真正的查詢」該有的形狀：
    // `backend.supportedPickerStyles.contains(...)`，由 backend 在執行期回答，因為 `Pickers`
    // 帶有某些 backend 可能沒有的 style。Toggle 沒有這樣一份清單，因為那三個控制項是必備的
    // ——所以 `true` 是如實的答案，而不是便宜行事。
}
