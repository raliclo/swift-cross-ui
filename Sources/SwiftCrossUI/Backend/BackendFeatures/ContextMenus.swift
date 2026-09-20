extension BackendFeatures {
    /// A menu raised by a secondary click on a view.
    ///
    /// **``ApplicationMenus`` and ``PopoverMenus`` are not this, and the
    /// difference is what raises the menu.** An application menu lives in the
    /// menu bar. A popover menu belongs to a button and opens when that button
    /// is pressed. This one belongs to arbitrary content and opens on a
    /// secondary click anywhere in it -- which is what a view drawing its own
    /// content needs, and what SoftPCB's `plan.md` §10.7 lists as gap 7:
    /// *no `contextMenu`; `Menu` exists but is tied to the menu bar.*
    ///
    /// **The menu is a ``ResolvedMenu``, the same value ``PopoverMenus`` takes.**
    /// A second menu representation would be a second place for a submenu, a
    /// toggle or a separator to mean something slightly different, and the
    /// backends already know how to turn this one into their own menus.
    ///
    /// **Conformance-checked, like ``Cursors`` and ``KeyEvents``.**
    ///
    /// 由次要點擊(右鍵)在一個 view 上叫出來的選單。
    ///
    /// **``ApplicationMenus`` 與 ``PopoverMenus`` 都不是這個,差別在於「是什麼叫出那個選單」。**
    /// application menu 住在選單列;popover menu 屬於某一顆按鈕,並在那顆按鈕被按下時開啟。
    /// 這一個屬於**任意內容**,並在其中任何地方被次要點擊時開啟——那正是一個自己畫自己內容的 view
    /// 所需要的,也正是 SoftPCB `plan.md` §10.7 所列的第 7 項缺口:
    /// *無 `contextMenu`;`Menu` 存在,但綁在選單列上。*
    ///
    /// **那個選單是一個 ``ResolvedMenu``,與 ``PopoverMenus`` 所取的是同一個值。** 第二套選單表示法,
    /// 等於多一個地方讓 submenu、toggle 或 separator 的意思產生些微差異;而各 backend 早已知道
    /// 怎麼把這一個轉成它們自己的選單。
    ///
    /// **採 conformance 檢查,與 ``Cursors``、``KeyEvents`` 相同。**
    @MainActor
    public protocol ContextMenus: Core {
        func createContextMenuTarget(wrapping child: Widget) -> Widget

        func updateContextMenuTarget(
            _ target: Widget,
            menu: ResolvedMenu,
            environment: EnvironmentValues
        )
    }
}
