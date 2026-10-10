import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

// implements BackendFeatures.TextFields & BackendFeatures.SecureFields & BackendFeatures.TextEditors
extension AndroidBackend {
    public func createTextField() -> Widget {
        let field = CustomEditText(activity: Self.activity, environment: Self.env)
        Self.makePlain(field)
        return field
    }

    /// `.automatic`/`.plain` from the start: no background, no inset, no
    /// minimum height. The core measures a field (`computeLayout`) before it
    /// applies the style (`commit`), so a field created with the theme's
    /// underline was laid out 45 dp tall and kept that height after the style
    /// removed it: P31 showed a strip of empty field under the text (2026-10-10).
    /// 一開始就是 `.automatic`/`.plain`:沒有背景、沒有內縮、沒有最小高度。核心在套用樣式(`commit`)之前就量測
    /// 欄位(`computeLayout`),所以帶著主題底線建立的欄位被排成 45 dp 高，樣式拿掉底線之後仍維持那個高度:P31 的文字
    /// 底下留著一段空白欄位(2026-10-10)。
    static func makePlain(_ field: CustomEditText) {
        field.setBackground(nil)
        field.setPadding(0, 0, 0, 0)
        field.setMinHeight(0)
        field.setMinimumHeight(0)
    }

    private func updateTextField(
        _ textField: CustomEditText,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: (() -> Void)?,
        isMultiline: Bool
    ) {
        textField.setHint(Self.charSequence(from: placeholder))
        textField.setOnChange(
            SwiftAction(environment: Self.env) {
                // Don't take textField as a weak reference, because otherwise it
                // gets dropped immediately (it's not actually held anywhere; it's
                // just a wrapper around a Java class instance). This doesn't cause
                // a reference cycle because textField doesn't hold the SwiftAction,
                // (Java does).
                let content = textField.getText().toString()
                onChange(content)
            }
        )
        textField.setEnabled(environment.isEnabled)
        textField.setMaxLines(isMultiline ? .max : 1)

        let expectedInputType = environment.textContentType.toInputType(isMultiline: isMultiline)
        if textField.getInputType() != expectedInputType {
            textField.setInputType(expectedInputType)
        }

        if let onSubmit {
            textField.setOnSubmit(SwiftAction(environment: Self.env, action: onSubmit))
        } else {
            textField.setOnSubmit(nil)
        }
        // Disabled, the text in the default colour at 30% unless the app chose
        // one, as UIKitBackend's resolvedForegroundColor colours a text field and
        // a text editor: P29's disabled editor read black on Android, grey on
        // iOS (2026-10-10).
        // 停用時，除非 app 選了顏色，文字用預設顏色的 30%,與 UIKitBackend 的 resolvedForegroundColor 為文字欄位
        // 與文字編輯器上色的方式相同:P29 停用的編輯器在 Android 上是黑字，在 iOS 上是灰字(2026-10-10)。
        let textEnvironment =
            environment.isEnabled || environment.foregroundColor != nil
            ? environment
            : environment.with(\.foregroundColor, environment.suggestedForegroundColor.opacity(0.3))
        getTextStyle(from: textEnvironment).apply(to: textField)
        // The placeholder in the current foreground at 30%, as UIKit's
        // placeholderText follows the window's scheme. The theme's hint colour
        // stayed light-theme grey under preferredColorScheme(.dark) and nearly
        // vanished on black (P15-DARK, 2026-10-09).
        // 佔位文字用目前前景色的 30%,如同 UIKit 的 placeholderText 跟著視窗的配色。主題的 hint 顏色在
        // preferredColorScheme(.dark) 下仍是淺色主題的灰，在黑底上幾乎看不見(P15-DARK,2026-10-09)。
        let foreground = environment.suggestedForegroundColor.resolve(in: environment).asColorInt()
        textField.setHintTextColor((foreground & 0x00FF_FFFF) | 0x4D00_0000)
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let editText = textField.as(CustomEditText.self)!
        updateTextField(
            editText,
            placeholder: placeholder,
            environment: environment,
            onChange: onChange,
            onSubmit: onSubmit,
            isMultiline: false
        )
        // Applied in this overload and not in the private one above, which is
        // the shared body. `updateTextEditor` also calls that body, and
        // `createTextEditor` deliberately strips the EditText's background and
        // padding to zero; applying a text *field* style there would restore
        // the chrome a text editor just took off, on every update.
        //
        // `updateSecureField` does route through here, so a secure field runs
        // this too -- always with `.automatic`, because `SecureField` does not
        // set `backendTextFieldStyle`. That costs one `restoreDefaultChrome()`
        // per update and changes nothing, which is the correct behaviour for a
        // control this task did not extend.
        //
        // 在此 overload 中套用，而非在上方那個私有的共用實作中。`updateTextEditor` 同樣會呼叫該共用
        // 實作，而 `createTextEditor` 是刻意把 EditText 的背景與 padding 歸零的；若在那裡套用文字
        // **輸入框**的樣式，等於每次更新都把文字編輯器剛拿掉的外框裝飾又裝回去。
        //
        // `updateSecureField` 確實會經過這裡，因此安全欄位也會執行到——且永遠是 `.automatic`，
        // 因為 `SecureField` 不會設定 `backendTextFieldStyle`。其代價是每次更新多一次
        // `restoreDefaultChrome()`，且不改變任何東西；對一個本次工作未擴充的控制項而言，這正是
        // 正確的行為。
        apply(environment.backendTextFieldStyle, to: editText, in: environment)
    }

