import AndroidKit
@_spi(Backends) import SwiftCrossUI

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

    /// The theme's `colorError`, the colour Material gives a destructive
    /// action. Asked only for a destructive button whose app named no colour.
    /// 主題的 `colorError`,Material 給危險動作的顏色。只有在危險按鈕且 app 沒有指定顏色時才會被問到。
    public func destructiveButtonLabelColor(
        in environment: EnvironmentValues
    ) -> SwiftCrossUI.Color? {
        let colorInt = helpers.getErrorColor(Self.activity)
        guard colorInt != 0 else {
            logger.warning(
                "the theme defines no colorError; a destructive button keeps its usual label colour"
            )
            return nil
        }
        return SwiftCrossUI.Color(SwiftCrossUI.Color.Resolved(fromColorInt: colorInt))
    }

    public func updateButton(
        _ button: Widget,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let buttonStyle = environment.resolvedButtonStyle.kotlinRepresentation
        let isEnabled = environment.isEnabled
        let isDarkMode = environment.colorScheme == .dark

        // The click action lives in a Swift box the Java `SwiftAction` calls through, so a
        // new closure is one assignment here and not two new Java objects. Every update
        // used to build a `SwiftAction` and a `SwiftObject`, and swift-java looks each
        // class up through the app's class loader on every construction: 25.5 ms of a
        // 104 ms update in P2 on Android (simpleperf, 2026-10-05). `CustomButton.set` is
        // called only when the style, enabled state or colour scheme actually changes.
        //
        // 點擊動作放在一個 Swift 盒子裡，由 Java 的 `SwiftAction` 轉呼叫，因此換一個新的 closure 在這裡只是一次
        // 指派，而不是兩個新的 Java 物件。原本每次更新都建立一個 `SwiftAction` 與一個 `SwiftObject`,而
        // swift-java 每次建構都要經由 app 的 class loader 查找類別：在 Android 上 P2 一次 104 ms 的更新中佔了
        // 25.5 ms(simpleperf,2026-10-05)。只有在樣式、啟用狀態或配色真的改變時才呼叫 `CustomButton.set`。
        if var state = Self.buttonStates.value(for: button) {
            state.box.action = action
            guard
                state.buttonStyle != buttonStyle
                    || state.isEnabled != isEnabled
                    || state.isDarkMode != isDarkMode
            else { return }
            state.buttonStyle = buttonStyle
            state.isEnabled = isEnabled
            state.isDarkMode = isDarkMode
            Self.buttonStates.set(state, for: button)
            button.as(CustomButton.self)!.set(
                action: state.javaAction,
                buttonStyle: buttonStyle,
                isEnabled: isEnabled,
                isDarkMode: isDarkMode
            )
            return
        }

        let box = ButtonActionBox(action)
        let javaAction = SwiftAction(environment: Self.env, action: { box.action() })
        Self.buttonStates.set(
            ButtonSetState(
                box: box,
                javaAction: javaAction,
                buttonStyle: buttonStyle,
                isEnabled: isEnabled,
                isDarkMode: isDarkMode
            ),
            for: button
        )
        button.as(CustomButton.self)!.set(
            action: javaAction,
            buttonStyle: buttonStyle,
            isEnabled: isEnabled,
            isDarkMode: isDarkMode
        )
    }

    public func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        return switch environment.resolvedButtonStyle.kind {
            case .bordered:
                SIMD2(
                    Int(CustomButtonConstants.horizontalPadding) * 2,
                    Int(CustomButtonConstants.verticalPadding) * 2
                )
            case .plain, .borderless: SIMD2(0, 0)
        }
    }

    /// The label environment for a button, matching UIKit on a phone: a
    /// borderless label is drawn in the platform's tint -- the theme's
    /// colorPrimary here, as a Material text button is -- unless the app named
    /// a colour, and a disabled one is a 30% grey. A bordered button keeps the
    /// theme's button text.
    /// 按鈕的標籤環境，與手機上的 UIKit 一致：無框標籤用平台的強調色(此處是主題的 colorPrimary,如 Material 文字按鈕),
    /// 除非 app 指定了顏色;停用時是 30% 的灰。有框按鈕維持主題的按鈕文字。
    public func computeButtonLabelEnvironment(
        from environment: EnvironmentValues
    ) -> EnvironmentValues {
        guard environment.resolvedButtonStyle.kind == .borderless else { return environment }
        if !environment.isEnabled {
            return environment.with(
                \.foregroundColor,
                environment.suggestedForegroundColor.opacity(0.3)
            )
        }
        guard environment.foregroundColor == nil, let primary = primaryColor(for: environment)
        else { return environment }
        return environment.with(\.foregroundColor, primary)
    }

    /// colorPrimary, read once per colour scheme rather than on every layout.
    /// colorPrimary,每種配色只讀一次，而不是每次排版都讀。
    func primaryColor(for environment: EnvironmentValues) -> SwiftCrossUI.Color? {
        let key = environment.colorScheme == .dark
        if let cached = Self.primaryColors[key] { return cached }
        let colorInt = helpers.getPrimaryColor(Self.activity)
        let color =
            colorInt == 0
            ? nil : SwiftCrossUI.Color(SwiftCrossUI.Color.Resolved(fromColorInt: colorInt))
        Self.primaryColors[key] = color
        return color
    }

    @MainActor static var primaryColors: [Bool: SwiftCrossUI.Color?] = [:]

    public func defaultButtonStyle() -> PrimitiveButtonStyle {
        // Borderless, as UIKit's default on a phone (user, 2026-10-09: Android
        // should line up with iOS). A Material bordered button's padding made
        // every row of buttons wider and taller than on iOS -- P4's top row
        // wrapped "Fe/wer rows" and showed 7 callback rows to iOS's 9.
        // 無框，與手機上 UIKit 的預設相同(使用者,2026-10-09:Android 要與 iOS 對齊)。Material 有框按鈕的內距讓每一排
        // 按鈕都比 iOS 寬且高——P4 頂端那排斷成「Fe/wer rows」,只顯示 7 列 callback,iOS 是 9 列。
        .borderless
    }

    /// Each button's action box and what `CustomButton.set` was last given; see `LastSet`.
    /// 每顆按鈕的動作盒子，以及上一次交給 `CustomButton.set` 的值；見 `LastSet`。
    @MainActor static let buttonStates = LastSet<ButtonSetState>()
}

