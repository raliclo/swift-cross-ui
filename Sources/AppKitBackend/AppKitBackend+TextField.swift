import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    // MARK: TextField

    public func createTextField() -> Widget {
        // Using the `(string:)` initializer ensures that the TextField scrolls
        // smoothly on horizontal overflow instead of jumping a full width at a
        // time.
        NSObservableTextField(string: "")
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let textField = textField as! NSObservableTextField
        textField.isEnabled = environment.isEnabled
        textField.placeholderString = placeholder
        textField.appearance = environment.colorScheme.nsAppearance
        let resolvedFont = environment.resolvedFont
        if textField.font != Self.font(for: resolvedFont) {
            textField.font = Self.font(for: resolvedFont)
        }

        textField.onEdit = { textField in
            onChange(textField.stringValue)
        }
        textField.onSubmit = onSubmit

        Self.apply(environment.backendTextFieldStyle, to: textField)

        if #available(macOS 14, *) {
            textField.contentType =
                switch environment.textContentType {
                    case .url:
                        .URL
                    case .phoneNumber:
                        .telephoneNumber
                    case .name:
                        .name
                    case .emailAddress:
                        .emailAddress
                    case .text, .digits(_), .decimal(_):
                        nil
                }
        }
    }

    /// Gives an `NSTextField` one of the four ``BackendTextFieldStyle`` shapes.
    ///
    /// AppKit is the one backend where all four shapes are first-class and
    /// named: `NSTextField.bezelStyle` is an enum whose two cases are
    /// `.roundedBezel` and `.squareBezel`, which is where SwiftUI's
    /// `roundedBorder` and macOS-only `squareBorder` come from in the first
    /// place. Nothing has to be synthesised out of a border width and a corner
    /// radius here, unlike on the other four backends.
    ///
    /// `automatic` restores `NSTextField`'s documented defaults -- bezeled,
    /// square, drawing its background -- rather than returning early. Widgets
    /// are reused across updates, so a field that was `plain` on the previous
    /// commit still has `isBezeled == false`; skipping would make `plain` a
    /// one-way door. This is the same reason `GtkBackend` re-sets `has-frame`
    /// and `WinUIBackend` removes its resource overrides.
    ///
    /// **`isBordered` and `isBezeled` are not independent**, which is why
    /// `plain` clears both. AppKit treats them as two ways of asking for a
    /// frame -- a bordered, unbezeled `NSTextField` draws a thin line rectangle
    /// -- so clearing only `isBezeled` would swap one border for another rather
    /// than removing it. Setting `bezelStyle` implicitly sets `isBezeled`, so
    /// the two bordered cases set the style and let that follow.
    ///
    /// The focus ring is deliberately left alone in every case. It is not
    /// chrome in the sense `plain` is about; it is how a keyboard user knows
    /// where they are, and `focusRingType = .none` would take that away in
    /// exchange for a slightly cleaner still image.
    ///
    /// - Note: Unrun. This backend cannot be built or executed on the Windows
    ///   machine this was written on, so it is implemented by reading AppKit's
    ///   interface rather than by observing it.
    ///
    /// AppKit 是唯一四種外形都是一等公民且各有其名的 backend：`NSTextField.bezelStyle` 是一個 enum，
    /// 其兩個 case 正是 `.roundedBezel` 與 `.squareBezel`——SwiftUI 的 `roundedBorder` 與僅限 macOS 的
    /// `squareBorder` 本來就是從這裡來的。此處不必像其餘四個 backend 那樣，用邊框寬度加圓角半徑去
    /// 合成任何東西。
    ///
    /// `automatic` 會還原 `NSTextField` 有文件記載的預設值——有 bezel、方角、繪製自身背景——而不是
    /// 提早返回。widget 會跨更新重複使用，因此在上一次 commit 中還是 `plain` 的欄位，其
    /// `isBezeled` 仍為 `false`；若略過，`plain` 就會成為一扇單向門。這與 `GtkBackend` 重設
    /// `has-frame`、`WinUIBackend` 移除其資源覆寫，是同一個理由。
    ///
    /// **`isBordered` 與 `isBezeled` 並非彼此獨立**，這正是 `plain` 兩者都要清除的原因。AppKit 把
    /// 它們視為「要求一個外框」的兩種說法——一個有 border、無 bezel 的 `NSTextField` 會畫出一個細線
    /// 矩形——因此只清除 `isBezeled` 會是把一種邊框換成另一種，而不是把邊框拿掉。
    ///
    /// 焦點環在所有情況下都刻意不動。它不屬於 `plain` 所要處理的那種外框裝飾；它是鍵盤使用者賴以
    /// 知道自己身在何處的東西，而 `focusRingType = .none` 是拿它去換一張略為乾淨的靜態畫面。
    ///
    /// - Note: 未實際執行。撰寫本程式碼的 Windows 機器無法建置或執行此 backend，因此它是靠閱讀
    ///   AppKit 的介面實作的，而非靠觀察其行為。
    static func apply(_ style: BackendTextFieldStyle, to textField: NSTextField) {
        switch style {
            case .automatic, .squareBorder:
                // One arm, not two, because `NSTextField`'s default *is*
                // `.squareBezel` -- see `BackendTextFieldStyle.automatic`,
                // which documents macOS as the platform where `automatic` and
                // `squareBorder` coincide. Splitting them would be two
                // identical bodies asserting they might differ.
                //
                // 合為一個分支而非兩個，因為 `NSTextField` 的預設值**就是** `.squareBezel`——見
                // `BackendTextFieldStyle.automatic`，其中記載 macOS 正是 `automatic` 與
                // `squareBorder` 重合的平台。拆成兩個，等於用兩份完全相同的內容去主張它們可能不同。
                textField.isBezeled = true
                textField.bezelStyle = .squareBezel
                textField.drawsBackground = true
            case .plain:
                textField.isBezeled = false
                textField.isBordered = false
                textField.drawsBackground = false
            case .roundedBorder:
                textField.isBezeled = true
                textField.bezelStyle = .roundedBezel
                textField.drawsBackground = true
        }
    }

    public func getContent(ofTextField textField: Widget) -> String {
        let textField = textField as! NSTextField
        return textField.stringValue
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField as! NSTextField
        textField.stringValue = content
    }

    // MARK: SecureField

    public func createSecureField() -> Widget {
        // Using the `(string:)` initializer ensures that the SecureField scrolls
        // smoothly on horizontal overflow instead of jumping a full width at a
        // time.
        NSObservableSecureTextField(string: "")
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let secureField = secureField as! NSObservableSecureTextField
        secureField.isEnabled = environment.isEnabled
        secureField.placeholderString = placeholder
        secureField.appearance = environment.colorScheme.nsAppearance
        let resolvedFont = environment.resolvedFont
        if secureField.font != Self.font(for: resolvedFont) {
            secureField.font = Self.font(for: resolvedFont)
        }

        secureField.onEdit = { _ in
            onChange(secureField.stringValue)
        }
        secureField.onSubmit = onSubmit

        if #available(macOS 14, *) {
            secureField.contentType =
                switch environment.textContentType {
                    case .url:
                        .URL
                    case .phoneNumber:
                        .telephoneNumber
                    case .name:
                        .name
                    case .emailAddress:
                        .emailAddress
                    case .text, .digits(_), .decimal(_):
                        nil
                }
        }
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        let secureField = secureField as! NSTextField
        return secureField.stringValue
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        let secureField = secureField as! NSTextField
        secureField.stringValue = content
    }

    // MARK: TextEditor

    public func createTextEditor() -> Widget {
        let textEditor = NSObservableTextView()
        textEditor.drawsBackground = false
        textEditor.delegate = textEditor
        textEditor.allowsUndo = true
        textEditor.isRichText = false
        textEditor.textContainerInset = .zero
        textEditor.textContainer?.lineFragmentPadding = 0
        return textEditor
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = textEditor as! NSObservableTextView
        textEditor.onEdit = { textView in
            onChange(self.getContent(ofTextEditor: textView))
        }
        let resolvedFont = environment.resolvedFont
        if textEditor.font != Self.font(for: resolvedFont) {
            textEditor.font = Self.font(for: resolvedFont)
        }
        textEditor.appearance = environment.colorScheme.nsAppearance
        textEditor.isEditable = environment.isEnabled

        if #available(macOS 14, *) {
            textEditor.contentType =
                switch environment.textContentType {
                    case .url:
                        .URL
                    case .phoneNumber:
                        .telephoneNumber
                    case .name:
                        .name
                    case .emailAddress:
                        .emailAddress
                    case .text, .digits(_), .decimal(_):
                        nil
                }
        }
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        (textEditor as! NSObservableTextView).string = content
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        (textEditor as! NSObservableTextView).string
    }
}

// MARK: Custom views

private class NSObservableTextField: NSTextField {
    override func textDidChange(_ notification: Notification) {
        onEdit?(self)
    }

    var onEdit: ((NSTextField) -> Void)?
    var _onSubmitAction = Action({})
    var onSubmit: () -> Void {
        get {
            _onSubmitAction.action
        }
        set {
            _onSubmitAction.action = newValue
            action = #selector(_onSubmitAction.run)
            target = _onSubmitAction
        }
    }
}

private class NSObservableSecureTextField: NSSecureTextField {
    override func textDidChange(_ notification: Notification) {
        onEdit?(self)
    }

    var onEdit: ((NSSecureTextField) -> Void)?
    var _onSubmitAction = Action({})
    var onSubmit: () -> Void {
        get {
            _onSubmitAction.action
        }
        set {
            _onSubmitAction.action = newValue
            action = #selector(_onSubmitAction.run)
            target = _onSubmitAction
        }
    }
}

class NSObservableTextView: NSTextView, NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onEdit?(self)
    }

    var onEdit: ((NSTextView) -> Void)?
}
