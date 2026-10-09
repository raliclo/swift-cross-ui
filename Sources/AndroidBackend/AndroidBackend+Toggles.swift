import AndroidKit
@_spi(Backends) import SwiftCrossUI

// implements BackendFeatures.ToggleButtons & BackendFeatures.Checkboxes & BackendFeatures.Switches
extension AndroidBackend {
    public var requiresToggleSwitchSpacer: Bool { false }

    public func createToggle() -> Widget {
        let toggle = AndroidKit.ToggleButton(
            Self.activity,
            environment: Self.env
        )
        helpers.styleToggleButton(toggle)
        return toggle
    }

    public func createCheckbox() -> Widget {
        AndroidKit.CheckBox(
            Self.activity,
            environment: Self.env
        )
    }

    public func createSwitch() -> Widget {
        AndroidKit.Switch(
            Self.activity,
            environment: Self.env
        )
    }

    private func updateCompoundButton(
        _ button: AndroidKit.CompoundButton,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        button.setEnabled(environment.isEnabled)

        let action = SwiftAction(environment: Self.env) {
            let checked = button.isChecked()
            onChange(checked)
        }
        let listener = CustomOnCheckedChangeListener(action, environment: Self.env)

        button.setOnCheckedChangeListener(
            listener.as(AndroidKit.CompoundButton.OnCheckedChangeListener.self)!
        )
    }

    public func updateToggle(
        _ toggle: Widget,
        label: String,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle.as(AndroidKit.ToggleButton.self)!
        updateCompoundButton(toggle, environment: environment, onChange: onChange)

        let charSequence = Self.charSequence(from: label)
        toggle.setAllCaps(false)
        toggle.setTextOn(charSequence)
        toggle.setTextOff(charSequence)

        getTextStyle(from: environment).apply(to: toggle)
        // `apply` sets one solid colour, which replaces the theme's state list
        // and with it the faded disabled text: P2's `.disabled(true)` toggle
        // read exactly like an enabled one. Material's disabled text is 38%.
        // `apply` 設的是單一固定顏色，蓋掉了主題的狀態色表，連帶蓋掉停用時的淡化文字:P2 的 `.disabled(true)`
        // 開關看起來和啟用的完全一樣。Material 的停用文字是 38%。
        if !environment.isEnabled {
            let color = environment.suggestedForegroundColor.resolve(in: environment).asColorInt()
            toggle.setTextColor((color & 0x00FF_FFFF) | 0x6100_0000)
        }
    }

    public func updateCheckbox(
        _ checkboxWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let checkboxWidget = checkboxWidget.as(AndroidKit.CompoundButton.self)!
        updateCompoundButton(checkboxWidget, environment: environment, onChange: onChange)
    }

    public func updateSwitch(
        _ switchWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let switchWidget = switchWidget.as(AndroidKit.CompoundButton.self)!
        updateCompoundButton(switchWidget, environment: environment, onChange: onChange)
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggle = toggle.as(AndroidKit.CompoundButton.self)!
        toggle.setChecked(state)
    }

    public func setState(ofCheckbox checkboxWidget: Widget, to state: Bool) {
        let checkboxWidget = checkboxWidget.as(AndroidKit.CompoundButton.self)!
        checkboxWidget.setChecked(state)
    }

    public func setState(ofSwitch switchWidget: Widget, to state: Bool) {
        let switchWidget = switchWidget.as(AndroidKit.CompoundButton.self)!
        switchWidget.setChecked(state)
    }
}