    /// Gives a `CustomEditText` one of the four ``BackendTextFieldStyle``
    /// shapes.
    ///
    /// Android is the only one of the five with no border property at all.
    /// `EditText` has no `hasFrame` (Gtk), no `borderThickness` (WinUI), no
    /// `bezelStyle` (AppKit) and no `borderStyle` (UIKit) -- a `View`'s frame
    /// *is* its background `Drawable`, and the platform look is a drawable the
    /// theme supplies. So the bordered shapes are built rather than selected,
    /// with `GradientDrawable`, which is exactly what this backend's own
    /// `CustomButton.kt` does for a bordered button (`borderedBackground`,
    /// around line 66).
    ///
    /// Two things follow from the background *being* the border, and both are
    /// easy to get wrong:
    ///
    /// - **Padding travels with it.** A background `Drawable` supplies a
    ///   `View`'s padding on Android, so swapping the background silently
    ///   changes the text inset. Every arm here sets padding explicitly; the
    ///   `automatic` arm restores the saved pair together, which is why
    ///   `restoreDefaultChrome()` exists on the Kotlin side rather than a bare
    ///   background getter.
    /// - **Everything is in pixels.** `GradientDrawable` takes device pixels,
    ///   not dp, so a 1dp stroke on a 3x screen must be passed as 3. The
    ///   density comes from the display metrics, the same conversion
    ///   `AndroidBackend+CornerRadius.swift` does around line 27.
    ///
    /// The stroke colour is derived from the environment's foreground colour at
    /// a quarter opacity rather than being a fixed grey, so it follows dark
    /// mode and any `foregroundColor(_:)` in scope. `CustomButton.kt` uses a
    /// hard-coded adaptive grey for its button, which only handles the first of
    /// those two.
    ///
    /// - Note: Unrun. This backend cannot be built or executed on the Windows
    ///   machine this was written on, so it is implemented against the AndroidKit
    ///   bindings' declared interface rather than by observing it.
    ///
    /// Android 是五者中唯一完全沒有邊框屬性的。`EditText` 沒有 `hasFrame`（Gtk）、沒有
    /// `borderThickness`（WinUI）、沒有 `bezelStyle`（AppKit），也沒有 `borderStyle`（UIKit）
    /// ——一個 `View` 的外框**就是**它的背景 `Drawable`，而平台外觀則是主題提供的一個 drawable。
    /// 因此帶邊框的外形是被「建造」而非「挑選」出來的，使用 `GradientDrawable`；本 backend 自己的
    /// `CustomButton.kt` 為帶邊框按鈕所做的正是同一件事（`borderedBackground`，約第 66 行）。
    ///
    /// 「背景即邊框」帶來兩項後果，而兩者都很容易弄錯：
    ///
    /// - **padding 會跟著一起走。** 在 Android 上，背景 `Drawable` 會提供 `View` 的 padding，因此
    ///   替換背景也會悄悄改變文字的內縮。此處每一個分支都明確設定 padding；`automatic` 分支則把
    ///   存下的那一對一併還原，這正是 Kotlin 端存在 `restoreDefaultChrome()`、而不是一個單純
    ///   background getter 的原因。
    /// - **一切都以像素計。** `GradientDrawable` 收的是裝置像素而非 dp，因此 1dp 的描邊在 3 倍螢幕
    ///   上必須以 3 傳入。density 取自 display metrics，與
    ///   `AndroidBackend+CornerRadius.swift` 約第 27 行所做的換算相同。
    ///
    /// 描邊顏色由 environment 的前景色以四分之一不透明度導出，而非固定的灰色，如此便能跟隨深色模式
    /// 以及作用範圍內任何的 `foregroundColor(_:)`。`CustomButton.kt` 為其按鈕使用的是寫死的自適應
    /// 灰，那只處理了上述兩者中的第一項。
    ///
    /// - Note: 未實際執行。撰寫本程式碼的 Windows 機器無法建置或執行此 backend，因此它是依據
    ///   AndroidKit 綁定所宣告的介面實作的，而非靠觀察其行為。
    private func apply(
        _ style: BackendTextFieldStyle,
        to textField: CustomEditText,
        in environment: EnvironmentValues
    ) {
        switch style {
            // `.automatic` as `.plain`, as UIKitBackend maps both to
            // `UITextField.BorderStyle.none`: an unstyled field on iOS has no
            // border, and Android's theme underline with its inset put P31's
            // field 4 dp right of iOS's and pushed the rows below it down
            // (2026-10-10).
            // `.automatic` 與 `.plain` 相同，如同 UIKitBackend 把兩者都對應到 `UITextField.BorderStyle.none`:
            // iOS 上未加樣式的欄位沒有框線，而 Android 主題的底線與它的內縮讓 P31 的欄位比 iOS 右移 4 dp,
            // 並把下方的列往下推(2026-10-10)。
            case .automatic, .plain:
                // The same pair `createTextEditor` uses, and for the same
                // reason: with no background there is no drawable to supply an
                // inset, and the theme's leftover padding would read as a
                // stray indent.
                // 與 `createTextEditor` 所用的是同一對，理由也相同：沒有背景就沒有 drawable 來提供
                // 內縮，而主題殘留的 padding 會看起來像一段莫名的縮排。
                textField.setBackground(nil)
                textField.setPadding(0, 0, 0, 0)
                // And no minimum height: the theme's 48 dp kept a strip of empty
                // field under the text (P31). 也不設最小高度：主題的 48 dp 讓文字底下留著一段空白欄位(P31)。
                textField.setMinHeight(0)
                textField.setMinimumHeight(0)
            case .roundedBorder, .squareBorder:
                let density = textField.getResources().getDisplayMetrics().density

                var strokeColor = environment.suggestedForegroundColor
                    .resolve(in: environment)
                strokeColor.opacity *= 0.25

                // No `setShape(RECTANGLE)`: `GradientDrawable`'s own default
                // shape is `RECTANGLE`, so the call would be a `JavaClass`
                // lookup and a JNI round trip per update to assert the status
                // quo. `CustomButton.kt` sets it because it is written in
                // Kotlin, where it costs a field write.
                //
                // 不呼叫 `setShape(RECTANGLE)`：`GradientDrawable` 自身的預設形狀就是 `RECTANGLE`，
                // 因此該呼叫只會是每次更新多一次 `JavaClass` 查找與一趟 JNI 往返，去主張現狀。
                // `CustomButton.kt` 之所以會設定它，是因為它是用 Kotlin 寫的，在那裡代價僅是一次
                // 欄位寫入。
                let background = GradientDrawable(environment: Self.env)
                background.setStroke(
                    Int32(density.rounded()),
                    strokeColor.asColorInt()
                )
                background.setCornerRadius(style == .roundedBorder ? 4 * density : 0)

                textField.setBackground(background)
                let horizontal = Int32((8 * density).rounded())
                let vertical = Int32((6 * density).rounded())
                textField.setPadding(horizontal, vertical, horizontal, vertical)
        }
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField.as(CustomEditText.self)!
        textField.setTextFromSwift(content)
    }

