extension BackendFeatures {
    /// Backend methods for taking a view out of hit testing.
    ///
    /// These are used by ``View/allowsHitTesting(_:)``.
    @MainActor
    public protocol HitTesting: Core {
        /// Sets whether a widget and everything inside it can receive pointer
        /// events.
        ///
        /// Subtree-wide, matching SwiftUI: a view that does not allow hit
        /// testing does not let its children be hit either, and a nested
        /// `allowsHitTesting(true)` does not undo it. That is a real constraint
        /// rather than an implementation shortcut — the toolkits express this as
        /// a single flag on the widget, and re-enabling below it would need the
        /// whole subtree walked and each widget's own setting remembered.
        ///
        /// Passing `true` restores the default, so a view whose hit testing is
        /// bound to state becomes interactive again when the state changes.
        ///
        /// A backend that cannot express this should do nothing. Ignoring it
        /// leaves the view interactive when it was asked not to be, which is
        /// visible and reportable; refusing to draw it would not be.
        ///
        /// - Parameters:
        ///   - widget: The widget.
        ///   - allowsHitTesting: Whether it and its children can be hit.
        func setHitTesting(of widget: Widget, to allowsHitTesting: Bool)
    }
}

extension BackendFeatures.HitTesting {
    /// Ignores the request.
    ///
    /// A default so that adding this did not break existing backends. The
    /// consequence of ignoring it is a view that still takes clicks, which the
    /// author can see; there is no safer fallback to pick.
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {}
}
