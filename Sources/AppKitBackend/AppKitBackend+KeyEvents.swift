import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.KeyEvents {
    public func createKeyEventTarget(wrapping child: Widget) -> Widget {
        NSKeyEventTarget(wrapping: child)
    }

    public func updateKeyEventTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onKey: @escaping (KeyPress) -> Void
    ) {
        let target = target as! NSKeyEventTarget
        target.isEnabled = environment.isEnabled
        target.onKey = onKey
    }
}

/// A view that takes focus and reports the keys it receives.
///
/// **Taking focus is half the feature, and the half that is easy to leave out.**
/// `acceptsFirstResponder` alone is not enough: it says the view CAN be first
/// responder, not that it is. Something has to make it so, and nothing will --
/// this view is not a control and the user has no reason to click it first. So
/// it asks the window itself once it has one. Without that the overrides below
/// compile, run, and are never called, which looks exactly like a keyboard that
/// is not working.
///
/// 一個會取得焦點、並回報它所收到的按鍵的 view。
///
/// **取得焦點是這項功能的一半,而且是容易被漏掉的那一半。** 光有 `acceptsFirstResponder` 並不夠:
/// 它說的是這個 view **可以**成為 first responder,不是它**已經是**。必須有東西讓它成為,而不會有——
/// 這個 view 不是控制項,使用者也沒有理由先去點它。因此它在取得 window 之後,自己向 window 要求一次。
/// 少了那一步,下面那些覆寫會編得過、會執行,而且永遠不會被呼叫——那看起來就像是鍵盤壞了。
final class NSKeyEventTarget: NSView {
    var isEnabled = true
    var onKey: ((KeyPress) -> Void)?

    private var lastModifiers: EventModifiers = []

    init(wrapping child: NSView) {
        super.init(frame: .zero)
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        // **Claimed when the window BECOMES KEY, not once when the view is
        // added, and the difference is the whole of why the first version
        // reported no keys at all.** Traced on 2026-09-19: the view reaches its
        // window and `viewDidMoveToWindow` runs, but at that moment
        // `window.isKeyWindow` is false and `window.firstResponder` is nil --
        // the window has not been activated yet. `makeFirstResponder` there
        // either fails or is undone when activation finishes, and a view that is
        // not first responder of a key window receives nothing. The app renders,
        // the clock ticks, and the keyboard looks broken.
        //
        // The notification fires every activation, so the claim also survives
        // the user switching to another app and back.
        //
        // **在 window **成為 key** 時才搶,而不是在這個 view 被加入時搶一次;而那個差別,就是第一版
        // 完全收不到任何按鍵的全部原因。** 2026-09-19 追蹤所得:這個 view 確實到達了它的 window、
        // `viewDidMoveToWindow` 確實執行,但在那個時刻 `window.isKeyWindow` 是 false、
        // `window.firstResponder` 是 nil——那個 window 還沒有被啟用。在那裡呼叫 `makeFirstResponder`
        // 不是失敗、就是在啟用完成時被撤銷;而一個「不是 key window 之 first responder」的 view
        // 什麼都收不到。App 有畫、時鐘有跳,而鍵盤看起來是壞的。
        //
        // 這個通知在每一次啟用時都會發出,因此這個宣告也能在使用者切到別的 app 再切回來之後存活。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        if window.isKeyWindow { claimFocus() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func windowBecameKey() {
        claimFocus()
    }

    private func claimFocus() {
        guard isEnabled, let window, window.firstResponder !== self else { return }
        // A text control keeps focus: typing into one is the case where taking
        // it away is plainly wrong. Everything else in this window is scenery.
        // 文字控制項保有焦點:「正在輸入」正是把焦點搶走明顯錯誤的那個情況。此 window 中其餘的東西都是布景。
        guard !(window.firstResponder is NSText) else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, report(event, phase: event.isARepeat ? .repeat : .down) else {
            super.keyDown(with: event)
            return
        }
    }

    override func keyUp(with event: NSEvent) {
        guard isEnabled, report(event, phase: .up) else {
            super.keyUp(with: event)
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isEnabled else {
            super.flagsChanged(with: event)
            return
        }
        // **A modifier change is not a key down or a key up, and AppKit will not
        // tell you which.** `flagsChanged` fires for both pressing and releasing
        // Shift, with the same event type; the only difference is whether the
        // flag is now set. The phase is therefore derived from whether the new
        // set is larger than the old one, which is also why `lastModifiers` is
        // kept: the event alone cannot answer it.
        // **一次修飾鍵變化既不是按下、也不是放開,而 AppKit 不會告訴你是哪一個。** 按下與放開 Shift
        // 都會觸發 `flagsChanged`,事件型別相同;唯一的差別在於那個旗標現在是否被設定。因此這裡的
        // phase 是由「新集合是否比舊集合大」推導出來的——那也正是要保留 `lastModifiers` 的原因:
        // 光靠那個事件本身回答不了。
        let modifiers = Self.modifiers(from: event.modifierFlags)
        let phase: KeyPress.Phase =
            modifiers.rawValue > lastModifiers.rawValue ? .down : .up
        lastModifiers = modifiers
        onKey?(
            KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase)
        )
    }

    private func report(_ event: NSEvent, phase: KeyPress.Phase) -> Bool {
        let modifiers = Self.modifiers(from: event.modifierFlags)
        lastModifiers = modifiers
        // `charactersIgnoringModifiers` for the key and `characters` for what it
        // produced, which is the distinction `KeyPress` documents: Shift-S is
        // the "s" key and the character "S".
        // 以 `charactersIgnoringModifiers` 作為那個鍵、以 `characters` 作為它產生的東西——那正是
        // `KeyPress` 所載明的分別:Shift-S 是「s」這個鍵,以及「S」這個字元。
        guard let bare = event.charactersIgnoringModifiers, let first = bare.first else {
            return false
        }
        onKey?(
            KeyPress(
                key: KeyEquivalent(first),
                characters: event.characters ?? "",
                modifiers: modifiers,
                phase: phase
            )
        )
        return true
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
