extension View {
    /// Sets the style of lists contained within this view.
    ///
    /// New public API as of 2026-08-27. The environment entry existed before
    /// but was `@_spi(Backends)` and inert -- `NavigationSplitView` set it on
    /// its sidebar and no backend consulted it -- so there was nothing an
    /// application could usefully call.
    ///
    /// - Parameter style: The list style to use.
    ///
    /// ## See Also
    ///
    /// - ``ListStyle``
    ///
    /// 設定此 view 之下所有清單的樣式。
    ///
    /// 自 2026-08-27 起成為公開 API。該 environment 條目先前即已存在，但屬於 `@_spi(Backends)` 且是
    /// inert 的——`NavigationSplitView` 會在其側邊欄設定它，卻無任何 backend 查詢它——因此當時並不
    /// 存在一個「應用程式呼叫得有意義」的東西。
    public func listStyle(_ style: any ListStyle) -> some View {
        EnvironmentModifier(self) { environment in
            environment
                .with(\.listStyle, style)
                .with(\.backendListStyle, style._asBackendListStyle(backend: environment.backend))
        }
    }
}
