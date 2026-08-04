extension View {
    /// Sets the style of toggles contained within this view.
    ///
    /// - Parameter toggleStyle: The new toggle style.
    public func toggleStyle(_ toggleStyle: ToggleStyle) -> some View {
        return EnvironmentModifier(self) { environment in
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
