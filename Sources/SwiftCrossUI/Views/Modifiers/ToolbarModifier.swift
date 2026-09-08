extension View {
    /// Puts `items` in the toolbar of the window this view is in.
    ///
    /// The items travel up as a preference and the window applies them, which
    /// is how ``View/navigationTitle(_:)`` reaches the window too. Two views
    /// each contributing an item both get one: unlike a title, a toolbar is the
    /// sum of what the content asked for.
    ///
    /// 把 `items` 放進本 view 所在視窗的工具列。
    ///
    /// 這些項目以 preference 的形式向上傳遞,再由視窗套用——``View/navigationTitle(_:)`` 抵達視窗的
    /// 方式也是如此。兩個各自貢獻一個項目的 view 會各得到一個:與標題不同,工具列是「內容所要求
    /// 之物的總和」。
    public func toolbar(_ items: [ToolbarItem]) -> some View {
        preference(key: \.toolbarItems, value: items)
    }

    /// The single-item spelling, for the common case.
    /// 單一項目的寫法,供最常見的情況使用。
    public func toolbar(_ item: ToolbarItem) -> some View {
        toolbar([item])
    }
}
