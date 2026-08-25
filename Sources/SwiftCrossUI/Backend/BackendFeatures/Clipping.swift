extension BackendFeatures {
    /// Backend methods for clipping a view to its bounds.
    ///
    /// These are used by ``View/clipped()``.
    @MainActor
    public protocol Clipping: Core {
        /// Creates a container that clips anything its child draws outside its
        /// own bounds, matching SwiftUI's `.clipped()`.
        ///
        /// Unlike ``CornerRadius``, this expresses the clip directly rather than
        /// as a side effect of rounding, so a view can be clipped to a plain
        /// rectangle without also asking for rounded corners. The caller sizes
        /// the container to the child's own layout size, so it does not change
        /// layout.
        ///
        /// A backend that cannot express this returns a plain container, so the
        /// child still shows but overflows. That is visible and reportable; there
        /// is no safer fallback to pick.
        ///
        /// - Returns: A container that clips its child.
        func createClippedContainer() -> Widget
    }
}

extension BackendFeatures.Clipping {
    /// A plain, non-clipping container. A default so adding this did not break
    /// existing backends; the child still overflows, which the author can see.
    public func createClippedContainer() -> Widget {
        createContainer()
    }
}
