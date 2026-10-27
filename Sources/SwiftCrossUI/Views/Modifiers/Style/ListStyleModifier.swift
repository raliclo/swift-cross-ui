extension View {
    /// Sets the style of lists contained within this view.
    ///
    /// - Parameter style: The list style to use.
    ///
    /// ## See Also
    ///
    /// - ``ListStyle``
    ///
    /// 設定此 view 之下所有清單的樣式。
    public func listStyle(_ style: any ListStyle) -> some View {
        EnvironmentModifier(self) { environment in
            environment
                .with(\.listStyle, style)
                .with(\.backendListStyle, style._asBackendListStyle(backend: environment.backend))
        }
    }
}
