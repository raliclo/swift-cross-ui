import SwiftCrossUI
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
        (try? widget.focus(.programmatic)) ?? false
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
