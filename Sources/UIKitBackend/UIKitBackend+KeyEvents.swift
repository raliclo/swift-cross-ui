import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.KeyEvents {
    public func createKeyEventTarget(wrapping child: Widget) -> Widget {
        KeyEventWidget(child: child)
    }

    public func updateKeyEventTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onKey: @escaping (KeyPress) -> Void
    ) {
        let target = target as! KeyEventWidget
        target.isEnabled = environment.isEnabled
        target.onKey = onKey
    }
}

/// Keys on iOS, which has no keyboard until something is plugged in and no
/// first responder until something asks.
///
/// **`pressesBegan`/`pressesEnded`, not `UIKeyCommand`.** A key command is the
/// menu-shortcut mechanism: it takes a selector, goes through the responder
/// chain, and is the thing #121 uses. It cannot report a key going up, and it
/// cannot report a modifier being held with nothing else -- which is the half
/// SoftPCB's §10.7 gap 4 is actually about. `UIPress` carries a `UIKey` from
/// iOS 13.4, and that is what these overrides read.
///
/// **A modifier change on its own arrives as a press whose key is a modifier.**
/// UIKit differs from AppKit here: AppKit has `flagsChanged` and UIKit sends
/// Shift through `pressesBegan` like any other key, with `UIKey.keyCode` one of
/// the `keyboardLeftShift` family. Those are turned into the `key == nil` case
/// `KeyPress` documents, so an application sees the same shape on both.
///
/// iOS 上的按鍵:在有東西插上之前它沒有鍵盤,在有東西提出要求之前它沒有 first responder。
///
/// **用 `pressesBegan`/`pressesEnded`,不是 `UIKeyCommand`。** key command 是選單快捷鍵的機制:
/// 它接收 selector、走 responder chain,也是 #121 所使用的東西。它回報不了「鍵放開」,也回報不了
/// 「只按住一個修飾鍵、什麼都沒按」——而後者正是 SoftPCB §10.7 第 4 項缺口真正在講的那一半。
/// 自 iOS 13.4 起 `UIPress` 帶著一個 `UIKey`,而下面這些覆寫讀的就是它。
///
/// **單獨的修飾鍵變化,會以「鍵本身是修飾鍵」的按鍵事件送達。** UIKit 在這裡與 AppKit 不同:AppKit 有
/// `flagsChanged`,而 UIKit 會像送任何其他鍵一樣、把 Shift 經由 `pressesBegan` 送出,其
/// `UIKey.keyCode` 屬於 `keyboardLeftShift` 那一族。此處把那些轉成 `KeyPress` 所載明的 `key == nil`
/// 情況,好讓應用程式在兩邊看到相同的形狀。
final class KeyEventWidget: ContainerWidget {
    var isEnabled = true
    var onKey: ((KeyPress) -> Void)?

    override init(child: some WidgetProtocol) {
        super.init(child: child)
    }

    /// Without this the overrides below never run. A `UIView` returns false by
    /// default, so it is never first responder, so no press ever reaches it.
    /// 少了這個,下面那些覆寫永遠不會執行。`UIView` 預設回傳 false,因此它永遠不是 first responder,
    /// 因此沒有任何按鍵到得了它。
    override var canBecomeFirstResponder: Bool { isEnabled }

