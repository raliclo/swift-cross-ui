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
    }
}
