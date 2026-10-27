/// The three built-in toggle styles, and the view that draws them.
///
/// The `where Self == …` extensions keep `.toggleStyle(.checkbox)` reading
/// like a static member. That is the
/// point: a call site reads the same as it does against
/// SwiftUI, and a style of the author's own is possible as well.

/// A toggle switch.
public struct SwitchToggleStyle: ToggleStyle, _BuiltinToggleStyle {
    public nonisolated init() {}

    public func _asBackendToggleStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendToggleStyle
    {
        .switch
    }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// A toggle switch.
    public static nonisolated var `switch`: Self { Self() }
}

/// A toggle button. Generally looks like a regular button when off and an
/// accented button when on.
public struct ButtonToggleStyle: ToggleStyle, _BuiltinToggleStyle {
    public nonisolated init() {}

    public func _asBackendToggleStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendToggleStyle
    {
        .button
    }
}

extension ToggleStyle where Self == ButtonToggleStyle {
    /// A toggle button. Generally looks like a regular button when off and an
    /// accented button when on.
    public static nonisolated var button: Self { Self() }
}

/// A checkbox.
public struct CheckboxToggleStyle: ToggleStyle, _BuiltinToggleStyle {
    public nonisolated init() {}

    public func _asBackendToggleStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendToggleStyle
    {
        .checkbox
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    /// A checkbox.
    public static nonisolated var checkbox: Self { Self() }
}

/// What the three built-in styles draw.
///
/// It is one view
/// switching on three cases instead of three views, because the two `HStack`
/// arms differ only in what sits after the label, and splitting them would
/// duplicate the label handling three ways.
///
/// 它是「一個 view 依三個 case 分支」而非三個
/// view，因為兩個 `HStack` 分支之間的差別只在標籤之後放什麼，拆開會讓標籤的處理重複三次。
public struct _BuiltinToggleImplementation: View {
    @Environment(\.backend) var backend

    var style: BackendToggleStyle
    var label: String
    var isOn: Binding<Bool>

    public var body: some View {
        switch style {
            case .switch:
                HStack {
                    Text(label)

                    if backend.requiresToggleSwitchSpacer {
                        Spacer()
                    }

                    ToggleSwitch(isOn: isOn)
                }
            case .button:
                ToggleButton(label, isOn: isOn)
            case .checkbox:
                HStack {
                    Text(label)

                    Checkbox(isOn: isOn)
                }
        }
    }
}
