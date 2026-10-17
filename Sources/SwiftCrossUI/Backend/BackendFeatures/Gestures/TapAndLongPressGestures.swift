extension BackendFeatures {
    /// A tap and a long press on the same view, told apart by the toolkit: a
    /// press released before the long-press delay is a tap (reported on
    /// release), a press held past it is a long press (reported once, when it
    /// is recognised) and is then NOT also a tap. What
    /// ``View/onTapAndLongPressGesture(onTap:onLongPress:)`` asks for.
    ///
    /// **A separate protocol rather than two nested ``TapGestures`` targets**,
    /// because nesting does not give this on the shipped backends: AppKit's
    /// outer target view covers the inner one, so the inner recogniser never
    /// sees the press; GTK's `.primary` fires on press, so every long press
    /// would also be a tap. The distinction has to be made where both
    /// recognisers live -- UIKit's and AppKit's `require(toFail:)`, Android's
    /// consumed long click, a shared press record on GTK and WinUI.
    ///
    /// The five shipped backends -- GtkBackend, WinUIBackend, AppKitBackend,
    /// UIKitBackend, AndroidBackend -- all conform. Others fall back to the
    /// tap alone and say so once.
    ///
    /// 同一個 view 上的點按與長按，由 toolkit 區分：在長按延遲之前放開的是點按(放開時回報)，按超過延遲的是
    /// 長按(辨識成立時回報一次)，而且之後**不會**再算成點按。這正是
    /// ``View/onTapAndLongPressGesture(onTap:onLongPress:)`` 所要的。**獨立成一個協定，而不是巢狀兩個
    /// ``TapGestures`` target**,因為巢狀在已發布的 backend 上做不到：AppKit 外層的 target view 蓋住內層，
    /// 內層辨識器收不到按壓;GTK 的 `.primary` 在按下時就觸發，每次長按也會變成一次點按。區分必須在兩個辨識器
    /// 共處的地方完成。五個已發布的 backend 全部 conform;其他 backend 退回只有點按，並說明一次。
    @MainActor
    public protocol TapAndLongPressGestures: TapGestures {
        /// Wraps a view in a target that can tell a tap from a long press.
        /// Backends that need no wrapper may return the child.
        /// 把 view 包進一個能區分點按與長按的 target。不需要包裝的 backend 可以直接回傳 child。
        func createTapAndLongPressTarget(wrapping child: Widget) -> Widget

        /// Replaces both actions. Called on every update, so it must replace
        /// the handlers rather than add recognisers. When the environment is
        /// disabled neither action may run.
        /// 替換兩個動作。每次更新都會呼叫，所以必須替換 handler 而不是再加辨識器。環境為停用時兩個動作都不可執行。
        func updateTapAndLongPressTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onTap: @escaping () -> Void,
            onLongPress: @escaping () -> Void
        )
    }
}