/// The closure a button's Java `SwiftAction` runs, swapped in place on each update.
/// 按鈕的 Java `SwiftAction` 所執行的 closure,每次更新時就地替換。
final class ButtonActionBox {
    var action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

struct ButtonSetState {
    let box: ButtonActionBox
    let javaAction: SwiftAction
    var buttonStyle: Int16
    var isEnabled: Bool
    var isDarkMode: Bool
}

/// `CustomButton`'s companion constants, read once. They are Kotlin `const val`s, so they
/// cannot change while the process runs, and each read through `JavaClass<CustomButton>()`
/// used to cost a class lookup.
/// `CustomButton` companion 的常數，只讀一次。它們是 Kotlin 的 `const val`,在程序執行期間不可能改變，
/// 而原本每次經由 `JavaClass<CustomButton>()` 讀取都要花一次類別查找。
@MainActor
enum CustomButtonConstants {
    static let horizontalPadding: Int32 = try! JavaClass<CustomButton>().horizontalPadding
    static let verticalPadding: Int32 = try! JavaClass<CustomButton>().verticalPadding
    static let borderedButtonStyle: Int16 = try! JavaClass<CustomButton>().borderedButtonStyle
    static let plainButtonStyle: Int16 = try! JavaClass<CustomButton>().plainButtonStyle
    static let borderlessButtonStyle: Int16 = try! JavaClass<CustomButton>().borderlessButtonStyle
}

extension PrimitiveButtonStyle {
    @MainActor
    var kotlinRepresentation: Int16 {
        return switch self.kind {
            case .bordered: CustomButtonConstants.borderedButtonStyle
            case .plain: CustomButtonConstants.plainButtonStyle
            case .borderless: CustomButtonConstants.borderlessButtonStyle
        }
    }
}
