extension BackendFeatures {
    /// Which widget the keyboard is talking to, and being told when that
    /// changes.
    ///
    /// **An action plus an event, which is why this is not ``Accessibility``.**
    /// A label is set and then it is there; nobody else changes it. Focus is the
    /// opposite: asking for it can be REFUSED, and it moves for reasons the app
    /// did not cause -- Tab, a click, a screen reader, a directional pad. The
    /// split was agreed in `testapp/plan/plan-focus-protocol.md` §4, and one
    /// protocol for both would have forced a backend that only wanted labels to
    /// implement focus reporting.
    ///
    /// **The five platforms differ in semantics, not just in spelling**, and
    /// three questions cover the difference:
    ///
    /// | | AppKit | UIKit | GTK | WinUI | Android |
    /// | --- | --- | --- | --- | --- | --- |
    /// | whose focus is it? | the window's responder chain | the scene's | each `GtkWindow`'s | `FocusManager`, across XAML islands | the view tree's, per window |
    /// | can a request be refused? | yes | yes | yes | yes | **yes, for a reason no other platform has: touch mode** |
    /// | does focus move on its own? | yes | yes | yes | yes | yes |
    ///
    /// Android's touch mode has no counterpart: a view is not focusable by
    /// default there and `requestFocus()` fails until
    /// `setFocusableInTouchMode(true)`. So on Android a refusal is ORDINARY,
    /// while on the other four it usually means the caller was wrong -- and that
    /// is the fact that decides ``focus(_:)``'s return type.
    ///
    /// **Conformance-checked, not required**, the arrangement ``ScrollingLists``,
    /// ``LazyListRows`` and ``Accessibility`` are under, so the five backends
    /// convert one at a time.
    ///
    /// 鍵盤正在對哪一個 widget 說話,以及在那件事改變時被告知。
    ///
    /// **一個動作加一個事件——這正是它不屬於 ``Accessibility`` 的原因。** 標籤設下去就在那裡,沒有
    /// 別人會改動它。焦點恰好相反:去要它可能**被拒絕**,而且它會因為 app 沒有造成的原因而移動——
    /// Tab、點擊、螢幕閱讀器、方向鍵。這個切分在 `testapp/plan/plan-focus-protocol.md` §4 議定;
    /// 把兩者合成一個協定,會迫使「只想加標籤」的 backend 去實作焦點回報。
    ///
    /// **五個平台的差異在語意,不只在名字**,而三個問題就能把差異分完(見上表)。
    ///
    /// Android 的 touch mode 沒有對應物:在那裡,view 預設**不可**取得焦點,`requestFocus()` 會失敗,
    /// 直到 `setFocusableInTouchMode(true)` 為止。因此在 Android 上「被拒絕」是**常態**,而在其餘四個
    /// 平台上,被拒絕多半代表呼叫者搞錯了——而那正是決定 ``focus(_:)`` 回傳型別的那個事實。
    ///
    /// **採 conformance 檢查而非要求實作**,與 ``ScrollingLists``、``LazyListRows``、``Accessibility``
    /// 同一種安排,好讓五個 backend 一次轉一個。
    @MainActor
    public protocol FocusableViews: Core {
        /// Gives this widget the focus within its window.
        ///
        /// **Returns whether it took it, and `Void` would have been wrong.**
        /// Android's `requestFocus()` already returns `Bool` and legitimately
        /// fails in touch mode; a disabled control refuses everywhere; a view
        /// that does not accept first responder refuses on AppKit. With a `Void`
        /// return, "this widget refused the focus" and "the focus moved" read
        /// identically at the call site, which is the shape this tree keeps
        /// catching.
        ///
        /// 讓這個 widget 在它的視窗內取得焦點。
        ///
        /// **回傳「它有沒有接受」,而 `Void` 會是錯的。** Android 的 `requestFocus()` 本來就回傳
        /// `Bool`,而且在 touch mode 下會正當地失敗;一個被停用的控制項在每個平台上都會拒絕;一個
        /// 不接受 first responder 的 view 在 AppKit 上會拒絕。若回傳 `Void`,「這個 widget 拒絕了
        /// 焦點」與「焦點移過去了」在呼叫端讀起來一模一樣——那正是這棵樹一再抓到的形狀。
        @discardableResult
        func focus(_ widget: Widget) -> Bool

        /// Takes the focus away from this widget, if it has it.
        ///
        /// Does nothing when it does not. "Unfocus something that is not
        /// focused" is not an error, and treating it as one would make every
        /// caller check first.
        ///
        /// 把焦點從這個 widget 移走(若它持有焦點)。
        ///
        /// 它沒有焦點時什麼都不做。「取消一個本來就沒有焦點的東西的焦點」不是錯誤,而把它當成錯誤,
        /// 會讓每一個呼叫端都得先檢查一次。
        func unfocus(_ widget: Widget)

        /// Whether this widget currently holds the focus.
        /// 這個 widget 目前是否持有焦點。
        func isFocused(_ widget: Widget) -> Bool

        /// Called when the focus arrives at or leaves this widget, for any
        /// reason.
        ///
        /// **Required, not an extra, and this is the half that cannot be
        /// simulated.** Focus moves for reasons the app did not cause: Tab, a
        /// click somewhere else, a screen reader, Android's directional pad.
        /// Without this a ``FocusState`` would be correct only until the user
        /// touched anything -- the same reason `Slider.onEditingChanged` (#126)
        /// had to exist.
        ///
        /// 當焦點抵達或離開這個 widget 時被呼叫,無論原因為何。
        ///
        /// **這是必要的、不是加分項,而且它是那個無法被模擬的一半。** 焦點會因為 app 沒有造成的原因
        /// 而移動:Tab、點到別的地方、螢幕閱讀器、Android 的方向鍵。少了它,一個 ``FocusState`` 只在
        /// 「使用者什麼都沒碰」時是對的——與 `Slider.onEditingChanged`(#126)之所以必須存在,是同一個
        /// 理由。
        func setFocusChangeHandler(
            ofWidget widget: Widget,
            to handler: @escaping (Bool) -> Void
        )
    }
}
