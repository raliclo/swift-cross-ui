extension BackendFeatures {
    /// Backend methods for sliders.
    ///
    /// These are used by ``Slider``.
    @MainActor
    public protocol Sliders: Core {
        /// Creates a slider for choosing a numerical value from a range. Predominantly used
        /// by ``Slider``.
        func createSlider() -> Widget

        /// Sets the minimum and maximum selectable value of a slider, the number of
        /// decimal places displayed by the slider, and the slider's change handler.
        ///
        /// - Parameters:
        ///   - slider: The slider to update.
        ///
        /// `onEditingChanged` is called with `true` when the user begins
        /// dragging and `false` when they let go, matching SwiftUI. It is NOT
        /// derived from `onChange`: a value that stops arriving is
        /// indistinguishable from a user who has paused, and a slider driven
        /// from code changes value without anyone editing anything.
        ///
        /// Every platform reports this directly, which is why the requirement
        /// takes it rather than guessing: `UISlider` has touch-down and
        /// touch-up control events, Android's `SeekBar` has
        /// `onStartTrackingTouch` and `onStopTrackingTouch` by those names, GTK
        /// has a `GestureClick`'s pressed and released, WinUI has pointer
        /// pressed and capture-lost, and AppKit's `NSSlider` sends its action
        /// with the causing event still available on `NSApp.currentEvent`.
        ///
        /// `onEditingChanged` 會在使用者**開始**拖曳時以 `true` 呼叫、**放開**時以 `false` 呼叫，
        /// 與 SwiftUI 一致。它**不是**從 `onChange` 推導出來的：一個「不再送來的值」與「使用者只是
        /// 暫停了」無從分辨，而一個由程式驅動的滑桿會在沒有任何人編輯的情況下改變數值。
        ///
        /// 每一個平台都直接回報這件事，這正是本 requirement 選擇「收下它」而非「用猜的」的理由：
        /// `UISlider` 有 touch-down 與 touch-up 控制事件、Android 的 `SeekBar` 就叫
        /// `onStartTrackingTouch` 與 `onStopTrackingTouch`、GTK 有 `GestureClick` 的 pressed 與
        /// released、WinUI 有指標按下與失去捕捉，而 AppKit 的 `NSSlider` 在送出 action 時，
        /// 造成它的事件仍留在 `NSApp.currentEvent` 上。
        ///   - minimum: The minimum selectable value of the slider (inclusive).
        ///   - maximum: The maximum selectable value of the slider (inclusive).
        ///   - decimalPlaces: The number of decimal places displayed by the slider.
        ///   - environment: The current environment.
        ///   - onChange: The action to perform when the slider's value changes.
        ///     This replaces any existing change handlers.
        func updateSlider(
            _ slider: Widget,
            minimum: Double,
            maximum: Double,
            decimalPlaces: Int,
            environment: EnvironmentValues,
            onChange: @escaping (Double) -> Void,
            onEditingChanged: @escaping (Bool) -> Void
        )

        /// Sets the selected value of a slider.
        ///
        /// - Parameters:
        ///   - slider: The slider to set the value of.
        ///   - value: The new value.
        func setValue(ofSlider slider: Widget, to value: Double)
    }
}
