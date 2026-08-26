extension BackendFeatures {
    /// Extra backend methods for window handling.
    ///
    /// ## Topics
    ///
    /// ### Constituent Protocols
    /// - ``WindowBehaviors``
    /// - ``WindowClosing``
    ///
    /// ### See Also
    /// - ``WindowLevels``, which is deliberately not part of this typealias --
    ///   see the note on it.
    public typealias Windowing = WindowBehaviors & WindowClosing

    /// Backend methods for placing a window in the stack of windows on screen.
    ///
    /// Its own protocol rather than another parameter on
    /// ``WindowBehaviors/setBehaviors(ofWindow:closable:minimizable:resizable:)``,
    /// and not folded into the ``Windowing`` typealias, because unlike closable,
    /// minimizable and resizable this is a capability a backend may genuinely
    /// not have. GTK 4 is that backend: `gtk_window_set_keep_above` was GTK 3
    /// and was removed, and under Wayland a client cannot raise itself above
    /// another application's window by design. Adding a parameter would have
    /// forced every conformer to answer a question one of them cannot.
    ///
    /// The support list is a property rather than a fixed fact about a backend
    /// because it is not one. A GTK window on Windows is an ordinary `HWND` and
    /// can float; the same backend on Linux cannot. So the answer is computed
    /// per platform, as ``supportedPickerStyles`` and
    /// ``supportedDatePickerStyles`` already are.
    @MainActor
    public protocol WindowLevels<Window>: Core {
        /// The levels this backend can actually place a window at, on the
        /// platform it is currently running on.
        ///
        /// ``WindowLevel/automatic`` and ``WindowLevel/normal`` are expected of
        /// every conformer; a backend that supports neither has no reason to
        /// conform at all.
        nonisolated var supportedWindowLevels: [WindowLevel] { get }

        /// Places a window at a level.
        ///
        /// Only called with a level this backend listed in
        /// ``supportedWindowLevels``, so an implementation does not need to
        /// handle the others. SwiftCrossUI substitutes ``WindowLevel/normal``
        /// for an unsupported level and logs it once, rather than crashing: a
        /// window level is a hint with a working fallback, unlike a missing
        /// widget, and an app should still run on a platform that cannot
        /// provide it.
        func setLevel(ofWindow window: Window, to level: WindowLevel)
    }

    /// Backend methods for setting window behaviors.
    @MainActor
    public protocol WindowBehaviors<Window>: Core {
        /// Sets the behaviors of a window.
        ///
        /// - Parameters:
        ///   - window: The window to set the behaviors on.
        ///   - closable: Whether the window can be closed by the user.
        ///   - minimizable: Whether the window can be minimized by the user.
        ///   - resizable: Whether the window can be resized by the user. Even if
        ///     resizable, the window shouldn't be allowed to become smaller than its
        ///     minimum size, or larger than its maximum size.
        func setBehaviors(
            ofWindow window: Window,
            closable: Bool,
            minimizable: Bool,
            resizable: Bool
        )
    }

    /// Backend methods for closing windows.
    @MainActor
    public protocol WindowClosing<Window>: Core {
        /// Closes a window.
        ///
        /// At some point during or after execution of this function, the handler
        /// set by ``setCloseHandler(ofWindow:to:)`` should be called.
        /// Oftentimes this will be done automatically by the backend's underlying
        /// UI framework.
        ///
        /// This is primarily used by ``DismissWindowAction``.
        func close(window: Window)

        /// Sets the handler for the window's close events (for example, when the
        /// user clicks the close button in the title bar).
        ///
        /// The close handler should also be called whenever ``close(window:)-9xucx``
        /// is called (some UI frameworks do this automatically).
        ///
        /// This is used by SwiftCrossUI to release scene nodes' references to
        /// `window` when the window is closed.
        ///
        /// This is only called once per window; as such, it doesn't matter if
        /// setting the close handler again overrides the previous handler or adds a
        /// new one.
        func setCloseHandler(
            ofWindow window: Window,
            to action: @escaping () -> Void
        )
    }
}
