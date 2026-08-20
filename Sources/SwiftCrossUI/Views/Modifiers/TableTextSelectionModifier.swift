extension View {
    /// Lets the user select and copy the text in any ``Table`` inside this view.
    ///
    /// Off by default. Selection is not free: it gives cells a caret and a
    /// highlight, makes them take keyboard focus, and changes what a drag inside
    /// the table does. A table used as a read-only readout should not acquire
    /// any of that because a different table elsewhere wanted copyable values,
    /// so this is opt-in per table rather than a global default.
    ///
    /// What becomes selectable is the text a cell draws, not the cell as an
    /// object — a cell is an arbitrary view, and a table of buttons gains
    /// nothing from this.
    ///
    /// A backend that cannot offer selection ignores it. Refusing to draw the
    /// table would be worse than drawing it unselectable.
    ///
    /// - Parameter isEnabled: Whether the text can be selected and copied.
    public func tableTextSelection(_ isEnabled: Bool = true) -> some View {
        EnvironmentModifier(self) { environment in
            environment.with(\.tableTextSelection, isEnabled)
        }
    }
}