    public func getContent(ofTextField textField: Widget) -> String {
        let textField = textField.as(AndroidKit.TextView.self)!
        return textField.getText().toString()
    }

    public func createSecureField() -> Widget {
        let field = SecureEditText(activity: Self.activity, environment: Self.env)
        Self.makePlain(field)
        return field
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        updateTextField(
            secureField,
            placeholder: placeholder,
            environment: environment,
            onChange: onChange,
            onSubmit: onSubmit
        )
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        setContent(ofTextField: secureField, to: content)
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        getContent(ofTextField: secureField)
    }

    public func createTextEditor() -> Widget {
        let editText = CustomEditText(activity: Self.activity, environment: Self.env)
        Self.makePlain(editText)
        return editText
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        updateTextField(
            textEditor.as(CustomEditText.self)!,
            placeholder: "",
            environment: environment,
            onChange: onChange,
            onSubmit: nil,
            isMultiline: true
        )
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        setContent(ofTextField: textEditor, to: content)
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        getContent(ofTextField: textEditor)
    }
}

@JavaClass("android.text.InputType")
class InputType: JavaObject {
}

extension JavaClass where JavaClass_T == InputType {
    @JavaStaticField(isFinal: true)
    var TYPE_CLASS_NUMBER: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_CLASS_PHONE: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_CLASS_TEXT: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_NUMBER_FLAG_DECIMAL: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_NUMBER_FLAG_SIGNED: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_NUMBER_VARIATION_NORMAL: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_TEXT_FLAG_MULTI_LINE: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_TEXT_VARIATION_EMAIL_ADDRESS: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_TEXT_VARIATION_NORMAL: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_TEXT_VARIATION_PERSON_NAME: Int32

