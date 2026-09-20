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
            let modifiers = Self.modifiers(from: key.modifierFlags)
            if Self.modifierKeyCodes.contains(key.keyCode) {
                onKey?(
                    KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase)
                )
            } else {
                let bare = key.charactersIgnoringModifiers
                onKey?(
                    KeyPress(
                        key: bare.first.map { KeyEquivalent($0) },
                        characters: key.characters,
                        modifiers: modifiers,
                        phase: phase
                    )
                )
            }
        }
        return handled
    }

    private static let modifierKeyCodes: Set<UIKeyboardHIDUsage> = [
        .keyboardLeftShift,
        .keyboardRightShift,
        .keyboardLeftControl,
        .keyboardRightControl,
        .keyboardLeftAlt,
        .keyboardRightAlt,
        .keyboardLeftGUI,
        .keyboardRightGUI,
    ]

    private static func modifiers(from flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
