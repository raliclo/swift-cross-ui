@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI

// Many force tries are required for the WinUI backend but we don't really want them
// anywhere else so just disable the lint rule at a file level.
// swiftlint:disable force_try

// MARK: TextField

extension WinUIBackend {
    public func createTextField() -> Widget {
        let textField = TextBox()
        textField.textChanged.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            let identifier = ObjectIdentifier(textField)
            let text = textField.text
            guard internalState.textFieldContents[identifier] != text else {
                return
            }
            internalState.textFieldContents[identifier] = text
            internalState.textFieldChangeActions[identifier]?(text)
        }
        textField.keyUp.addHandler { [weak internalState] _, event in
            guard let internalState else { return }

            if event?.key == .enter {
                internalState.textFieldSubmitActions[ObjectIdentifier(textField)]?()
            }
        }
        return textField
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let textField = textField as! TextBox
        textField.placeholderText = placeholder
        internalState.textFieldChangeActions[ObjectIdentifier(textField)] = onChange
        internalState.textFieldSubmitActions[ObjectIdentifier(textField)] = onSubmit
        environment.apply(to: textField)
        apply(environment.backendTextFieldStyle, to: textField)

        updateInputScope(of: textField, textContentType: environment.textContentType)
    }

    /// Gives a `TextBox` one of the four ``BackendTextFieldStyle`` shapes.
    ///
    /// Four properties are not enough on their own, and that is the whole
    /// difficulty here. `borderThickness`, `cornerRadius`, `background` and
    /// `borderBrush` set the *Normal* visual state only: WinUI's `TextBox`
    /// template binds the inner `BorderElement` to them, and then its
    /// `PointerOver` and `Focused` visual states overwrite the brushes with the
    /// `TextControlBackgroundPointerOver` / `TextControlBorderBrushFocused`
    /// theme resources. Set the four properties alone and a `plain` field looks
    /// plain until the pointer touches it, at which point the grey fill and the
    /// accent underline come back.
    ///
    /// So `plain` also overrides those theme resources on the control's own
    /// ``FrameworkElement/resources`` dictionary, which is the narrowest scope
    /// that reaches a template-internal `ThemeResource` lookup. The same
    /// technique is already used for ``TextEditor`` at `WinUIBackend.swift`
    /// around line 1744, whose comment records that the *focused* border brush
    /// was deliberately left alone there; this does not leave it alone, because
    /// "no chrome" that grows an accent underline on focus is not the shape the
    /// application asked for.
    ///
    /// The other three cases `remove` those keys rather than skipping them.
    /// Widgets are reused across updates, so a field that was `plain` a moment
    /// ago still carries the overrides; without the removal, `plain` would be a
    /// one-way door and `.textFieldStyle` would appear to work exactly once.
    /// The same reasoning is why the properties are `clearValue`d rather than
    /// re-set to guessed literals -- `clearValue` hands the property back to
    /// the theme, which is what `automatic` means. That idiom is
    /// `WinUIBackend+Button.swift:202-205`.
    ///
    /// 光靠四個屬性是不夠的，而這正是此處的全部難處。`borderThickness`、`cornerRadius`、
    /// `background` 與 `borderBrush` 只設定了 *Normal* 這個視覺狀態：WinUI 的 `TextBox` template
    /// 把內部的 `BorderElement` 繫結到它們，然後它的 `PointerOver` 與 `Focused` 視覺狀態會用
    /// `TextControlBackgroundPointerOver`／`TextControlBorderBrushFocused` 這些主題資源覆寫掉那些
    /// 筆刷。只設那四個屬性的話，`plain` 欄位會一直看起來很乾淨——直到指標碰到它，灰色填色與強調色
    /// 底線就回來了。
    ///
    /// 因此 `plain` 還會在控制項自身的 ``FrameworkElement/resources`` 字典上覆寫那些主題資源，
    /// 那是能觸及 template 內部 `ThemeResource` 查找的最小範圍。同樣手法已用於 ``TextEditor``
    /// （`WinUIBackend.swift` 約 1744 行），該處註解記載了它刻意不動**聚焦時**的邊框筆刷；此處則
    /// 不放過它，因為「一聚焦就長出強調色底線的無裝飾」並不是應用程式要的外形。
    ///
    /// 另外三個 case 會 `remove` 那些鍵，而不是略過。widget 會跨更新重複使用，因此上一刻還是
    /// `plain` 的欄位仍帶著那些覆寫；少了這步移除，`plain` 就會是一扇單向門，而 `.textFieldStyle`
    /// 看起來會只生效一次。
    func apply(_ style: BackendTextFieldStyle, to textField: WinUI.Control) {
        // `TextControlBorderThemeThickness` is 1,1,1,2 in WinUI's own theme --
        // the thicker bottom edge is the resting underline -- so a border is
        // whatever the theme says, and only the radius is ours to choose.
        // `ControlCornerRadius`, WinUI's default, is 4.
        //
        // `TextControlBorderThemeThickness` 在 WinUI 自身主題中是 1,1,1,2——較厚的下緣就是靜止時
        // 的底線——因此「有邊框」是主題說了算，我們能選的只有圓角半徑。WinUI 的預設值
        // `ControlCornerRadius` 為 4。
        let roundedRadius = 4.0

        switch style {
            case .plain:
                let transparent = SolidColorBrush(UWP.Color.transparent)
                textField.borderThickness = Thickness.null
                textField.cornerRadius = CornerRadius.null
                textField.background = transparent
                textField.borderBrush = transparent
                for key in Self.textControlChromeResourceKeys {
                    _ = textField.resources.insert(key, transparent)
                }
            case .automatic, .roundedBorder, .squareBorder:
                for key in Self.textControlChromeResourceKeys {
                    textField.resources.remove(key)
                }
                _ = try? textField.clearValue(WinUI.Control.borderThicknessProperty)
                _ = try? textField.clearValue(WinUI.Control.backgroundProperty)
                _ = try? textField.clearValue(WinUI.Control.borderBrushProperty)

                switch style {
                    case .roundedBorder:
                        textField.cornerRadius = CornerRadius(
                            topLeft: roundedRadius,
                            topRight: roundedRadius,
                            bottomRight: roundedRadius,
                            bottomLeft: roundedRadius
                        )
                    case .squareBorder:
                        textField.cornerRadius = CornerRadius.null
                    default:
                        _ = try? textField.clearValue(WinUI.Control.cornerRadiusProperty)
                }
        }
    }

    /// The `TextBox` theme resources that draw chrome in a state the four
    /// `Control` properties do not reach.
    ///
    /// Disabled is included even though a disabled field is already dimmed:
    /// `plain` describes the shape, and a shape that returns when the field is
    /// disabled is the `PointerOver` bug again in a state that is harder to
    /// notice.
    ///
    /// 停用狀態也涵蓋在內，儘管停用的欄位本來就會變暗：`plain` 描述的是外形，而一個「在欄位停用時
    /// 又跑回來」的外形，不過是同一個 `PointerOver` 缺陷換到一個更不易察覺的狀態罷了。
    private static let textControlChromeResourceKeys = [
        "TextControlBackground",
        "TextControlBackgroundPointerOver",
        "TextControlBackgroundFocused",
        "TextControlBackgroundDisabled",
        "TextControlBorderBrush",
        "TextControlBorderBrushPointerOver",
        "TextControlBorderBrushFocused",
        "TextControlBorderBrushDisabled",
    ]

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField as! TextBox
        let identifier = ObjectIdentifier(textField)
        internalState.textFieldContents[identifier] = content
        guard textField.text != content else {
            return
        }
        textField.text = content
    }

    public func getContent(ofTextField textField: Widget) -> String {
        (textField as! TextBox).text
    }
}

