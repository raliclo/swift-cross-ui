extension View {
    /// Sets the style of toggles contained within this view.
    ///
    /// - Parameter toggleStyle: The new toggle style.
    public func toggleStyle(_ toggleStyle: any ToggleStyle) -> some View {
        return EnvironmentModifier(self) { environment in
            // Unlike the date picker's, this modifier does not refuse an
            // unsupported style: a backend missing `Switches` draws the switch
            // arm anyway and fails at that view's own `@CastBackend`, which is a
            // hard abort naming the missing feature. That is loud already.
            //
            // 與日期選擇器的 modifier 不同，此處不會拒絕不支援的樣式：若某個 backend 缺少
            // `Switches`，它仍會走 switch 分支，並在該 view 自己的 `@CastBackend` 處失敗——那是一次
            // 會指名缺少哪個功能的硬性中止，本來就夠大聲了。
            return environment.with(\.toggleStyle, toggleStyle)
        }
    }

    /// Sets the active background color of button-style toggles in this view.
    ///
    /// - Parameter color: The background color used while the toggle is on.
    public func toggleColor(_ color: Color?) -> some View {
        return EnvironmentModifier(self) { environment in
            return environment.with(\.toggleColor, color)
        }
    }
}
