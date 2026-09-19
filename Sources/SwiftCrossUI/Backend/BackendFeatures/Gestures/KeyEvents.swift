/// A key going down or coming up over a view, with the modifiers held at the
/// time.
///
/// **`key` is a CHARACTER, not a physical key, and for a camera control that
/// matters.** ``KeyEquivalent`` says why in its own documentation: a key code is
/// a property of a keyboard layout rather than of a shortcut, so
/// `.keyboardShortcut("s")` reads the way SwiftUI's does. Reusing it here keeps
/// one key vocabulary in the framework instead of two, and it inherits the
/// consequence: **WASD is ZQSD on an AZERTY keyboard**, and an application that
/// wants the physical key under the finger cannot get it from this. That is a
/// real limit, stated rather than discovered. The alternative -- a second,
/// physical-key enumeration with an entry per key and a mapping per backend --
/// is a larger surface than anything asking for it today.
///
/// **`key` is `nil` when only the modifiers changed.** SwiftUI's `KeyPress` has
/// no such case, and this needs one: SoftPCB's `plan.md` §10.7 gap 4 is
/// *"modifier keys switch drag mode"*, which is holding Shift and having the
/// view behave differently before any other key is touched. A backend reports
/// that as a press whose `key` is absent and whose `modifiers` are the new set.
///
/// 一個在 view 上按下或放開的鍵,連同當時按住的修飾鍵。
///
/// **`key` 是一個**字元**,不是實體按鍵;而對一個相機控制而言,那是有差別的。** ``KeyEquivalent``
/// 自己的文件說明了理由:key code 是鍵盤配置的性質、不是快捷鍵的性質,那才讓 `.keyboardShortcut("s")`
/// 讀起來與 SwiftUI 一致。在此重用它,是為了讓框架裡只有**一套**按鍵語彙而不是兩套;而它也連帶繼承了
/// 那個後果:**在 AZERTY 鍵盤上,WASD 是 ZQSD**,而一個想要「手指底下那個實體鍵」的應用程式,從這裡
/// 拿不到。那是一個真實的限制,此處**寫明**、而不是留給人去發現。另一條路——第二套「每個實體鍵一個
/// 條目、每個 backend 一份對應表」的列舉——其表面積,比今天任何提出此需求的東西都要大。
///
/// **只有修飾鍵改變時,`key` 為 `nil`。** SwiftUI 的 `KeyPress` 沒有這種情況,而這裡需要:
/// SoftPCB `plan.md` §10.7 的第 4 項缺口正是*「修飾鍵切換拖曳模式」*——也就是按住 Shift,讓那個 view
/// 在還沒碰到任何其他鍵之前就表現不同。backend 會把它回報為一次「`key` 不存在、`modifiers` 為新集合」
/// 的按鍵事件。
public struct KeyPress: Equatable, Sendable {
    /// What phase of the press this is.
    /// 這次按鍵處於哪個階段。
    public enum Phase: Equatable, Sendable {
        case down
        /// The platform's auto-repeat while a key is held.
        ///
        /// Reported separately from ``down`` because the rate is the user's
        /// system setting on every platform here, so an application that counts
        /// presses and one that moves a camera want opposite things from it.
        ///
        /// 平台在按鍵被按住時的自動重複。
        ///
        /// 與 ``down`` 分開回報,因為在此處每個平台上那個速率都是使用者的系統設定;因此一個「計算按鍵
        /// 次數」的應用程式與一個「移動相機」的應用程式,對它的期待恰好相反。
        case `repeat`
        case up
    }

    /// The key, or `nil` when only the modifiers changed.
    /// 那個鍵;當只有修飾鍵改變時為 `nil`。
    public var key: KeyEquivalent?

    /// What the key produced, with the modifiers applied -- `"S"` for Shift-S.
    /// Empty for a key with no character and for a modifiers-only change.
    /// 這個鍵在套用修飾鍵之後產生的東西——Shift-S 為 `"S"`。沒有字元的鍵,以及純修飾鍵變化,此處為空字串。
    public var characters: String

    /// The modifiers held at the time, after this event is applied.
    /// 當時按住的修飾鍵,已套用本次事件之後的狀態。
    public var modifiers: EventModifiers

    public var phase: Phase

    public init(
        key: KeyEquivalent?,
        characters: String,
        modifiers: EventModifiers,
        phase: Phase
    ) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
        self.phase = phase
    }
}

extension BackendFeatures {
    /// Raw key events delivered to a view, rather than to a menu item.
    ///
    /// **``ApplicationMenus`` and `.keyboardShortcut` are not this.** A shortcut
    /// fires one action from a menu, whether or not the menu is open, and the
    /// view underneath never hears the key. This hands the key to the view,
    /// which is what a view drawing its own content needs -- hold Shift to
    /// constrain a drag, press an arrow to nudge, release a modifier and have
    /// the cursor change back. SoftPCB's `plan.md` §10.7 lists it as gap 4:
    /// *no keyboard event API; implement `flagsChanged`/`keyDown` and set
    /// `acceptsFirstResponder = true`.*
    ///
    /// **Focus is the backend's problem, not the caller's.** A view only
    /// receives keys when it is first responder, and making it so differs per
    /// platform -- `acceptsFirstResponder` plus `makeFirstResponder` on AppKit,
    /// `becomeFirstResponder` and `canBecomeFirstResponder` on UIKit, a focus
    /// controller on GTK. A conforming backend arranges it when the target is
    /// created, so a caller that adds the modifier and presses a key gets the
    /// key. §10.7's gap 5 is exactly the focus half of this, and it is not a
    /// separate protocol for that reason.
    ///
    /// **Conformance-checked, like ``ScrollGestures``.**
    ///
    /// 直接送到 view、而不是送到選單項目的原始按鍵事件。
    ///
    /// **``ApplicationMenus`` 與 `.keyboardShortcut` 不是這個。** 一個快捷鍵會從選單觸發一個動作
    /// (不論選單是否開啟),而底下的 view 從來聽不到那個鍵。這個則是把鍵**交給 view**——那正是一個
    /// 自己畫自己內容的 view 所需要的:按住 Shift 來限制拖曳、按方向鍵微調、放開修飾鍵讓游標變回去。
    /// SoftPCB `plan.md` §10.7 把它列為第 4 項缺口:*無鍵盤事件 API;實作 `flagsChanged`/`keyDown`,
    /// 並設 `acceptsFirstResponder = true`。*
    ///
    /// **焦點是 backend 的事,不是呼叫端的事。** 一個 view 只有在成為 first responder 時才收得到鍵,
    /// 而「讓它成為」的做法各平台不同——AppKit 是 `acceptsFirstResponder` 加 `makeFirstResponder`,
    /// UIKit 是 `becomeFirstResponder` 與 `canBecomeFirstResponder`,GTK 是一個 focus controller。
    /// 有實作的 backend 會在建立 target 時安排好,好讓「加上這個 modifier、按一個鍵」的呼叫端真的收到鍵。
    /// §10.7 的第 5 項缺口正是這件事的焦點那一半,而它之所以不是一個獨立的協定,理由就在這裡。
    ///
    /// **採 conformance 檢查,與 ``ScrollGestures`` 相同。**
    @MainActor
    public protocol KeyEvents: Core {
        func createKeyEventTarget(wrapping child: Widget) -> Widget

        func updateKeyEventTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onKey: @escaping (KeyPress) -> Void
        )
    }
}