// MARK: SecureField

extension WinUIBackend {
    public func createSecureField() -> Widget {
        let secureField = PasswordBox()
        secureField.passwordChanged.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            let identifier = ObjectIdentifier(secureField)
            let password = secureField.password
            guard internalState.textFieldContents[identifier] != password else {
                return
            }
            internalState.textFieldContents[identifier] = password
            internalState.textFieldChangeActions[identifier]?(password)
        }
        secureField.keyUp.addHandler { [weak internalState] _, event in
            guard let internalState else { return }

            if event?.key == .enter {
                internalState.textFieldSubmitActions[ObjectIdentifier(secureField)]?()
            }
        }
        return secureField
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let secureField = secureField as! PasswordBox
        secureField.placeholderText = placeholder
        internalState.textFieldChangeActions[ObjectIdentifier(secureField)] = onChange
        internalState.textFieldSubmitActions[ObjectIdentifier(secureField)] = onSubmit
        environment.apply(to: secureField)

        updateInputScope(of: secureField, textContentType: environment.textContentType)
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        let secureField = secureField as! PasswordBox
        let identifier = ObjectIdentifier(secureField)
        internalState.textFieldContents[identifier] = content
        guard secureField.password != content else {
            return
        }
        secureField.password = content
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        (secureField as! PasswordBox).password
    }
}

// MARK: TextBoxProtocol

protocol TextBoxProtocol: Control {
    var inputScope: InputScope! { get set }
}

extension TextBox: TextBoxProtocol {}
extension PasswordBox: TextBoxProtocol {}
