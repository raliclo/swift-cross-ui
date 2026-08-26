extension Scene {
    /// Sets where this scene's windows sit in the stack of windows on screen.
    ///
    /// ``WindowLevel/floating`` puts a window above every other application's
    /// and keeps it there without it needing focus, which is the only way to
    /// stay in front on Windows: a process that is not already in front cannot
    /// take the foreground there, so raising a window from a script or a
    /// background launcher does not work.
    ///
    /// Backends that cannot honour a level fall back to ``WindowLevel/normal``
    /// and log it. ``BackendFeatures/WindowLevels/supportedWindowLevels`` is
    /// what to ask if the answer needs to change what an app does, rather than
    /// just be recorded.
    public func windowLevel(_ level: WindowLevel) -> some Scene {
        environment(\.windowLevel, level)
    }

    /// Keeps this scene's windows above every other window, or stops doing so.
    ///
    /// The same thing as ``windowLevel(_:)`` with ``WindowLevel/floating``, under
    /// the name the platform APIs use for it -- Windows calls it `HWND_TOPMOST`
    /// and X11 calls it `_NET_WM_STATE_ABOVE`. ``windowLevel(_:)`` is the
    /// spelling that matches SwiftUI and the one to reach for when a scene picks
    /// between levels; this one reads better where a scene is only ever pinned
    /// or not, which is most of them.
    ///
    /// The same shape as ``PickerStyle/palette``, which exists beside
    /// ``PickerStyle/segmented`` for the same reason: two names for one thing
    /// cost nothing when both are the name someone will look for.
    public func topmost(_ isTopmost: Bool = true) -> some Scene {
        windowLevel(isTopmost ? .floating : .normal)
    }
}
