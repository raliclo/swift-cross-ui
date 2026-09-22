import AndroidKit
import SwiftCrossUI

/// `.onKeyPress` on Android.
///
/// **A container that takes focus, because a view that cannot be focused receives no keys.**
/// `KeyEventContainer.kt` carries the two halves and why each is needed; this file is the mapping
/// between Android's `KeyEvent` and ``KeyPress``.
///
/// Android 上的 `.onKeyPress`。
///
/// **一個會取得焦點的容器,因為一個無法被聚焦的 view 收不到任何按鍵。** 那兩半以及各自的必要性寫在
/// `KeyEventContainer.kt`;本檔是 Android `KeyEvent` 與 ``KeyPress`` 之間的對照。
extension AndroidBackend: BackendFeatures.KeyEvents {
    public func createKeyEventTarget(wrapping child: Widget) -> Widget {
        let container = KeyEventContainer(context: Self.activity)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func updateKeyEventTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onKey: @escaping (KeyPress) -> Void
    ) {
        let target = target.as(KeyEventContainer.self)!
        guard environment.isEnabled else {
            target.setOnKey(nil)
            return
        }
        target.setOnKey(
            SwiftAction(action: {
                MainActor.assumeIsolated {
                    onKey(Self.keyPress(from: target))
                }
            })
        )
    }

    private static func keyPress(from target: KeyEventContainer) -> KeyPress {
        let modifiers = modifiers(fromMetaState: target.getMetaState())
        let phase: KeyPress.Phase =
            switch target.getPhase() {
                case 1: .up
                case 2: .repeat
                default: .down
            }

        // A modifier change reports `key == nil`, which is what ``KeyPress`` defines it to mean.
        // Android delivers Shift as an ordinary key event with its own keycode, so unlike AppKit --
        // where `flagsChanged` is a separate callback and the phase has to be derived by comparing
        // modifier sets -- the phase here is simply the event's own action.
        // 一次修飾鍵變化以 `key == nil` 回報,那正是 ``KeyPress`` 為它下的定義。Android 把 Shift 當成
        // 一個帶有自己 keycode 的普通按鍵事件送出,因此與 AppKit 不同——那裡 `flagsChanged` 是獨立的
        // callback,phase 必須靠比較兩個修飾鍵集合推導出來——此處的 phase 就是該事件自己的 action。
        guard !target.isModifier() else {
            return KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase)
        }

        let key = keyEquivalent(keyCode: target.getKeyCode(), bareChar: target.getBareChar())
        let typed = target.getTypedChar()
        let characters =
            typed > 0 && typed < 0x11_0000
                ? String(UnicodeScalar(UInt32(typed)) ?? " ")
                : ""

