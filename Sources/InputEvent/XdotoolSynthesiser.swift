#if os(Linux)

import Foundation

/// Posts events through the `xdotool` binary.
///
/// Shelling out rather than linking `libxdo`. Linking would pull an X11
/// dependency into a target that is otherwise pure Swift and has to build on
/// Windows too, and the cost of a process per action is irrelevant next to the
/// sleeps an action file already contains. The existing
/// `testapp/drive_xdotool.zsh` does the same thing and works.
///
/// XTEST, which is what xdotool uses, posts to the X server's focus rather than
/// to a chosen window -- hence the caller presenting its window first. It also
/// means this only works under X11 or XWayland: a Wayland client cannot be
/// driven by another process at all.
public final class XdotoolSynthesiser: Synthesiser {
    private let executable: URL

    public init() throws {
        guard let found = Self.locate("xdotool") else {
            throw SynthesiserError.toolMissing("xdotool")
        }
        executable = found
    }

    /// X has no double-click interval of its own; the value lives in each
    /// toolkit. GTK's default `gtk-double-click-time` is 400ms, and reading the
    /// live setting would need a GTK dependency this target does not have, so
    /// the default is used and named rather than a number appearing from
    /// nowhere.
    public let doubleClickInterval = 400_000

    /// Asks X for the active window's geometry.
    ///
    /// `getwindowgeometry --shell` prints `X=`, `Y=`, `WIDTH=`, `HEIGHT=`. The
    /// position it reports is the frame's, decorations included.
    ///
    /// Client and frame origins are reported as the same point. Under GTK's
    /// client-side decorations that is literally true -- the title bar is drawn
    /// by the application, inside what X considers the window -- and this is a
    /// GTK app. It would be wrong for a server-side-decorated window, and is
    /// noted rather than hidden because a `frame` row in an action file is
    /// relying on it.
    public func currentWindowGeometry() throws -> WindowGeometry {
        let output = try capture(["getactivewindow", "getwindowgeometry", "--shell"])
        func value(_ name: String) -> Double? {
            for line in output.split(whereSeparator: \.isNewline)
            where line.hasPrefix("\(name)=") {
                return Double(line.dropFirst(name.count + 1))
            }
            return nil
        }
        guard let x = value("X"), let y = value("Y") else {
            throw SynthesiserError.toolFailed("xdotool getwindowgeometry", status: 0)
        }
        // X reports pixels and has no notion of a logical point, so the scale
        // is 1 and a point is a pixel. On a scaled Wayland session under
        // XWayland the app is scaled by the compositor rather than by X, so
        // this stays true from XTEST's side.
        return WindowGeometry(frameOrigin: (x, y), clientOrigin: (x, y), scale: 1)
    }

    public func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
        switch action {
            case .move(let point):
                let position = geometry.screenPosition(of: point)
                try run(["mousemove", "\(position.x)", "\(position.y)"])

            case .click(let button, let point):
                try moveIfNeeded(point, in: geometry)
                try run(["click", Self.number(for: button)])

            case .doubleClick(let button, let point):
                try performDoubleClick(button, at: point, in: geometry)

            case .mouseDown(let button, let point):
                try moveIfNeeded(point, in: geometry)
                try run(["mousedown", Self.number(for: button)])

            case .mouseUp(let button, let point):
                try moveIfNeeded(point, in: geometry)
                try run(["mouseup", Self.number(for: button)])

            case .keyDown(let key):
                try run(["keydown", Self.keysym(for: key)])

            case .keyUp(let key):
                try run(["keyup", Self.keysym(for: key)])

            case .key(let key):
                try run(["key", Self.keysym(for: key)])

            case .sleep(let microseconds):
                usleep(UInt32(max(0, microseconds)))
        }
    }

    private func moveIfNeeded(_ point: Point?, in geometry: WindowGeometry) throws {
        guard let point else { return }
        let position = geometry.screenPosition(of: point)
        try run(["mousemove", "\(position.x)", "\(position.y)"])
    }

    private func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SynthesiserError.toolFailed(
                "xdotool \(arguments.joined(separator: " "))",
                status: process.terminationStatus
            )
        }
    }

    private func capture(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SynthesiserError.toolFailed(
                "xdotool \(arguments.joined(separator: " "))",
                status: process.terminationStatus
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func number(for button: MouseButton) -> String {
        switch button {
            case .left: "1"
            case .middle: "2"
            case .right: "3"
        }
    }

    /// Our macOS-derived names to X keysyms.
    ///
    /// The two disagree in ways that would be silent if this table were skipped
    /// rather than exhaustive: our `delete` is Backspace and X's `Delete` is the
    /// forward one, and our `command` is X's `Super_L`.
    private static func keysym(for key: Key) -> String {
        switch key {
            case .delete: "BackSpace"
            case .forwardDelete: "Delete"
            case .return: "Return"
            case .escape: "Escape"
            case .space: "space"
            case .tab: "Tab"
            case .leftArrow: "Left"
            case .rightArrow: "Right"
            case .upArrow: "Up"
            case .downArrow: "Down"
            case .home: "Home"
            case .end: "End"
            case .pageUp: "Prior"
            case .pageDown: "Next"
            case .shift: "Shift_L"
            case .rightShift: "Shift_R"
            case .control: "Control_L"
            case .rightControl: "Control_R"
            case .option: "Alt_L"
            case .rightOption: "Alt_R"
            case .command: "Super_L"
            case .rightCommand: "Super_R"
            case .capsLock: "Caps_Lock"
            // No X keysym: the Fn key is handled in firmware and never reaches
            // the server as a key of its own. Reported rather than silently
            // dropped.
            case .function: "XF86Fn"
            case .keypadDecimal: "KP_Decimal"
            case .keypadPlus: "KP_Add"
            case .keypadMinus: "KP_Subtract"
            case .keypadMultiply: "KP_Multiply"
            case .keypadDivide: "KP_Divide"
            case .keypadEnter: "KP_Enter"
            case .keypadEquals: "KP_Equal"
            case .keypadClear: "Num_Lock"
            case .keypad0: "KP_0"
            case .keypad1: "KP_1"
            case .keypad2: "KP_2"
            case .keypad3: "KP_3"
            case .keypad4: "KP_4"
            case .keypad5: "KP_5"
            case .keypad6: "KP_6"
            case .keypad7: "KP_7"
            case .keypad8: "KP_8"
            case .keypad9: "KP_9"
            case .zero: "0"
            case .one: "1"
            case .two: "2"
            case .three: "3"
            case .four: "4"
            case .five: "5"
            case .six: "6"
            case .seven: "7"
            case .eight: "8"
            case .nine: "9"
            // Letters and function keys share their spelling with X, so the raw
            // value is already the keysym.
            default: key.rawValue
        }
    }

    private static func locate(_ name: String) -> URL? {
        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

#endif
