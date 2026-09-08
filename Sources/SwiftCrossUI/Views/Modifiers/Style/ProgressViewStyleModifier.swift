extension View {
    /// Sets the style ``ProgressView`` uses inside this view.
    ///
    /// Carried in the environment like every other style here, so it reaches a
    /// `ProgressView` nested anywhere below without being threaded through.
    ///
    /// 設定本 view 之內 ``ProgressView`` 所使用的樣式。
    ///
    /// 與此處其他樣式一樣以 environment 攜帶，因此它會抵達下方任何深度的 `ProgressView`，而不必逐層
    /// 傳遞。
    public func progressViewStyle(_ style: any ProgressViewStyle) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.progressViewStyle, style)
        }
    }
}
