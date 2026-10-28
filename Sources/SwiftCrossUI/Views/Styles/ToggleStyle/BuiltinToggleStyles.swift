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
/// **The label.** A string label in the button style is the native toggle's
/// own title (`ToggleButton`). A view label in the button style is hosted
/// inside the native toggle (`ViewLabelToggleButton`, through
/// ``BackendFeatures/ViewLabelToggleButtons``). In the switch and checkbox
/// styles the label, string or view, sits beside an unlabelled control, as
/// SwiftUI lays a toggle out on macOS and iOS; a click on it flips the toggle,
/// and the control's accessibility label is the label's text, so a screen
/// reader announces the control by what is written beside it.
///
/// 它是「一個 view 依三個 case 分支」而非三個
/// view，因為兩個 `HStack` 分支之間的差別只在標籤之後放什麼，拆開會讓標籤的處理重複三次。
///
/// **標籤。** 按鈕樣式下的字串標籤是原生 toggle 自己的標題(`ToggleButton`)。按鈕樣式下的 view 標籤容納在原生 toggle
/// 裡面(`ViewLabelToggleButton`,經由 ``BackendFeatures/ViewLabelToggleButtons``)。在 switch 與 checkbox 樣式中，
/// 標籤(字串或 view)位於一個無標籤控制項旁邊，與 SwiftUI 在 macOS 與 iOS 上排列 toggle 的方式相同；點擊它會翻轉
/// toggle,而控制項的輔助使用標籤就是標籤的文字，讓螢幕閱讀器以旁邊所寫的內容稱呼該控制項。
public struct _BuiltinToggleImplementation: View {
    @Environment(\.backend) var backend
    @Environment(\.isEnabled) var isEnabled

    var style: BackendToggleStyle
    var label: String
    /// The view label, or `nil` for a string label. / view 標籤；字串標籤時為 `nil`。
    var labelView: AnyView? = nil
    var isOn: Binding<Bool>

    public var body: some View {
        switch style {
            case .switch:
                HStack {
                    besideLabel

                    if backend.requiresToggleSwitchSpacer {
                        Spacer()
                    }

                    ToggleSwitch(isOn: isOn)
                        .accessibilityLabel(label.isEmpty ? nil : label)
                }
            case .button:
                if let labelView {
                    if backend is any BackendFeatures.ViewLabelToggleButtons {
                        ViewLabelToggleButton(label: labelView, isOn: isOn)
                    } else {
                        // Only a backend outside the five shipped ones lands here
                        // (all five conform). The label stays visible and a click
                        // still flips the value; there is no on-state bezel.
                        // 只有五個已發布 backend 以外的 backend 會走到這裡(五者都遵循)。標籤仍然可見，點擊仍然翻轉值；
                        // 只是沒有開啟狀態的外框。
                        Button(action: toggleAction) {
                            labelView
                        }
                    }
                } else {
                    ToggleButton(label, isOn: isOn)
                }
            case .checkbox:
                HStack {
                    besideLabel

                    Checkbox(isOn: isOn)
                        .accessibilityLabel(label.isEmpty ? nil : label)
                }
        }
    }

    /// Flips the value. / 翻轉值。
    private var toggleAction: @MainActor @Sendable () -> Void {
        let isOn = self.isOn
        return { isOn.wrappedValue.toggle() }
    }

    /// The label beside a switch or checkbox. A click on it flips the toggle,
    /// as a click on the label of a checkbox does on every desktop toolkit.
    ///
    /// switch 或 checkbox 旁邊的標籤。點擊它會翻轉 toggle,與每個桌面 toolkit 上點擊 checkbox 標籤的效果相同。
    @ViewBuilder
    private var besideLabel: some View {
        let content = labelView ?? AnyView(Text(label))
        if isEnabled, backend is any BackendFeatures.TapGestures {
            content
                .onTapGesture(perform: toggleAction)
        } else {
            content
        }
    }
}
