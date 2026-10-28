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
    /// navigation bar on iOS and in the *window* title on macOS.
    /// `setTitle(ofWindow:to:)` is the title API every backend has, so the
    /// window is where this writes on all of them, and it names the window for
    /// the system (task switcher, accessibility). On iOS and Android, where the
    /// platform window has no visible title bar, the same value also reaches
    /// the backend's own navigation bar through
    /// `setToolbar(ofWindow:to:title:)`: UIKitBackend's `UINavigationBar`, and
    /// AndroidBackend's title row above the content.
    ///
    /// **``NavigationStack``'s back control.** The title of a screen inside a
    /// stack also becomes the label of the control that returns to it: one
    /// level down the back bar reads "‹ " and the root view's title, further
    /// down the previous destination's, and SwiftUI's fallback "Back" when
    /// that screen has no title. The stack records each screen's title when the
    /// screen is committed and reads it when the next screen is pushed on top
    /// -- the title is a preference travelling upward and cannot reach the bar
    /// above it in the same pass. See ``NavigationStack``.
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
    /// 標題。`setTitle(ofWindow:to:)` 是每個 backend 都具備的標題 API,因此在所有 backend 上它都寫入視窗，並為系統
    /// (工作切換器、輔助使用)命名該視窗。在 iOS 與 Android 上，平台視窗沒有可見的標題列，同一個值也會經由
    /// `setToolbar(ofWindow:to:title:)` 送到 backend 自己的導覽列:UIKitBackend 的 `UINavigationBar`,以及
    /// AndroidBackend 內容上方的標題列。
    ///
    /// **``NavigationStack`` 的返回控制項。** 位於堆疊中的畫面，其標題也會成為返回該畫面之控制項的標籤:推入一層後，
    /// 返回列顯示「‹ 」加上根 view 的標題，更深時顯示前一個 destination 的標題，而該畫面沒有標題時顯示 SwiftUI 的後備
    /// 文字「Back」。堆疊在每個畫面 commit 時記下它的標題，並在下一個畫面被推到它上面時讀取——標題是向上傳遞的
    /// preference,在同一次計算中無法抵達位於其上方的那條列。見 ``NavigationStack``。
    ///
    /// - Parameter title: 要給予外層視窗的標題。
    /// - Returns: 一個已設定 ``PreferenceValues/navigationTitle`` preference 的 view。
    public func navigationTitle(_ title: String) -> some View {
        preference(key: \.navigationTitle, value: title)
    }
}