        return KeyPress(key: key, characters: characters, modifiers: modifiers, phase: phase)
    }

    /// **The keys with no printable character are mapped by KEYCODE, not by what
    /// `getUnicodeChar` returns for them, because for these it returns zero.**
    ///
    /// The scalars are the ones ``KeyEquivalent`` already uses -- the private-use block SwiftUI
    /// and AppKit both spell arrows in. Mapping Android's `KEYCODE_DPAD_UP` onto `U+F700` is what
    /// lets `press.key == .upArrow` be written once in an app and hold on both platforms; leaving
    /// it as zero would make every arrow key on Android an unidentifiable key that happens to type
    /// nothing. `AppKitSynthesiser.functionKeyCharacter(for:)` does the same translation from the
    /// other side.
    ///
    /// **沒有可列印字元的那些鍵是以 KEYCODE 對照的,不是以 `getUnicodeChar` 的回傳值,因為對它們而言
    /// 那個函式回傳零。**
    ///
    /// 這些 scalar 就是 ``KeyEquivalent`` 本來就在用的那一組——SwiftUI 與 AppKit 用來表示方向鍵的
    /// 私有使用區。把 Android 的 `KEYCODE_DPAD_UP` 對到 `U+F700`,才讓 `press.key == .upArrow`
    /// 在 app 裡寫一次、在兩個平台上都成立;若放著讓它是零,Android 上的每一個方向鍵都會變成一個
    /// 「無法辨識、而且剛好什麼都不打出來」的鍵。`AppKitSynthesiser.functionKeyCharacter(for:)`
    /// 從另一側做的是同一件翻譯。
    private static func keyEquivalent(keyCode: Int32, bareChar: Int32) -> KeyEquivalent? {
        let named: Character? =
            switch keyCode {
                case 19: "\u{F700}" // KEYCODE_DPAD_UP
                case 20: "\u{F701}" // KEYCODE_DPAD_DOWN
                case 21: "\u{F702}" // KEYCODE_DPAD_LEFT
                case 22: "\u{F703}" // KEYCODE_DPAD_RIGHT
                case 61: "\u{9}" // KEYCODE_TAB
                case 66: "\r" // KEYCODE_ENTER
                case 67: "\u{7F}" // KEYCODE_DEL (backspace)
                case 92: "\u{F72C}" // KEYCODE_PAGE_UP
                case 93: "\u{F72D}" // KEYCODE_PAGE_DOWN
                case 111: "\u{1B}" // KEYCODE_ESCAPE
                case 112: "\u{F728}" // KEYCODE_FORWARD_DEL
                case 122: "\u{F729}" // KEYCODE_MOVE_HOME
                case 123: "\u{F72B}" // KEYCODE_MOVE_END
                default: nil
            }
        if let named { return KeyEquivalent(named) }
        guard bareChar > 0, bareChar < 0x11_0000, let scalar = UnicodeScalar(UInt32(bareChar))
        else { return nil }
        return KeyEquivalent(Character(scalar))
    }

    /// **CTRL becomes `.command`, and `.control` is never reported. That is a
    /// deliberate one-way street, not an oversight.**
    ///
    /// ``AndroidBackend/keyModifiers(for:)`` maps BOTH `.command` and `.control` onto
    /// `META_CTRL_ON` when it installs a menu shortcut, because that is the convention
    /// ``EventModifiers/command`` records: SwiftUI's `.command` is Command on Apple platforms and
    /// Ctrl everywhere else. Two names collapsing onto one bit cannot be un-collapsed coming back,
    /// so the choice is which one to report -- and `.command` is the one that makes a shortcut
    /// written once behave the same way in both directions. An app that wants to distinguish the
    /// physical Ctrl key from Command on Android is asking a question this pair of mappings has
    /// already answered no to.
    ///
    /// META -- the Command key on an Apple keyboard attached to an Android device -- reports
    /// `.command` for the same reason.
    ///
    /// **CTRL 變成 `.command`,而 `.control` 永遠不會被回報。那是刻意的單行道,不是疏漏。**
    ///
    /// ``AndroidBackend/keyModifiers(for:)`` 在安裝選單快捷鍵時,把 `.command` 與 `.control`
    /// **兩者**都對到 `META_CTRL_ON`,因為那正是 ``EventModifiers/command`` 所記載的慣例:
    /// SwiftUI 的 `.command` 在 Apple 平台上是 Command,在其餘平台上是 Ctrl。兩個名字塌縮到同一個
    /// 位元之後,回程就無法再把它們分開;因此要選的是「回報哪一個」——而 `.command` 是那個能讓
    /// 「寫一次的快捷鍵在兩個方向上行為相同」的選擇。一個想在 Android 上區分實體 Ctrl 與 Command 的
    /// app,問的是這組對照早已回答「不行」的問題。
    ///
    /// META——接在 Android 裝置上的 Apple 鍵盤上的 Command 鍵——基於同一理由也回報 `.command`。
    private static func modifiers(fromMetaState metaState: Int32) -> EventModifiers {
        /// `KeyEvent.META_SHIFT_ON`
        let shift: Int32 = 0x1
        /// `KeyEvent.META_ALT_ON`
        let alt: Int32 = 0x2
        /// `KeyEvent.META_CTRL_ON`
        let ctrl: Int32 = 0x1000
        /// `KeyEvent.META_META_ON`
        let meta: Int32 = 0x1_0000

        var modifiers: EventModifiers = []
        if metaState & shift != 0 { modifiers.insert(.shift) }
        if metaState & alt != 0 { modifiers.insert(.option) }
        if metaState & (ctrl | meta) != 0 { modifiers.insert(.command) }
        return modifiers
    }
}
