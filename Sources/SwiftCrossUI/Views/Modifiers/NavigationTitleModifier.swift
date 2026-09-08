extension View {
    /// Sets the title of the enclosing window.
    ///
    /// Built on the existing ``PreferenceValues`` machinery and applied through
    /// ``BackendFeatures/CoreWindowing/setTitle(ofWindow:to:)``, which is part
    /// of ``BackendFeatures/Core``. **No backend gains a new requirement from
    /// this modifier**, so it works on all five shipped backends -- GtkBackend,
    /// WinUIBackend, AppKitBackend, UIKitBackend, AndroidBackend -- the moment
    /// it compiles. That is the same property that decided the order of the
    /// parity work it was added alongside. See ``View/safeAreaInset(edge:spacing:content:)``.
    ///
    /// **Where the title actually goes, per platform.** SwiftUI puts it in the
    /// navigation bar on iOS and in the *window* title on macOS. There is no
    /// third answer available here: `setTitle(ofWindow:to:)` is the one title
    /// API every backend has, so the window is where this writes on all of
    /// them. On Android and iOS, where the platform window has no visible
    /// title bar, the value still reaches the backend and still names the
    /// window for the system (task switcher, accessibility); it is not
    /// discarded, and it is not drawn on screen either.
    ///
    /// **What this does *not* yet do, stated so it is not met as a surprise:**
    /// it does not retitle ``NavigationStack``'s back bar. That bar is a
    /// sibling *above* the destination in the same layout pass, and a
    /// preference travels upward -- the title of the view being pushed is not
    /// known until after the bar it would label has already been laid out.
    /// Closing that gap needs a value that survives between passes, not another
    /// preference, and it is deliberately not smuggled in here. The bar's
    /// label therefore remains SwiftUI's fallback, "Back".
    ///
    /// - Parameter title: The title to give the enclosing window.
    /// - Returns: A view with the ``PreferenceValues/navigationTitle``
    ///   preference set.
    ///
    /// 設定外層視窗的標題。
    ///
    /// 建構於既有的 ``PreferenceValues`` 機制之上，並透過
    /// ``BackendFeatures/CoreWindowing/setTitle(ofWindow:to:)`` 套用；後者屬於
    /// ``BackendFeatures/Core``。**沒有任何 backend 因這個 modifier 而多出新的要求**，因此它一旦
    /// 編譯通過，就在五個已發布的 backend 上同時成立——GtkBackend、WinUIBackend、AppKitBackend、
    /// UIKitBackend、AndroidBackend。這正是與它一同進行的那批 parity 工作之所以如此排序的性質。
    /// 見 ``View/safeAreaInset(edge:spacing:content:)``。
    ///
    /// **標題實際落在哪裡，依平台而定。** SwiftUI 在 iOS 上把它放進導覽列，在 macOS 上放進**視窗**
    /// 標題。此處沒有第三種答案可選：`setTitle(ofWindow:to:)` 是每個 backend 都具備的唯一標題 API，
    /// 因此在所有 backend 上它都寫入視窗。在 Android 與 iOS 上，平台視窗沒有可見的標題列，該值仍會
    /// 送達 backend，仍會為系統（工作切換器、輔助使用）命名該視窗；它既沒有被丟棄，也不會被畫在
    /// 螢幕上。
    ///
    /// **它目前**不**做什麼，寫在此處以免日後撞見：** 它不會替 ``NavigationStack`` 的返回列改標題。
    /// 那條列在同一次版面計算中是位於 destination **上方**的兄弟節點，而 preference 是向上傳遞的
    /// ——被推入的 view 的標題，要到那條本該標示它的列已完成版面之後才會為人所知。要補上這個缺口，
    /// 需要的是一個能跨越多次計算而存續的值，而不是再一個 preference，因此此處刻意不夾帶。該列的
    /// 標籤因而維持 SwiftUI 的後備文字「Back」。
    ///
    /// - Parameter title: 要給予外層視窗的標題。
    /// - Returns: 一個已設定 ``PreferenceValues/navigationTitle`` preference 的 view。
    public func navigationTitle(_ title: String) -> some View {
        preference(key: \.navigationTitle, value: title)
    }
}
