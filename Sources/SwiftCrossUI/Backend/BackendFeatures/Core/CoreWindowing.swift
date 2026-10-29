extension BackendFeatures {
    /// Core backend methods for window handling. These are required for a
    /// functional backend.
    @MainActor
    public protocol CoreWindowing<Window>: Widgets {
        /// The underlying window type. Can be a wrapper or subclass.
        associatedtype Window

        /// Whether the backend can have multiple windows open at once. Mobile
        /// backends generally can't.
        var supportsMultipleWindows: Bool { get }

        /// Whether the backend supports overriding window color schemes (as you may
        /// do with the ``View/preferredColorScheme(_:)`` modifier).
        ///
        /// If `false`, then SwiftCrossUI will ignore the `preferredColorScheme(_:)`
        /// modifier as a nicer failure mode.
        var canOverrideWindowColorScheme: Bool { get }

        /// Whether the backend handles restoring window frames from previous sessions.
        ///
        /// If `true`, the backend is expected to handle the default size by itself, and
        /// calls to ``CoreWindowing/size(ofWindow)`` should return either the window's
        /// default size, or its restored size.
        ///
        /// If `false`, then SwiftCrossUI will always use `defaultSize` as the window's
        /// initial size, because it will presume that the backend's size restoration/defaulting
        /// support is minimal.
        var restoresWindowFrames: Bool { get }

        /// Creates a new window.
        ///
        /// For some backends it may make sense for this method to return the
        /// application's root window the first time its called, and only create new
        /// windows on subsequent invocations.
        ///
        /// A window's content size has precendence over the default size. The
        /// window should always be at least the size of its content.
        ///
        /// - Parameters:
        ///   - defaultSize: The default size of the window. This is only a
        ///     suggestion; for example some backends may choose to restore the user's
        ///     preferred window size from a previous session.
        ///   - id: A "unique" id for the window, to be used for restoring the window's
        ///     position and size from disk if it has been opened before.
        /// - Returns: The created window.
        func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window

        /// Updates a window, generally to react to the current color scheme from the
        /// environment.
        ///
        /// - Parameters:
        ///   - window: The window to update.
        ///   - environment: the current environment.
        func updateWindow(_ window: Window, environment: EnvironmentValues)

        /// Sets the title of a window.
        ///
        /// - Parameters:
        ///   - window: The window to set the title of.
        ///   - title: The new title.
        func setTitle(ofWindow window: Window, to title: String)

        /// Sets the root child of a window.
        ///
        /// This replaces the previous child if one exists.
        ///
        /// - Parameters:
        ///   - window: The window to set the root child of.
        ///   - child: The new root child.
        func setChild(ofWindow window: Window, to child: Widget)

        /// Gets the size of the given window in pixels.
        ///
        /// - Parameter window: The window to get the size of.
        /// - Returns: The window's size in pixels.
        func size(ofWindow window: Window) -> SIMD2<Int>

        /// Check whether a window is programmatically resizable.
        ///
        /// This value does not necessarily reflect whether the window is resizable
        /// by the user.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: Whether the window is programmatically resizable.
        func isWindowProgrammaticallyResizable(_ window: Window) -> Bool

        /// Sets the size (in pixels) of the given window.
        ///
        /// - Parameters:
        ///   - window: The window to set the size of.
        ///   - newSize: The new size.
        func setSize(ofWindow window: Window, to newSize: SIMD2<Int>)

        /// Sets the minimum and maximum width and height of a window.
        ///
        /// Prevents the user from making the window any smaller or larger than the
        /// given minimum and maximum sizes, respectively.
        ///
        /// - Parameters:
        ///   - window: The window to set the size limits of.
        ///   - minimumSize: The minimum window size.
        ///   - maximumSize: The maximum window size. If `nil`, any existing maximum
        ///     size constraints should be removed.
        func setSizeLimits(
            ofWindow window: Window,
            minimum minimumSize: SIMD2<Int>,
            maximum maximumSize: SIMD2<Int>?
        )

        /// The largest content size, in the units of ``size(ofWindow:)``, that
        /// the window can have and still fit on its screen from where it is:
        /// the work area (the screen without the taskbar, dock or panels) from
        /// the window's top-left corner, less the window's frame.
        ///
        /// SwiftCrossUI caps a window's default size, and its growth to fit its
        /// content, at this -- never below the content's minimum size, and never
        /// a size the user chose by resizing. Return `nil` where the platform
        /// sizes windows itself (a phone's screen-filling scene) or cannot say.
        ///
        /// Added 2026-10-29: on a 1920x1080 display at 125%, P41's content grew
        /// its window to 1471 px, so its last row was off the screen and could
        /// not be clicked.
        ///
        /// 視窗從目前位置起、仍能完整放在螢幕上的最大內容尺寸，單位與 ``size(ofWindow:)`` 相同：從視窗左上角起算的
        /// 工作區(扣掉工作列、Dock 或面板的螢幕),再扣掉視窗外框。SwiftCrossUI 以此作為視窗預設尺寸、以及為容納內容而
        /// 撐大時的上限——絕不低於內容的最小尺寸，也絕不限制使用者自己拉出來的尺寸。平台自行決定視窗大小(手機上佔滿
        /// 螢幕的 scene)或無法得知時，回傳 `nil`。2026-10-29 加入：在 125% 的 1920x1080 螢幕上,P41 的內容把視窗撐到
        /// 1471 px,最後一列落在螢幕外、點不到。
        ///
        /// - Parameter window: The window to measure the screen space of.
        /// - Returns: The largest content size that fits, or `nil`.
        func maximumSizeOnScreen(ofWindow window: Window) -> SIMD2<Int>?

        /// Sets the handler for the window's resizing events.
        ///
        /// Setting the resize handler overrides any previous handler.
        ///
        /// - Parameters:
        ///   - window: The window to set the resize handler of.
        ///   - action: The new resize handler. Takes the window's proposed size.
        func setResizeHandler(
            ofWindow window: Window,
            to action: @escaping (_ newSize: SIMD2<Int>) -> Void
        )

        /// Shows a window after it has been created or updated (may be unnecessary
        /// for some backends).
        ///
        /// Predominantly used by window-based ``Scene`` implementations after
        /// propagating updates.
        ///
        /// - Parameter window: The window to show.
        func show(window: Window)

        /// Brings a window to the front if possible.
        ///
        /// Called when the window receives an external URL or file to handle from
        /// the desktop environment. May be used in other circumstances eventually.
        ///
        /// - Parameter window: The window to activate.
        func activate(window: Window)

        /// Computes a window's environment based off the root environment.
        ///
        /// This may involve updating ``EnvironmentValues/windowScaleFactor``, etc.
        ///
        /// - Parameters:
        ///   - window: The window to compute the environment for.
        ///   - rootEnvironment: The root environment.
        /// - Returns: The computed window environment.
        func computeWindowEnvironment(
            window: Window,
            rootEnvironment: EnvironmentValues
        ) -> EnvironmentValues

        /// Sets the handler to be notified when the window's contribution to the
        /// environment may have to be recomputed.
        ///
        /// Use this for things such as updating a window's scale factor in the
        /// environment when the window changes displays. In the future this may be
        /// useful for color space handling.
        ///
        /// If the root environment change handler (set by
        /// ``setRootEnvironmentChangeHandler(to:)``) needs to be called for
        /// whatever reason, the backend can skip calling `action` since the
        /// window's environment will be recomputed anyway.
        ///
        /// - Parameters:
        ///   - window: The window to set the environment change handler of.
        ///   - action: The window environment change handler.
        func setWindowEnvironmentChangeHandler(
            of window: Window,
            to action: @escaping @Sendable @MainActor () -> Void
        )
    }
}
