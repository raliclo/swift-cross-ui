extension BackendFeatures {
    /// Renders the application's menus from their layout, with the standard
    /// commands as the platform's own items.
    ///
    /// For a backend whose platform HAS those items -- AppKit, where Undo is a
    /// responder-chain action the system enables and disables. A backend without
    /// this gets the layout as plain menus through
    /// ``ApplicationMenus/setApplicationMenu(_:environment:)`` instead.
    /// 依版面畫出應用程式選單，標準指令用平台自己的項目。給平台**本來就有**那些項目的 backend——AppKit,
    /// 那裡的 Undo 是由系統啟用與停用的 responder chain 動作。沒有這個協定的 backend 會改經由
    /// ``ApplicationMenus/setApplicationMenu(_:environment:)`` 收到轉成一般選單的版面。
    @MainActor
    public protocol CommandLayouts: Core {
        func setApplicationCommands(_ layout: CommandLayout, environment: EnvironmentValues)
    }

    /// The standard commands, on a backend whose menus this framework builds.
    ///
    /// With the standard menus on (``Scene/enableMenu(_:)``), each command the
    /// backend says it has becomes an item that calls
    /// ``performStandardCommand(_:)``. One it does not have is left out rather
    /// than shown and dead.
    /// 選單由本框架建出的 backend 上的標準指令。標準選單打開時(``Scene/enableMenu(_:)``),backend 表示有的每個
    /// 指令都成為一個呼叫 ``performStandardCommand(_:)`` 的項目;沒有的就不放，而不是顯示出來卻沒有作用。
    @MainActor
    public protocol StandardCommands: Core {
        func hasStandardCommand(_ command: StandardCommand) -> Bool
        func performStandardCommand(_ command: StandardCommand)
        /// Whether the platform shows the standard menus even when the app has not
        /// turned them on: macOS always has a menu bar with an app menu, Quit in it.
        /// When `true` the framework hands over the default items as if
        /// ``Scene/enableMenu(_:)`` had been called, so the app's own menus do not
        /// take the place of the system's and leave no Quit (GtkBackend on macOS,
        /// P71 and P92, 2026-10-23).
        /// 即使 app 沒有打開標準選單，平台是否仍會顯示它們:macOS 一定有選單列，其中的 app 選單裡有 Quit。為 `true`
        /// 時，框架如同呼叫過 ``Scene/enableMenu(_:)`` 一樣交出預設項目，app 自己的選單才不會取代系統的、讓 Quit
        /// 消失(macOS 上的 GtkBackend,P71 與 P92,2026-10-23)。
        var showsStandardMenusByDefault: Bool { get }
    }
}

extension BackendFeatures.StandardCommands {
    /// Whether the platform shows the standard menus whether or not the app turns
    /// them on. `false` unless a backend says otherwise.
    /// 平台是否不論 app 有沒有打開，都會顯示標準選單。除非 backend 另有說明，否則為 `false`。
    public var showsStandardMenusByDefault: Bool { false }
}
