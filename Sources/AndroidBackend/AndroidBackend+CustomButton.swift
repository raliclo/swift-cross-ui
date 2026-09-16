import AndroidKit
import SwiftCrossUI

// swiftlint:disable force_try
extension AndroidBackend {
    public func createButton(wrapping widget: Widget) -> Widget {
        let button = CustomButton(Self.activity, environment: Self.env)
        let content = widget.as(AndroidKit.View.self)!
        // The button carries the name; its content must not carry it a second
        // time. Without this a screen reader reads every button twice -- once
        // as the `Button` node's contentDescription and once as the `TextView`
        // inside it. Measured with `uiautomator dump --compressed` on 2026-09-16:
        // `desc='Close'` and `text='X'` both present as separate nodes.
        //
        // `NO_HIDE_DESCENDANTS` rather than `NO`, so a label built from several
        // views loses all of them rather than just its outermost one. The same
        // defect and the same shape of fix as `NSCustomButton`'s
        // `setAccessibilityChildren([button])`.
        //
        // 名字由按鈕承載;它的內容不該再承載第二次。少了這一行,螢幕閱讀器會把每一顆按鈕唸兩次——
        // 一次是 `Button` 節點的 contentDescription,一次是它裡面的 `TextView`。2026-09-16 以
        // `uiautomator dump --compressed` 量到:`desc='Close'` 與 `text='X'` 是兩個各自存在的節點。
        //
        // 用 `NO_HIDE_DESCENDANTS` 而非 `NO`,好讓一個由多個 view 組成的標籤整組消失,而不是只掉最
        // 外層那一個。與 `NSCustomButton` 的 `setAccessibilityChildren([button])` 是同一個缺陷、
        // 同一種形狀的修法。
        content.setImportantForAccessibility(4)
        button.addView(content, 0)
        return button.as(AndroidKit.View.self)!
    }

    public func updateButton(
        _ button: Widget,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button.as(CustomButton.self)!
        button.set(
            action: SwiftAction(environment: Self.env, action: action),
            buttonStyle: environment.resolvedButtonStyle.kotlinRepresentation,
            isEnabled: environment.isEnabled,
            isDarkMode: environment.colorScheme == .dark
        )
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        let buttonClass = try! JavaClass<CustomButton>()
        return switch environment.resolvedButtonStyle.kind {
            case .bordered:
                SIMD2(
                    Int(buttonClass.horizontalPadding) * 2,
                    Int(buttonClass.verticalPadding) * 2
                )
            case .plain, .borderless: SIMD2(0, 0)
        }
    }

    public func defaultButtonStyle() -> PrimitiveButtonStyle {
        .bordered
    }
}

extension PrimitiveButtonStyle {
    var kotlinRepresentation: Int16 {
        let buttonClass = try! JavaClass<CustomButton>()
        return switch self.kind {
            case .bordered: buttonClass.borderedButtonStyle
            case .plain: buttonClass.plainButtonStyle
            case .borderless: buttonClass.borderlessButtonStyle
        }
    }
}
