@_spi(Backends) import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.FocusableViews {
    /// `UIElement.focus(_:)`, which is SYNCHRONOUS and returns whether the
    /// element took the focus.
    ///
    /// **`TryFocusAsync` is the other spelling and is not the one this protocol
    /// wants.** It is the later, awaitable variant; `focus(_:)` has been on
    /// `UIElement` all along, returns `Bool`, and matches
    /// ``BackendFeatures/FocusableViews/focus(_:)`` exactly. The `throws` is
    /// absorbed with `try?` for the same reason AppKit's version returns false
    /// on a missing window: "could not" and "would not" are the same answer to
    /// the caller, and there is nothing useful to do with the error.
    ///
    /// `.programmatic` rather than `.keyboard` or `.pointer`, because this call
    /// IS programmatic -- nothing the user did caused it. The distinction is not
    /// cosmetic: WinUI draws the focus rectangle for `.keyboard` and withholds
    /// it for `.programmatic`, so passing `.keyboard` here would paint a
    /// keyboard-navigation ring around a control the user never tabbed to.
    ///
    /// `UIElement.focus(_:)`——它是**同步**的,並回傳該元素是否取得了焦點。
    ///
    /// **`TryFocusAsync` 是另一種寫法,而它不是本協定所要的那一個。** 那是後來加上、可等待的變體;
    /// `focus(_:)` 一直都在 `UIElement` 上、回傳 `Bool`,與
    /// ``BackendFeatures/FocusableViews/focus(_:)`` 完全對得上。其 `throws` 以 `try?` 吸收,
    /// 理由與 AppKit 版本在沒有視窗時回傳 false 相同:對呼叫端而言,「做不到」與「不願意」是同一個
    /// 答案,而那個 error 也沒有任何有用的處置方式。
    ///
    /// 使用 `.programmatic` 而非 `.keyboard` 或 `.pointer`,因為這次呼叫**就是**程式發起的
    /// ——沒有任何使用者動作導致它。這個區別不是裝飾性的:WinUI 會為 `.keyboard` 畫出焦點方框、
    /// 為 `.programmatic` 不畫;因此在此傳入 `.keyboard`,會在一個使用者從未 tab 到的控制項周圍
    /// 畫出鍵盤導覽的外框。
    @discardableResult
    public func focus(_ widget: Widget) -> Bool {
        // **A disabled control is refused before it is asked.** Measured by P70
        // on 2026-09-16: without this, "ask both for focus" reported
        // `DISABLED FOCUS reported true` -- `UIElement.focus(_:)` does not
        // reliably answer false for a disabled control, so this backend handed
        // the keyboard to one and told `@FocusState` it had worked.
        //
        // That is the one answer this protocol exists to get right: `focus`
        // returns WHETHER the widget took the focus, and a plausible true makes
        // every reader of `@FocusState` wrong about where the keyboard is.
        // AppKit refuses the same case by checking `acceptsFirstResponder`
        // first; `isEnabled` is the WinUI spelling.
        //
        // **一個被停用的控制項,在被詢問之前就先被拒絕。** 2026-09-16 由 P70 量到:少了這一段,
        // 「ask both for focus」回報 `DISABLED FOCUS reported true`——`UIElement.focus(_:)` 對於
        // 被停用的控制項並不可靠地回傳 false,於是本 backend 把鍵盤交給了它,並告訴 `@FocusState`
        // 這件事成功了。
        //
        // 那正是本協定存在所要答對的那一個答案:`focus` 回傳的是**該 widget 有沒有接受焦點**,
        // 而一個看似合理的 true,會讓每一個讀取 `@FocusState` 的人對「鍵盤在哪裡」判斷錯誤。
        // AppKit 以先檢查 `acceptsFirstResponder` 拒絕同一個情形;`isEnabled` 是 WinUI 的寫法。
        // **The CONTROL inside, never the wrapper.** Every widget this backend
        // hands out is a `Canvas`, and a `Canvas` accepts focus unconditionally:
        // instrumented on 2026-09-16, `focus(Canvas) enabled=not-a-Control
        // took=true` appeared 51 times in one run, including for the disabled
        // button. So `focus` was returning true for everything, and an earlier
        // `isEnabled` guard on the widget never even ran, because the cast to
        // `Control` failed on the wrapper.
        //
        // That made the one answer this protocol has to get right -- did the
        // widget take the focus -- always yes, which makes every reader of
        // `@FocusState` wrong about where the keyboard is.
        //
        // AppKit refuses the identical case and says so: its `responder(in:)`
        // falls back to the widget, and handing that wrapper to
        // `makeFirstResponder` is what its comment warns against.
        //
        // **要的是裡面那個控制項,絕不是那層 wrapper。** 本 backend 交出去的每一個 widget 都是一個
        // `Canvas`,而 `Canvas` 會無條件接受焦點:2026-09-16 加上儀器後,單次執行中
        // `focus(Canvas) enabled=not-a-Control took=true` 出現了 51 次,**包含那個被停用的按鈕**。
        // 於是 `focus` 對任何東西都回傳 true,而先前那道加在 widget 上的 `isEnabled` 防護根本沒執行過,
        // 因為對 wrapper 的 `Control` 轉型失敗了。
        //
        // 那讓本協定唯一必須答對的答案——「該 widget 有沒有接受焦點」——永遠是「有」,而那會讓每一個
        // 讀取 `@FocusState` 的人對「鍵盤在哪裡」判斷錯誤。
        //
        // AppKit 拒絕的是完全相同的情形,而且它寫明了:它的 `responder(in:)` 會退回該 widget,
        // 而「把那層 wrapper 交給 `makeFirstResponder`」正是它的註解所警告的事。
        guard let target = Self.focusableControl(in: widget) else { return false }
        return (try? target.focus(.programmatic)) ?? false
    }

    /// The first control inside `widget` that can actually take the focus.
    ///
    /// **Enabled AND a tab stop.** `isEnabled` alone is not the whole question:
    /// a control can be enabled and still excluded from focus navigation, and
    /// granting focus to one would be the same false yes in a different shape.
    ///
    /// Returns `nil` rather than falling back to the widget. A wrapper that
    /// contains nothing focusable has not taken the focus, and saying so is the
    /// entire value of the `Bool` this protocol returns.
    ///
    /// `widget` 內部第一個**真的能接受焦點**的控制項。
    ///
    /// **必須同時是 enabled 且為 tab stop。** 只看 `isEnabled` 並不完整:一個控制項可以是啟用的、
    /// 卻仍被排除在焦點導覽之外,而把焦點給它會是同一個「假的 yes」、只是換了個形狀。
    ///
    /// 找不到時回傳 `nil`,而**不是**退回那個 widget。一個內部沒有任何可聚焦物的 wrapper,
    /// 並沒有接受焦點;而說出這件事,正是本協定回傳那個 `Bool` 的全部價值。
    private static func focusableControl(in element: FrameworkElement) -> Control? {
        if let control = element as? Control, control.isEnabled, control.isTabStop {
            return control
        }
        let count = VisualTreeHelper.getChildrenCount(element)
        for index in 0..<count {
            guard
                let child = VisualTreeHelper.getChild(element, index) as? FrameworkElement
            else { continue }
            if let found = focusableControl(in: child) { return found }
        }
        return nil
    }

    /// Moves the focus off this widget by giving it to the root.
    ///
    /// **WinUI has no "unfocus".** Focus is a position, not a flag: something is
    /// always focused, so removing it from here means putting it somewhere
    /// harmless. The window's content is that somewhere -- the same choice
    /// AppKit's version makes when it hands the first-responder status back to
    /// the window.
    ///
    /// Guarded on `isFocused` so this cannot steal the focus from an unrelated
    /// control. Without the guard, every layout pass that calls `unfocus` on a
    /// widget which never had the focus would move it off whatever did.
    ///
    /// 把焦點移出這個 widget,做法是把它交給 root。
    ///
    /// **WinUI 沒有「取消聚焦」這個動作。** 焦點是一個**位置**、不是一個旗標:總是有某個東西被聚焦,
    /// 因此「把焦點從這裡移走」意謂著「把它放到某個無害的地方」。視窗的內容就是那個地方——與 AppKit
    /// 版本把 first responder 交還給視窗,是同一個選擇。
    ///
    /// 以 `isFocused` 作為前置條件,使這個呼叫不可能從一個不相干的控制項手上偷走焦點。少了這個防護,
    /// 每一次對「本來就沒有焦點的 widget」呼叫 `unfocus` 的 layout pass,都會把焦點從真正持有它的
    /// 那個東西上移開。
    public func unfocus(_ widget: Widget) {
        guard isFocused(widget), let root = widget.xamlRoot?.content else { return }
        _ = try? root.focus(.programmatic)
    }

    /// Whether this widget, or anything inside it, currently holds the focus.
    ///
    /// **Descendants count, and that is not a convenience.** A `TextField` in
    /// this backend is a `TextBox` inside a wrapper, and it is the inner control
    /// that WinUI focuses. Comparing only the widget itself would report `false`
    /// for a text field the user is typing into.
    ///
    /// Scoped to the widget's own `xamlRoot`. The parameterless
    /// `getFocusedElement()` answers for whichever root WinUI considers current,
    /// which in an app with two windows is not necessarily this widget's.
    ///
    /// 這個 widget——或它內部的任何東西——目前是否持有焦點。
    ///
    /// **後代也算,而那不是為了方便。** 本 backend 的 `TextField` 是一個包在 wrapper 裡的 `TextBox`,
    /// 而 WinUI 聚焦的是**內層**那個控制項。若只比對 widget 自身,對於使用者正在輸入的文字欄位,
    /// 會回報 `false`。
    ///
    /// 以該 widget 自己的 `xamlRoot` 為範圍。不帶參數的 `getFocusedElement()` 回答的是「WinUI 認為
    /// 目前是哪一個 root」,而在一個有兩個視窗的 app 中,那不必然是這個 widget 的 root。
    public func isFocused(_ widget: Widget) -> Bool {
        guard let root = widget.xamlRoot else { return false }
        guard let focused = FocusManager.getFocusedElement(root) as? DependencyObject else {
            return false
        }
        var current: DependencyObject? = focused
        while let element = current {
            if let element = element as? Widget, element === widget { return true }
            current = (element as? FrameworkElement)?.parent
        }
        return false
    }

    /// Reports focus in and out through `gotFocus` and `lostFocus`.
    ///
    /// **Both are routed events, so they fire for descendants too**, which is
    /// what makes them agree with ``isFocused(_:)`` above: the inner `TextBox`
    /// getting the focus raises `gotFocus` on the wrapper as well.
    ///
    /// The handler is stored and the subscription made once. This is called from
    /// `computeLayout`, so it runs on every frame -- subscribing each time would
    /// add a handler per frame, which is the shape this backend's slider hit as
    /// `began=5` and the shape the lazy-row container handler is guarded against.
    ///
    /// 透過 `gotFocus` 與 `lostFocus` 回報焦點的進出。
    ///
    /// **兩者都是 routed event,因此後代也會觸發它們**——而那正是它們與上方 ``isFocused(_:)`` 一致的
    /// 原因:內層的 `TextBox` 取得焦點時,`gotFocus` 也會在 wrapper 上被引發。
    ///
    /// handler 會被**存起來**,而訂閱只做一次。本方法由 `computeLayout` 呼叫,因此每一幀都會跑
    /// ——若每次都訂閱,就會變成每幀多掛一個 handler,那正是本 backend 的 slider 撞上的 `began=5`
    /// 形狀,也正是 lazy-row 的容器 handler 所防的那一個。
    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        let key = ObjectIdentifier(widget)
        internalState.focusChangeHandlers[key] = handler
        guard !internalState.widgetsWithFocusSubscription.contains(key) else { return }
        internalState.widgetsWithFocusSubscription.insert(key)

        widget.gotFocus.addHandler { [weak internalState] _, _ in
            internalState?.focusChangeHandlers[key]?(true)
        }
        widget.lostFocus.addHandler { [weak internalState] _, _ in
            internalState?.focusChangeHandlers[key]?(false)
        }
    }
}
