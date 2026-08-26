import CGtk

extension Popover {
    /// Sets the widget shown inside the popover.
    ///
    /// The caller must keep its own reference to `child`: GTK owns the
    /// GObject from here on, but the Swift wrapper owns the child's signal
    /// handlers, and those go away with it.
    public func setChild(_ child: Widget?) {
        gtk_popover_set_child(castedPointer(), child?.widgetPointer)
    }

    /// Closes the popover, as clicking outside it or pressing Escape does.
    public func popDown() {
        gtk_popover_popdown(castedPointer())
    }
}
