extension BackendFeatures {
    /// A wrapper that lets a view which is not a control hold the keyboard focus.
    ///
    /// ``FocusableViews`` moves the focus and reports it; it cannot make a plain
    /// view able to take it. A `Text` or a `Color` is not a Tab stop on any of the
    /// five platforms, a click on it leaves the focus where it was, and
    /// ``FocusableViews/focus(_:)`` on it is refused. This is the missing half:
    /// the target is a Tab stop, takes the focus when pressed, and is what
    /// `.focused` and `.onKeyPress` then talk to.
    ///
    /// | | AppKit | UIKit | GTK | Android |
    /// | --- | --- | --- | --- | --- |
    /// | able to hold focus | `acceptsFirstResponder` | `canBecomeFirstResponder`, `canBecomeFocused` | `gtk_widget_set_focusable` | `isFocusable`, `isFocusableInTouchMode` |
    /// | a press focuses | `mouseDown` | a tap recognizer that cancels nothing | `GestureClick` | a touch seen in `dispatchTouchEvent` |
    /// | Tab leaves it | `selectKeyView(following:)` | the next stop, found by the view | `gtk_widget_child_focus` | the view root's own focus search |
    ///
    /// **The target never takes a press from its child**: it only watches one go by.
    ///
    /// **Tab is the target's, every other key is the app's.** `.onKeyPress` has no
    /// way to decline a key, so a key target around a focused view would swallow
    /// Tab and the focus could never leave by keyboard.
    ///
    /// 讓一個不是控制項的 view 能持有鍵盤焦點的包裝。``FocusableViews`` 能移動並回報焦點，卻無法讓普通的 view
    /// 有能力接受它:`Text` 或 `Color` 在五個平台上都不是 Tab 停駐點，點它焦點不會動，對它呼叫
    /// ``FocusableViews/focus(_:)`` 會被拒絕。這裡補上的是另一半:target 是 Tab 停駐點、被按下時取得焦點，
    /// 之後 `.focused` 與 `.onKeyPress` 對話的對象就是它。target 絕不搶走子 view 的按壓，只是看著它經過。
    /// Tab 歸 target、其餘按鍵歸 app:`.onKeyPress` 無法拒收按鍵，所以包在已聚焦 view 外面的按鍵 target 會把
    /// Tab 吞掉，焦點就再也無法用鍵盤離開。
    @MainActor
    public protocol FocusableTargets: Core {
        /// Wraps `child` in a view that can hold the focus.
        /// 把 `child` 包進一個能持有焦點的 view。
        func createFocusableTarget(wrapping child: Widget) -> Widget

        /// Whether the target can hold the focus now. A target that stops being
        /// focusable, or is disabled, gives the focus up if it has it.
        /// target 現在能否持有焦點。不再可聚焦或被停用的 target,若正持有焦點就放掉。
        func updateFocusableTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            isFocusable: Bool
        )
    }
}