    /// `viewDidAppear`, not `didMoveToWindow`.
    ///
    /// **A `ContainerWidget` is a view CONTROLLER, and the first version of this
    /// file overrode a `UIView` method on it.** It never compiled -- and it was
    /// committed saying it did, because UIKitBackend is not built by a plain
    /// `swift build` on a macOS host and I never ran `compile.zsh -ios` after
    /// writing it. That is mistakes.md entry 10 exactly: verified on the one
    /// platform where the defect was impossible.
    ///
    /// 用 `viewDidAppear`,不是 `didMoveToWindow`。
    ///
    /// **`ContainerWidget` 是一個 view **controller**,而本檔的第一版在它上面覆寫了一個 `UIView` 的方法。**
    /// 它從來沒有編譯過——而它被提交時還說它編得過,因為在 macOS 主機上,一個單純的 `swift build`
    /// 不會建 UIKitBackend,而我寫完之後沒有跑過 `compile.zsh -ios`。那正是 mistakes.md 第 10 條:
    /// 在「那個缺陷不可能發生」的唯一平台上驗證。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard view.window != nil else { return }
        // Deferred for the reason AppKit's is: during assembly the request is
        // accepted and then superseded.
        // 延後一輪,理由與 AppKit 那邊相同:在組裝期間這個要求會被接受、然後被取代。
        DispatchQueue.main.async { [weak self] in
            _ = self?.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isEnabled, report(presses, phase: .down) else {
            super.pressesBegan(presses, with: event)
            return
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isEnabled, report(presses, phase: .up) else {
            super.pressesEnded(presses, with: event)
            return
        }
    }

    private func report(_ presses: Set<UIPress>, phase: KeyPress.Phase) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            handled = true
            var modifiers = Self.modifiers(from: key.modifierFlags)
            if let own = Self.modifierBit(for: key.keyCode) {
                // **A modifier's own RELEASE still reports itself as held, and this is the third
                // backend where that was true.**
                //
                // `UIKey.modifierFlags` on `pressesEnded` for the Shift key still contains
                // `.shift`, so a caller watching `press.modifiers` sees Shift go down and never
                // come up -- a stuck modifier, which reads as the app being wrong rather than the
                // backend. Measured on 2026-09-22: P72 printed `MODIFIERS up shift=true`.
                // AppKitSynthesiser had it on 2026-09-19 and AndroidSynthesiser on 2026-09-22;
                // this is the same shape a third time, here in a backend rather than a
                // synthesiser. AppKit's `flagsChanged` reports the state AFTER the change, which
                // is the behaviour being matched.
                //
                // **一個修飾鍵自己的**放開**仍然回報自己被按住,而這已經是第三個出現這件事的 backend。**
                //
                // Shift 的 `pressesEnded` 上,`UIKey.modifierFlags` 仍然含有 `.shift`;因此一個觀察
                // `press.modifiers` 的呼叫端會看到 Shift 按下去、而且永遠沒有放開——一個卡住的修飾鍵,
                // 讀起來像是 app 錯了、而不是 backend 錯了。2026-09-22 實測:P72 印出
                // `MODIFIERS up shift=true`。AppKitSynthesiser 在 2026-09-19、AndroidSynthesiser 在
                // 2026-09-22 各有一次;這是同一個形狀的第三次,而這次在 backend 裡、不在 synthesiser 裡。
                // AppKit 的 `flagsChanged` 回報的是變化**之後**的狀態,而此處要對齊的就是那個行為。
                if phase == .up { modifiers.remove(own) }
                onKey?(
                    KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase)
                )
            } else {
                onKey?(
                    KeyPress(
                        key: Self.equivalent(for: key),
                        characters: key.characters,
                        modifiers: modifiers,
                        phase: phase
                    )
                )
            }
        }
        return handled
    }

    /// **`charactersIgnoringModifiers` is a WORD for an arrow key on iOS, and taking its first
    /// character silently produced the letter U.**
    ///
    /// That is what this file did until 2026-09-22. AppKit hands back a single scalar in the
    /// private-use block -- U+F700 for the up arrow -- and the obvious transliteration,
    /// `bare.first.map(KeyEquivalent.init)`, reads correctly and is wrong here: UIKit returns
    /// `UIKeyCommand.inputUpArrow`, whose value is the eighteen-character string
    /// `"UIKeyInputUpArrow"`. Its first character is `U`, which is a perfectly valid
    /// ``KeyEquivalent`` for a completely different key.
    ///
    /// Nothing reports that. An app switching on `press.key` falls through to `default`, so the
    /// arrow does nothing while the press count rises -- P72 showed `keys: 2 ... high 1.30`, two
    /// presses and a camera that had not moved, and the giveaway was the readout printing
    /// `last U`.
    ///
    /// The `keyCode` is a HID usage and is unambiguous, so the named keys are mapped from it. The
    /// scalars are ``KeyEquivalent``'s own, which is what makes `press.key == .upArrow` mean the
    /// same thing on AppKit, UIKit and AndroidBackend. `AndroidBackend+KeyEvents.swift` maps
    /// Android keycodes onto the same set, for the same reason.
    ///
    /// **在 iOS 上,方向鍵的 `charactersIgnoringModifiers` 是一個**單字**,而取它的第一個字元會
    /// 靜默地產生字母 U。**
    ///
    /// 那正是本檔在 2026-09-22 之前所做的事。AppKit 交回的是私有使用區的單一 scalar——上方向鍵是
    /// U+F700——而那個看起來理所當然的音譯 `bare.first.map(KeyEquivalent.init)` 讀起來沒問題,在此處卻是
    /// 錯的:UIKit 回傳的是 `UIKeyCommand.inputUpArrow`,其值是十八個字元的字串
    /// `"UIKeyInputUpArrow"`。它的第一個字元是 `U`,而那是一個**完全不同的按鍵**的合法 ``KeyEquivalent``。
    ///
    /// 沒有任何東西會回報這件事。一個對 `press.key` 做 switch 的 app 會落到 `default`,於是方向鍵什麼都
    /// 不做、而按鍵計數照常上升——P72 顯示的是 `keys: 2 ... high 1.30`:兩次按鍵,而相機沒有移動;
    /// 露餡的是讀數上那個 `last U`。
    ///
    /// `keyCode` 是 HID usage、毫無歧義,因此具名的按鍵改由它對照。那些 scalar 是 ``KeyEquivalent``
    /// 自己的那一組,那正是讓 `press.key == .upArrow` 在 AppKit、UIKit 與 AndroidBackend 上意義相同的
    /// 原因。`AndroidBackend+KeyEvents.swift` 把 Android 的 keycode 對到同一組,理由相同。
    private static func equivalent(for key: UIKey) -> KeyEquivalent? {
        let named: Character? =
            switch key.keyCode {
                case .keyboardUpArrow: "\u{F700}"
                case .keyboardDownArrow: "\u{F701}"
                case .keyboardLeftArrow: "\u{F702}"
                case .keyboardRightArrow: "\u{F703}"
                case .keyboardTab: "\u{9}"
                case .keyboardReturnOrEnter, .keypadEnter: "\r"
                case .keyboardDeleteOrBackspace: "\u{7F}"
                case .keyboardDeleteForward: "\u{F728}"
                case .keyboardHome: "\u{F729}"
                case .keyboardEnd: "\u{F72B}"
                case .keyboardPageUp: "\u{F72C}"
                case .keyboardPageDown: "\u{F72D}"
                case .keyboardEscape: "\u{1B}"
                case .keyboardSpacebar: " "
                default: nil
            }
        if let named { return KeyEquivalent(named) }
        // An ordinary printable key: `charactersIgnoringModifiers` really is one character for
        // these, and using it keeps the layout the user is typing on rather than a US-QWERTY
        // guess derived from the HID usage.
        // 一個普通的可列印按鍵:對這些而言 `charactersIgnoringModifiers` 確實是一個字元,而用它可以
        // 保留使用者實際使用的鍵盤配置,而不是從 HID usage 推導出的一個「美式 QWERTY」猜測。
        let bare = key.charactersIgnoringModifiers
        guard bare.count == 1, let first = bare.first else { return nil }
        return KeyEquivalent(first)
    }

    /// Which modifier a key IS, or nil if it is not one.
    ///
    /// Replaces the flat `modifierKeyCodes` set this file used to carry: the set could say "this
    /// is a modifier" and not which, and the release fix above needs which. Left and right map to
    /// the same ``EventModifiers`` case because that is all this package's modifier set can
    /// express -- the same collapse `AndroidSynthesiser.modifierBit(for:)` makes.
    ///
    /// 一個按鍵**是**哪一個修飾鍵;若它不是修飾鍵則為 nil。
    ///
    /// 取代本檔原本那個扁平的 `modifierKeyCodes` 集合:那個集合說得出「這是一個修飾鍵」、說不出是哪一個,
    /// 而上面那個「放開」的修法需要知道是哪一個。左右兩側對到同一個 ``EventModifiers`` case,因為那是
    /// 本套件的修飾鍵集合所能表達的全部——與 `AndroidSynthesiser.modifierBit(for:)` 所做的是同一種塌縮。
    private static func modifierBit(for keyCode: UIKeyboardHIDUsage) -> EventModifiers? {
        switch keyCode {
            case .keyboardLeftShift, .keyboardRightShift: .shift
            case .keyboardLeftControl, .keyboardRightControl: .control
            case .keyboardLeftAlt, .keyboardRightAlt: .option
            case .keyboardLeftGUI, .keyboardRightGUI: .command
            default: nil
        }
    }

    private static func modifiers(from flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
