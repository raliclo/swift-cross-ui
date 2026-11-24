extension BackendFeatures {
    // swiftlint:disable line_length
    /// Hides the focus ring of a widget, for ``View/focusEffectDisabled(_:)``.
    ///
    /// | AppKit | UIKit | GTK | Android | WinUI |
    /// | --- | --- | --- | --- | --- |
    /// | `focusRingType = .none` | `focusEffect = nil` (iOS 15) | a class whose CSS has no `outline` | `setDefaultFocusHighlightEnabled(false)` (API 26) | `UseSystemFocusVisuals = false` (not yet implemented, 2026-11-24) |
    ///
    /// **Called once per view-graph node, and only when the setting changes.**
    /// ``ViewGraphNode`` calls it for every node under a `.focusEffectDisabled`,
    /// so each node's own widget gets its own call. A backend applies it to that
    /// widget and to the native views the widget is made of (an `NSTextField`
    /// inside a container, a `GtkText` inside a `GtkEntry`), and stops at a view
    /// another node has been given: that node gets its own call, with its own
    /// setting, and `.focusEffectDisabled(false)` inside a disabled subtree is
    /// how an app turns the ring back on for one control.
    ///
    /// Restoring (`disabled == false`) puts back what the widget had, not a
    /// fixed value: a `.focusable()` target on AppKit draws an exterior ring
    /// that the default ring type would not.
    ///
    /// 為 ``View/focusEffectDisabled(_:)`` 隱藏 widget 的焦點環。**每個 view graph 節點呼叫一次，而且只在設定改變時。**
    /// ``ViewGraphNode`` 對 `.focusEffectDisabled` 之下的每個節點呼叫它，所以每個節點自己的 widget 各得到一次呼叫。backend
    /// 把它套用在該 widget 與組成它的原生 view 上(容器內的 `NSTextField`、`GtkEntry` 內的 `GtkText`),遇到已交給另一個
    /// 節點的 view 就停下:那個節點會以自己的設定得到自己的呼叫，而在被停用的子樹內寫 `.focusEffectDisabled(false)`,
    /// 就是 app 替單一控制項把焦點環開回來的方式。還原(`disabled == false`)放回的是 widget 原本的值，不是固定值:
    /// AppKit 上 `.focusable()` 的 target 畫的是外側焦點環，預設的焦點環類型不會這樣畫。
    @MainActor
    public protocol FocusEffects: Core {
    // swiftlint:enable line_length
        /// Hides (`true`) or restores (`false`) the focus ring of `widget` and
        /// the native views it is made of.
        /// 隱藏(`true`)或還原(`false`)`widget` 及組成它的原生 view 的焦點環。
        func setFocusEffectDisabled(_ disabled: Bool, on widget: Widget)
    }

    // swiftlint:disable line_length
    /// A container whose contents cannot take the keyboard focus, for
    /// ``View/focusDisabled(_:)``.
    ///
    /// | AppKit | UIKit | GTK | Android | WinUI |
    /// | --- | --- | --- | --- | --- |
    /// | the window refuses `makeFirstResponder`, and `selectKeyView` steps over | text fields refuse to begin editing, `.focusable()` targets refuse first responder, and their Tab skips | `can-focus = false` on the container | `FOCUS_BLOCK_DESCENDANTS` | not yet implemented (2026-11-24) |
    ///
    /// The container is one ``Core`` container (`createContainer`) holding the
    /// modified view; the core lays it out. This protocol only marks it.
    ///
    /// **All three ways in are closed, not only Tab**: Tab and Shift-Tab step
    /// over the subtree, a press on a control inside it does not focus it, and
    /// `.focused` on a view inside it is refused and written back as not
    /// focused. A subtree that Tab skipped but a click still focused would be a
    /// different feature on each platform -- GTK's `can-focus` and Android's
    /// `FOCUS_BLOCK_DESCENDANTS` are already all-or-nothing -- so the other
    /// backends match them.
    ///
    /// Marking a container that holds the focus moves the focus out.
    ///
    /// 一個內容無法取得鍵盤焦點的容器，給 ``View/focusDisabled(_:)`` 用。容器是一個 ``Core`` 容器
    /// (`createContainer`),裝著被修飾的 view,由 core 排版;本協定只負責標記它。**三條進入的路都關上，不只 Tab**:
    /// Tab 與 Shift-Tab 跨過整個子樹，按下其中的控制項不會讓它取得焦點，對其中的 view 用 `.focused` 會被拒絕並寫回
    /// 未聚焦。「Tab 跳過、點擊卻仍能聚焦」在每個平台上會是不同的功能——GTK 的 `can-focus` 與 Android 的
    /// `FOCUS_BLOCK_DESCENDANTS` 本來就是全有或全無——所以其他 backend 與它們一致。標記一個正持有焦點的容器會把焦點移出去。
    @MainActor
    public protocol FocusDisabledContainers: Core {
    // swiftlint:enable line_length
        /// Marks (`true`) or unmarks (`false`) a container made by
        /// `createContainer` as one whose contents cannot take the focus.
        /// 把一個由 `createContainer` 建立的容器標記(`true`)或取消標記(`false`)為內容無法取得焦點。
        func setFocusDisabled(_ disabled: Bool, onContainer container: Widget)
    }
}
