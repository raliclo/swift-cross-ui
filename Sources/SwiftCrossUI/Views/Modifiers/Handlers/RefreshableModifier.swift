extension View {
    /// Adds an action to perform when the user pulls a surrounding scroll
    /// container down past its top.
    ///
    /// The action belongs to the nearest enclosing scroll container. Applying
    /// it where there is no scroll container has no effect -- there is nothing
    /// to pull -- and that is not an error, because a view is often written
    /// once and placed in a scroll view only on some platforms.
    ///
    /// It REPLACES an outer `refreshable` rather than chaining with it, which
    /// is where this differs from ``View/onSubmit(perform:)``. See
    /// ``EnvironmentValues/onRefresh``.
    ///
    /// - Parameter action: The action to perform.
    ///
    /// 加入一個動作:當使用者把外圍的 scroll container 從頂端往下拉時執行它。
    ///
    /// 該動作屬於最接近的那個外圍 scroll container。套用在沒有 scroll container 之處不會有任何效果
    /// ——沒有東西可拉——而那不是錯誤,因為一個 view 常常只寫一次,卻只在部分平台上被放進捲動視圖裡。
    ///
    /// 它會**取代**外層的 `refreshable` 而非與之串接,而這正是它與 ``View/onSubmit(perform:)``
    /// 的差別所在。見 ``EnvironmentValues/onRefresh``。
    public func refreshable(action: @escaping @MainActor @Sendable () -> Void) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.onRefresh, action)
        }
    }
}
