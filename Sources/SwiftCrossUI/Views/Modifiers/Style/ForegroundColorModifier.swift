extension View {
    /// Sets the color of the foreground elements displayed by this view.
    ///
    /// Replaces a gradient an outer ``View/foregroundStyle(_:)-generic`` set.
    /// 取代外層 ``View/foregroundStyle(_:)-generic`` 設定的漸層。
    ///
    /// - Parameter color: The new foreground color.
    public func foregroundColor(_ color: Color) -> some View {
        return EnvironmentModifier(self) { environment in
            return environment.with(\.foregroundColor, color).with(\.foregroundShapeStyle, nil)
        }
    }
}
