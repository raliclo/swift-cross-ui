import SwiftCrossUI
import UIKit

/// The closures a `UIKeyCommand` cannot carry, and the token that stands in for
/// one.
///
/// **A `UIKeyCommand` takes a selector, and a selector carries no captured
/// state.** `UIAction` takes a closure and is the shape the rest of this menu
/// code uses, but it has nowhere to put a key. So the closure stays here and the
/// command carries a token in its `propertyList` -- which is exactly what that
/// parameter is for: UIKit hands it back on `sender.propertyList` when the
/// command fires.
///
/// **Tokens are reused per rebuild rather than appended to.** `buildMenu` runs
/// again whenever the menu system is rebuilt, and a table that only grew would
/// hold every closure from every rebuild for the life of the process --
/// including closures capturing view state that has since been replaced. Firing
/// one of those would run an action against a stale graph, which is worse than
/// leaking: it is a button that does the wrong thing.
///
/// 那些 `UIKeyCommand` 帶不動的 closure,以及代替它們的那個 token。
///
/// **`UIKeyCommand` 收的是 selector,而 selector 不帶任何被捕捉的狀態。** `UIAction` 收 closure,
/// 也是本選單程式其餘部分所用的形狀,但它沒有地方放按鍵。因此 closure 留在這裡,而那個 command 在它的
/// `propertyList` 裡帶一個 token——那正是該參數的用途:command 觸發時,UIKit 會從
/// `sender.propertyList` 把它交回來。
///
/// **每次重建都重用 token,而不是往上累加。** 選單系統每次重建時 `buildMenu` 都會再跑一次;一張只增不
/// 減的表,會在整個行程的生命期裡持有**每一次**重建的每一個 closure——包括那些捕捉了「後來已被替換的
/// view 狀態」的 closure。觸發到其中之一,等於對一棵過期的圖執行一個動作;那比洩漏更糟:那是一顆做錯
/// 事情的按鈕。
enum MenuShortcutActions {
    /// Keyed by the token handed to `UIKeyCommand.propertyList`.
    ///
    /// `nonisolated(unsafe)` because every access is on the main thread -- menus
    /// are built there and key commands are delivered there -- and the type is
    /// not reachable from anywhere else.
    /// 以交給 `UIKeyCommand.propertyList` 的那個 token 為鍵。
    ///
    /// 標為 `nonisolated(unsafe)`,因為每一次存取都在主執行緒上——選單在那裡建立,按鍵命令也在那裡
    /// 送達——而這個型別在別處無從觸及。
    nonisolated(unsafe) private static var actions: [Int: @MainActor () -> Void] = [:]
    nonisolated(unsafe) private static var next = 0

    /// Starts a fresh generation of tokens.
    ///
    /// Called once per `buildMenu`, before any item is rendered. Everything from
    /// the previous build goes, because the menu about to be built replaces it
    /// entirely -- see the note on this type about stale closures.
    /// 開始新一代的 token。
    ///
    /// 每次 `buildMenu` 呼叫一次,時點在任何項目被繪製之前。前一次建置的一切都會被丟棄,因為即將被建
    /// 出來的那個選單會**整個**取代它——關於過期 closure,見這個型別上的說明。
    @MainActor
    static func beginRebuild() {
        actions.removeAll()
        next = 0
    }

    @MainActor
    static func register(_ action: @escaping @MainActor () -> Void) -> Int {
        next += 1
        actions[next] = action
        return next
    }

    /// Runs the action a fired command stands for, if it is still current.
    ///
    /// A token from a previous generation finds nothing and does nothing. That
    /// is the right answer rather than a missed press: the menu it belonged to
    /// no longer exists.
    /// 執行某個已觸發的 command 所代表的動作——若它仍然是當代的。
    ///
    /// 來自前一代的 token 什麼也找不到、什麼也不做。那是正確的答案,而不是一次被漏掉的按鍵:它所屬的
    /// 那個選單已經不存在了。
    @MainActor
    static func perform(token: Int) {
        actions[token]?()
    }
}

extension UIKitBackend {
    /// Maps SwiftCrossUI's modifiers onto UIKit's flags.
    ///
    /// `.command` is Command here, matching AppKit, and Ctrl on the three
    /// non-Apple backends -- the convention `EventModifiers.command` records.
    /// `.capsLock` has no `UIKeyModifierFlags` member and is dropped, which is
    /// stated rather than silently ignored: a shortcut asking for Caps Lock on
    /// iOS becomes the same shortcut without it.
    /// 把 SwiftCrossUI 的 modifier 映射到 UIKit 的 flags。
    ///
    /// `.command` 在此是 Command(與 AppKit 一致),而在三個非 Apple backend 上是 Ctrl——那是
    /// `EventModifiers.command` 所記載的慣例。`.capsLock` 在 `UIKeyModifierFlags` 裡沒有對應成員,
    /// 因此被捨棄;此處寫明而不是默默忽略:一個在 iOS 上要求 Caps Lock 的快捷鍵,會變成沒有它的同一個
    /// 快捷鍵。
    static func modifierFlags(for shortcut: KeyboardShortcut) -> UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.command) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.shift) }
        if shortcut.modifiers.contains(.option) { flags.insert(.alternate) }
        if shortcut.modifiers.contains(.control) { flags.insert(.control) }
        if shortcut.modifiers.contains(.numericPad) { flags.insert(.numericPad) }
        return flags
    }
}

extension ApplicationDelegate {
    /// The one selector every menu `UIKeyCommand` is dispatched to.
    ///
    /// **It lives on `ApplicationDelegate` because that is a `UIResponder` AND
    /// the object that builds the menu.** A key command's selector travels the
    /// responder chain; putting it on a helper object would mean the chain never
    /// reaches it and the key would do nothing, which is the failure this whole
    /// arrangement exists to avoid -- the menu item would still draw its "⌘S".
    ///
    /// 每一個選單 `UIKeyCommand` 都被派送到的那唯一一個 selector。
    ///
    /// **它住在 `ApplicationDelegate` 上,因為那既是一個 `UIResponder`、又是建出這個選單的那個物件。**
    /// 一個 key command 的 selector 會沿著 responder chain 傳遞;把它放在某個輔助物件上,等於 chain
    /// 永遠到不了它,而那個按鍵什麼都不會做——那正是整套安排所要避免的失敗,因為那個選單項目**仍然會**
    /// 把它的「⌘S」畫出來。
    @objc
    func scuiPerformKeyCommand(_ sender: UIKeyCommand) {
        guard let token = sender.propertyList as? Int else { return }
        MenuShortcutActions.perform(token: token)
    }
}
