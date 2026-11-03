import AndroidKit
@_spi(Backends) import SwiftCrossUI

// swiftlint:disable force_try

// implements BackendFeatures.Pickers
extension AndroidBackend {
    public var supportedPickerStyles: [BackendPickerStyle] {
        // `.segmented`: `CustomSegmentedGroup`.
        // `.segmented`:`CustomSegmentedGroup`。
        [.menu, .radioGroup, .wheel, .segmented]
    }

    public func createPicker(style: BackendPickerStyle) -> Widget {
        switch style {
            case .radioGroup:
                return CustomRadioGroup(
                    Self.activity,
                    environment: Self.env
                ).as(AndroidKit.View.self)!
            case .menu:
                return CustomSpinner(
                    Self.activity,
                    environment: Self.env
                ).as(AndroidKit.View.self)!
            case .wheel:
                return CustomNumberPicker(
                    Self.activity,
                    environment: Self.env
                ).as(AndroidKit.View.self)!
            case .segmented:
                // A styled horizontal RadioGroup rather than Material's
                // MaterialButtonToggleGroup, which is a library this backend does
                // not link. 以樣式化的水平 RadioGroup 實作,而非 Material 的
                // MaterialButtonToggleGroup——那是本 backend 沒有連結的函式庫。
                return CustomSegmentedGroup(
                    Self.activity,
                    environment: Self.env
                ).as(AndroidKit.View.self)!
        }
    }

    public func updatePicker(
        _ picker: Widget,
        options: [String],
        environment: EnvironmentValues,
        onChange: @escaping (Int?) -> Void
    ) {
        if let picker = picker.as(CustomRadioGroup.self) {
            // The picker is reached through a Java weak reference, not captured: the
            // picker holds this action, and a captured wrapper is a JNI global
            // reference back to the picker, so neither collector could ever free
            // the pair. See `JavaWeakReference`.
            // picker 經由 Java 弱參照取得，而不是被捕捉:picker 持有這個 action,而被捕捉的包裝物件是指回
            // picker 的 JNI 全域參照，兩邊的回收機制都永遠釋放不了這一對。見 `JavaWeakReference`。
            let weakPicker = JavaWeakReference(picker, environment: Self.env)
            let action = SwiftAction(environment: Self.env) {
                guard let picker = weakPicker.get()?.as(CustomRadioGroup.self) else { return }
                let selectedOption = picker.getSelectedOption()
                onChange(selectedOption < 0 ? nil : Int(selectedOption))
            }
            let textStyle = getTextStyle(from: environment)
            picker.update(
                action,
                options,
                environment.isEnabled,
                color: textStyle.color,
                fontSize: textStyle.fontSize,
                lineHeight: textStyle.lineHeightPixels,
                textStyle.typeface
            )
        } else if let picker = picker.as(CustomSegmentedGroup.self) {
            let weakPicker = JavaWeakReference(picker, environment: Self.env)
            let action = SwiftAction(environment: Self.env) {
                guard let picker = weakPicker.get()?.as(CustomSegmentedGroup.self) else { return }
                let selectedOption = picker.getSelectedOption()
                onChange(selectedOption < 0 ? nil : Int(selectedOption))
            }
            let textStyle = getTextStyle(from: environment)
            picker.update(
                action,
                options,
                environment.isEnabled,
                color: textStyle.color,
                fontSize: textStyle.fontSize,
                lineHeight: textStyle.lineHeightPixels,
                textStyle.typeface
            )
        } else if let picker = picker.as(CustomSpinner.self) {
            let weakPicker = JavaWeakReference(picker, environment: Self.env)
            let action = SwiftAction(environment: Self.env) {
                guard let picker = weakPicker.get()?.as(CustomSpinner.self) else { return }
                let selectedOption = picker.getSelectedItemPosition()
                let invalidPosition: Int32 = try! JavaClass<AndroidKit.AdapterView>()
                    .INVALID_POSITION

                onChange(selectedOption == invalidPosition ? nil : Int(selectedOption))
            }
            // The label colour as UIButtonPicker's; see tintedLabelEnvironment.
            // 標籤色與 UIButtonPicker 相同;見 tintedLabelEnvironment。
            let textStyle = getTextStyle(from: tintedLabelEnvironment(environment))
            picker.update(
                action,
                options,
                environment.isEnabled,
                color: textStyle.color,
                fontSize: textStyle.fontSize,
                lineHeight: textStyle.lineHeightPixels,
                textStyle.typeface
            )
        } else if let picker = picker.as(CustomNumberPicker.self) {
            let weakPicker = JavaWeakReference(picker, environment: Self.env)
            let action = SwiftAction(environment: Self.env) {
                guard let picker = weakPicker.get()?.as(CustomNumberPicker.self) else { return }
                let selectedOption = picker.getValue()
                onChange(selectedOption == 0 ? nil : Int(selectedOption - 1))
            }
            picker.update(action, options, environment.isEnabled)
        } else {
            // Logged, not fatal: one widget this backend did not create must not take
            // the whole app down. The picker keeps the options it last showed.
            // 記錄而非中止:一個不是本 backend 建立的 widget,不該拖垮整個 app。picker 保留它上次顯示的選項。
            log("picker: updatePicker on an unexpected widget \(picker.toString()); options not updated")
        }
    }

    public func setSelectedOption(ofPicker picker: Widget, to selectedOption: Int?) {
        if let picker = picker.as(CustomRadioGroup.self) {
            picker.selectOption(Int32(selectedOption ?? -1))
        } else if let picker = picker.as(CustomSegmentedGroup.self) {
            picker.selectOption(Int32(selectedOption ?? -1))
        } else if let picker = picker.as(CustomSpinner.self) {
            if let selectedOption {
                picker.selectOption(Int32(selectedOption))
            } else {
                let invalidPosition: Int32 = try! JavaClass<AndroidKit.AdapterView>()
                    .INVALID_POSITION

                picker.selectOption(invalidPosition)
            }
        } else if let picker = picker.as(AndroidKit.NumberPicker.self) {
            if let selectedOption {
                picker.setValue(Int32(selectedOption + 1))
            } else {
                picker.setValue(0)
            }
        } else {
            // Logged, not fatal: one widget this backend did not create must not take
            // the whole app down. The selection is left as it is.
            // 記錄而非中止:一個不是本 backend 建立的 widget,不該拖垮整個 app。選取狀態維持原樣。
            log("picker: setSelectedOption on an unexpected widget \(picker.toString()); left as it is")
        }
    }
}
