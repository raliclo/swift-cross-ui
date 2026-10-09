import AndroidKit
@_spi(Backends) import SwiftCrossUI

// implements BackendFeatures.ToggleButtons & BackendFeatures.Checkboxes & BackendFeatures.Switches
extension AndroidBackend {
    // A spacer between the label and the switch, as UIKitBackend asks: the
    // switch sits at the trailing edge of its row, where both iOS and Android
    // settings rows put it. Without it P12's "Switch" row was label-plus-switch
    // wide on Android, so its whole section centred instead of starting at the
    // leading edge as on iOS (2026-10-09).
    // 標籤與開關之間放一個 Spacer,與 UIKitBackend 相同：開關位於該列的結尾端，iOS 與 Android 的設定列都這樣放。少了它，
    // P12 的「Switch」那一列在 Android 上只有標籤加開關那麼寬，整個區塊因而置中，而不是像 iOS 那樣從起始端開始(2026-10-09)。
    public var requiresToggleSwitchSpacer: Bool { true }

    public func createToggle() -> Widget {
        let toggle = AndroidKit.ToggleButton(
            Self.activity,
            environment: Self.env
        )
        helpers.styleToggleButton(toggle)
        return toggle
    }

    public func createCheckbox() -> Widget {
        let checkbox = AndroidKit.CheckBox(
            Self.activity,
            environment: Self.env
        )
        // Shaped at creation, so the first measurement is the 30 pt square.
        // 建立時就定形，讓第一次量測就是 30 pt 的方塊。
        helpers.styleCheckbox(checkbox.as(AndroidKit.CompoundButton.self), Int32(bitPattern: 0xFF00_0000), true)
        return checkbox
    }

    public func createSwitch() -> Widget {
        let switchWidget = AndroidKit.Switch(
            Self.activity,
            environment: Self.env
        )
        // Shaped at creation, so the first measurement already has the pill's
        // size; styled only in update, a checked switch was measured with the
        // framework drawables and its thumb came out clipped (P15, 2026-10-09).
        // 建立時就套上形狀，讓第一次量測就是膠囊的尺寸;只在 update 時套用，開啟的開關是以框架的圖量測的，滑塊被裁掉了(P15)。
        helpers.styleSwitch(switchWidget.as(AndroidKit.CompoundButton.self), Int32(bitPattern: 0xFF00_0000), true)
        return switchWidget
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
        // The shown text too: setTextOn/Off take effect only at the next state
        // change, so the toggle was measured with its default "OFF" and drew
        // "Tog" once Material's 88 dp minimum width stopped hiding it (P12).
        // 也設定目前顯示的文字:setTextOn/Off 要到下一次狀態改變才生效，所以開關是以預設的「OFF」量測的，一旦 Material 的
        // 88 dp 最小寬度不再遮掩，就只畫出「Tog」(P12)。
        toggle.setText(charSequence)

        getTextStyle(from: environment).apply(to: toggle)
        // `apply` sets one solid colour, which replaces the theme's state list
        // and with it the faded disabled text: P2's `.disabled(true)` toggle
        // read exactly like an enabled one. Material's disabled text is 38%.
        // `apply` 設的是單一固定顏色，蓋掉了主題的狀態色表，連帶蓋掉停用時的淡化文字:P2 的 `.disabled(true)`
        // 開關看起來和啟用的完全一樣。Material 的停用文字是 38%。
        // White on the filled (checked) state, the tint otherwise, 38% when
        // disabled -- see AndroidBackendHelpers.applyToggleButtonTextColors.
        // 開(填滿)時白色，其他時候強調色，停用時 38%——見 AndroidBackendHelpers.applyToggleButtonTextColors。
        helpers.applyToggleButtonTextColors(toggle, environment.isEnabled)
    }

    public func updateCheckbox(
        _ checkboxWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let checkboxWidget = checkboxWidget.as(AndroidKit.CompoundButton.self)!
        updateCompoundButton(checkboxWidget, environment: environment, onChange: onChange)
        helpers.styleCheckbox(
            checkboxWidget,
            environment.suggestedForegroundColor.resolve(in: environment).asColorInt(),
            environment.isEnabled
        )
    }

    public func updateSwitch(
        _ switchWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let switchWidget = switchWidget.as(AndroidKit.CompoundButton.self)!
        updateCompoundButton(switchWidget, environment: environment, onChange: onChange)
        helpers.styleSwitch(
            switchWidget,
            environment.suggestedForegroundColor.resolve(in: environment).asColorInt(),
            environment.isEnabled
        )
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