    @JavaStaticField(isFinal: true)
    var TYPE_TEXT_VARIATION_URI: Int32
}

// swiftlint:disable force_try
extension TextContentType {
    public func toInputType(isMultiline: Bool) -> Int32 {
        let inputType = try! JavaClass<InputType>()

        var type: Int32 = 0
        switch self {
            case .text:
                type |= inputType.TYPE_CLASS_TEXT
                type |= inputType.TYPE_TEXT_VARIATION_NORMAL
                if isMultiline {
                    type |= inputType.TYPE_TEXT_FLAG_MULTI_LINE
                }
            case .digits(_):
                type |= inputType.TYPE_CLASS_NUMBER
                type |= inputType.TYPE_NUMBER_VARIATION_NORMAL
            case .url:
                type |= inputType.TYPE_CLASS_TEXT
                type |= inputType.TYPE_TEXT_VARIATION_URI
                if isMultiline {
                    type |= inputType.TYPE_TEXT_FLAG_MULTI_LINE
                }
            case .phoneNumber:
                type |= inputType.TYPE_CLASS_PHONE
            case .name:
                type |= inputType.TYPE_CLASS_TEXT
                type |= inputType.TYPE_TEXT_VARIATION_PERSON_NAME
                if isMultiline {
                    type |= inputType.TYPE_TEXT_FLAG_MULTI_LINE
                }
            case .decimal(let signed):
                type |= inputType.TYPE_CLASS_NUMBER
                type |= inputType.TYPE_NUMBER_FLAG_DECIMAL
                type |= inputType.TYPE_NUMBER_VARIATION_NORMAL
                if signed {
                    type |= inputType.TYPE_NUMBER_FLAG_SIGNED
                }
            case .emailAddress:
                type |= inputType.TYPE_CLASS_TEXT
                type |= inputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                if isMultiline {
                    type |= inputType.TYPE_TEXT_FLAG_MULTI_LINE
                }
        }
        return type
    }
}
