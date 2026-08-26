/// Where a window sits in the stack of windows on screen.
///
/// Set with ``Scene/windowLevel(_:)``. The names follow SwiftUI's `WindowLevel`,
/// where ``floating`` is the one that puts a window above every other
/// application's.
///
/// Not every backend can honour every level, and one that cannot says so through
/// ``BackendFeatures/WindowLevels/supportedWindowLevels``. A level a backend does
/// not support falls back to ``normal`` and is logged once; see the note on that
/// protocol for why it is a warning rather than a crash.
///
/// SwiftUI's type also has a `desktop` level, for a window pinned *below* the
/// others as a wallpaper would be. It is left out here because nothing has asked
/// for it -- the enum is the place to add it when something does, and leaving a
/// case nothing implements would only produce a fourth answer every backend has
/// to give.
public enum WindowLevel: Sendable, Hashable {
    /// The backend decides, which in every current backend means ``normal``.
    case automatic

    /// An ordinary window, stacked by use like any other.
    case normal

    /// Above every other window, including other applications', and staying
    /// there without needing focus.
    ///
    /// Costly to leave on. A floating window covers whatever the user does next
    /// and other windows cannot get out from under it, so it suits a palette,
    /// a heads-up display, or a window being driven by a test, rather than an
    /// application's main window.
    case floating
}
