import CGtk

/// A button that shows a popover when clicked, drawing its own disclosure
/// arrow.
///
/// This is GTK's shape for what SwiftUI calls a compact input: a small button
/// that opens a pop-up holding the real control. Unlike a plain `GtkButton`
/// with a hand-attached popover, `GtkMenuButton` handles the toggling,
/// keyboard activation and accessibility relationship itself.
open class MenuButton: Widget {
    public convenience init() {
        self.init(
            gtk_menu_button_new()
        )
    }

    /// The popover shown when the button is clicked.
    ///
    /// Kept on the Swift side as well as handed to GTK. `gtk_menu_button_set_popover`
    /// takes ownership of the GObject, but nothing there keeps the Swift
    /// wrapper alive, and the wrapper is what owns the signal handlers of
    /// anything inside the popover.
    public private(set) var popover: Popover?

    public func setPopover(_ popover: Popover?) {
        gtk_menu_button_set_popover(opaquePointer, popover?.widgetPointer)
        self.popover = popover
    }

    /// The text drawn on the button, next to the disclosure arrow.
    ///
    /// Setting this replaces any child set with ``setChild(_:)``, and vice
    /// versa: measured on GTK 4.22, `gtk_menu_button_get_label` returns NULL
    /// after a child has been set.
    public var label: String? {
        get {
            gtk_menu_button_get_label(opaquePointer).map(String.init(cString:))
        }
        set {
            gtk_menu_button_set_label(opaquePointer, newValue)
        }
    }

    /// Whether the popover is currently open.
    @GObjectProperty(named: "active") public var active: Bool
}
