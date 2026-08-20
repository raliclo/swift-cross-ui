import Foundation

/// One row of an action file.
///
/// The verbs and their arguments are described in this module's README. Each
/// case carries only what that verb uses, so an unusable combination -- a
/// `sleep` with a button, a `click` with a key -- cannot be constructed.
public enum InputAction: Equatable, Sendable {
    case move(Point)
    case click(MouseButton, at: Point?)
    case doubleClick(MouseButton, at: Point?)
    case mouseDown(MouseButton, at: Point?)
    case mouseUp(MouseButton, at: Point?)
    case keyDown(Key)
    case keyUp(Key)
    case key(Key)
    case sleep(microseconds: Int)
}

/// A position and the origin it is measured from.
public struct Point: Equatable, Sendable {
    /// Logical points, not physical pixels. A file written in pixels is correct
    /// only at the display scale it was written at, and fails by clicking
    /// somewhere plausible rather than by reporting anything.
    public var x: Double
    public var y: Double
    public var origin: Origin

    public init(x: Double, y: Double, origin: Origin = .client) {
        self.x = x
        self.y = y
        self.origin = origin
    }
}

/// Where `0,0` sits.
public enum Origin: String, Equatable, Sendable {
    /// Top-left of the client area, below the title bar and inside the border.
    /// The default, and correct for everything the app draws.
    case client

    /// Top-left of the window frame, including the decorations. For the title
    /// bar and the close, minimise and maximise buttons.
    ///
    /// Less portable than `client`: title bar height varies with platform,
    /// theme and display scale, and under GTK's client-side decorations the
    /// title bar is drawn by the app rather than the window manager, so the two
    /// origins can coincide on one machine and differ on another.
    case frame
}

public enum MouseButton: String, Equatable, Sendable {
    case left
    case right
    case middle
}

/// A key, named as macOS names it.
///
/// The names are Carbon's `kVK_*` constants from `HIToolbox/Events.h` -- the
/// codes `NSEvent.keyCode` returns -- with the `kVK_` prefix and the `ANSI_`
/// infix dropped and the first letter lowercased.
///
/// macOS is the source rather than a set invented here, or either of the two
/// platforms this runs on. It is a real specification with documentation, so an
/// argument about what a name means has somewhere to go; it is complete,
/// including the keypad and the right-hand modifiers, which an invented list
/// would have discovered it needed later; and it belongs to the third backend,
/// so neither Linux nor Windows spelling wins by default.
///
/// Two Mac assumptions come with the names and are not accidents of this
/// implementation:
///
/// - ``delete`` is Backspace. ``forwardDelete`` is the key usually labelled
///   Delete elsewhere.
/// - ``command`` is the physical key in that position -- the Windows key, or
///   Super -- not "whatever this platform uses for shortcuts". A Mac shortcut
///   is Command-based where the same shortcut is Control-based elsewhere, so an
///   action file exercising a shortcut cannot be identical across platforms
///   even though its key names are.
public enum Key: String, Equatable, Sendable, CaseIterable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"

    case delete, forwardDelete
    case escape, space, tab, `return`

    case leftArrow, rightArrow, upArrow, downArrow
    case home, end, pageUp, pageDown

    case shift, control, option, command
    case rightShift, rightControl, rightOption, rightCommand
    case capsLock, function

    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    case keypad0, keypad1, keypad2, keypad3, keypad4
    case keypad5, keypad6, keypad7, keypad8, keypad9
    case keypadDecimal, keypadPlus, keypadMinus
    case keypadMultiply, keypadDivide, keypadEnter
    case keypadEquals, keypadClear
}
