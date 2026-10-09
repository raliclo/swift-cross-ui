import AndroidKit
@_spi(Backends) import SwiftCrossUI

// swiftlint:disable force_try

// implements BackendFeatures.Pickers
extension AndroidBackend {
    public var supportedPickerStyles: [BackendPickerStyle] {
        // `.segmented` from 2026-09-29: `CustomSegmentedGroup`.
        // `.segmented` 自 2026-09-29 起:`CustomSegmentedGroup`。
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
            let action = SwiftAction(environment: Self.env) {
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
            let action = SwiftAction(environment: Self.env) {
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
            let action = SwiftAction(environment: Self.env) {
                let selectedOption = picker.getSelectedItemPosition()
                let invalidPosition: Int32 = try! JavaClass<AndroidKit.AdapterView>()
                    .INVALID_POSITION

                onChange(selectedOption == invalidPosition ? nil : Int(selectedOption))
            }
            // The label colour as UIButtonPicker's: the app's foreground colour,
            // else colorPrimary (UIKit's .link); 30% grey when disabled.
            // 標籤色與 UIButtonPicker 相同:app 的前景色，否則 colorPrimary(UIKit 的 .link);停用時是 30% 的灰。
            var labelEnvironment = environment
            if !environment.isEnabled {
                labelEnvironment = environment.with(
                    \.foregroundColor, environment.suggestedForegroundColor.opacity(0.3)
                )
            } else if environment.foregroundColor == nil, let primary = primaryColor(for: environment) {
                labelEnvironment = environment.with(\.foregroundColor, primary)
            }
            let textStyle = getTextStyle(from: labelEnvironment)
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
            let action = SwiftAction(environment: Self.env) {
                let selectedOption = picker.getValue()
                onChange(selectedOption == 0 ? nil : Int(selectedOption - 1))
            }
            picker.update(action, options, environment.isEnabled)
        } else {
            fatalError("Unexpected picker class")
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
            fatalError("Unexpected picker class")
        }
    }
}
