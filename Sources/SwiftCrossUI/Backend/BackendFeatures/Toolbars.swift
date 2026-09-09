extension BackendFeatures {
    /// A row of controls in a window's own chrome.
    ///
    /// Takes a resolved ``ToolbarItem`` list rather than widgets, because not
    /// one of the five platforms hosts an arbitrary view tree in its toolbar --
    /// see ``ToolbarItem`` for the list of what each one actually is. A backend
    /// is expected to record, in its own implementation, how it mapped
    /// ``ToolbarItem/Placement`` onto whatever its platform has.
    ///
    /// 視窗自身外框上的一列控制項。
    ///
    /// 接收的是已解析的 ``ToolbarItem`` 清單而非 widget,因為五個平台沒有一個會在工具列中承載任意的
    /// view 樹——各平台實際上是什麼,見 ``ToolbarItem``。各 backend 應在自己的實作中記錄:它把
    /// ``ToolbarItem/Placement`` 對應到了該平台所擁有的什麼東西。
    @MainActor
    public protocol Toolbars<Window>: Core {
        /// Replaces the window's toolbar.
        ///
        /// An empty array removes it. That is the same call rather than a
        /// separate one because a view that stops asking for a toolbar and a
        /// view that never asked are the same state, and giving them two paths
        /// invites one of them to be forgotten.
        ///
        /// 取代該視窗的工具列。
        ///
        /// 空陣列即為移除。此處使用同一個呼叫而非另立一個,因為「一個不再要求工具列的 view」與
        /// 「一個從未要求過的 view」處於相同狀態,而給它們兩條路徑,等於邀請其中一條被遺忘。
        /// - Parameter title: What ``View/navigationTitle(_:)`` asked for, or
        ///   `nil` when the content asked for nothing.
        ///
        ///   **Not the same as the window's title, and the difference is the
        ///   whole reason this parameter exists.** `setTitle(ofWindow:to:)`
        ///   receives `preferences.navigationTitle ?? scene.title`, so a backend
        ///   reading it cannot tell "the content asked for this heading" from
        ///   "this is what the window is called". On macOS, GTK and Windows that
        ///   does not matter -- both belong in the title bar. On iOS and Android
        ///   it decides whether a bar appears at all, and showing every app's
        ///   scene title as a heading would put chrome on forty apps that never
        ///   asked for one.
        ///
        /// - Parameter title:``View/navigationTitle(_:)`` 所要求的內容,或在內容什麼都沒要求時為 `nil`。
        ///
        ///   **這與視窗的標題不是同一件事,而那個差別正是這個參數存在的全部理由。**
        ///   `setTitle(ofWindow:to:)` 收到的是 `preferences.navigationTitle ?? scene.title`,因此讀取它的
        ///   backend 無法分辨「內容要求了這個標題」與「這個視窗就叫這個名字」。在 macOS、GTK 與 Windows 上
        ///   那沒有差別——兩者都屬於標題列。而在 iOS 與 Android 上,它決定了那條列究竟該不該出現,
        ///   而把每一支 app 的 scene 標題都當成標題顯示,等於替四十支從未要求過外框的 app 加上外框。
        func setToolbar(ofWindow window: Window, to items: [ToolbarItem], title: String?)
    }
}
