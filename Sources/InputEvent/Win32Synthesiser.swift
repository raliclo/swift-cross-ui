#if os(Windows)

import Foundation
import WinSDK

/// Posts events through `SendInput`.
///
/// `SendInput` is a Win32 function in `user32.dll`, not a library to obtain, and
/// it posts to the foreground window rather than to a chosen one -- hence the
/// caller presenting its window before replaying anything.
///
/// Mouse positions go through `MOUSEEVENTF_ABSOLUTE`, which does not take
/// pixels: it takes a position on a 0-65535 grid spanning the virtual desktop.
/// Passing pixels there is a mistake that produces a cursor near the top-left
/// corner rather than an error.
public final class Win32Synthesiser: Synthesiser {
    public init() {}

    /// The user's setting, read from the system rather than assumed.
    /// `GetDoubleClickTime` returns milliseconds and defaults to 500, but it is
    /// adjustable in Control Panel, so a file that hard-coded a gap would
    /// behave differently on two machines.
    public var doubleClickInterval: Int { Int(GetDoubleClickTime()) * 1000 }

    /// Asks Windows for the foreground window's frame and client origins.
    ///
    /// `GetWindowRect` gives the frame, decorations included. The client origin
    /// is found by mapping the client area's own `(0,0)` into screen space with
    /// `ClientToScreen`, rather than by subtracting a title bar height --
    /// there is no reliable constant for that, and a window with client-side
    /// decorations has none at all.
    ///
    /// The scale comes from `GetDpiForWindow`, which is per-monitor: a window
    /// dragged to a differently scaled display reports a different value, which
    /// is why it is read here rather than once at startup.
    public func currentWindowGeometry() throws -> WindowGeometry {
        guard let window = GetForegroundWindow() else {
            throw SynthesiserError.unsupported("no foreground window")
        }

        var frame = RECT()
        guard GetWindowRect(window, &frame) else {
            throw SynthesiserError.toolFailed("GetWindowRect", status: Int32(GetLastError()))
        }

        var clientOrigin = POINT(x: 0, y: 0)
        guard ClientToScreen(window, &clientOrigin) else {
            throw SynthesiserError.toolFailed("ClientToScreen", status: Int32(GetLastError()))
        }

        let dpi = GetDpiForWindow(window)
        let scale = dpi == 0 ? 1.0 : Double(dpi) / 96.0

        // Divided by the scale so both origins are in logical points, which is
        // what an action file's coordinates are. screenPosition multiplies back
        // by the same scale; doing it in one place keeps the round trip honest.
        return WindowGeometry(
            frameOrigin: (Double(frame.left) / scale, Double(frame.top) / scale),
            clientOrigin: (Double(clientOrigin.x) / scale, Double(clientOrigin.y) / scale),
            scale: scale
        )
    }

    public func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
        switch action {
            case .move(let point):
                try move(to: point, in: geometry)

            case .click(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.downFlag(for: button))
                try send(mouseFlags: Self.upFlag(for: button))

            case .doubleClick(let button, let point):
                try performDoubleClick(button, at: point, in: geometry)

            case .mouseDown(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.downFlag(for: button))

            case .mouseUp(let button, let point):
                if let point { try move(to: point, in: geometry) }
                try send(mouseFlags: Self.upFlag(for: button))

            case .keyDown(let key):
                try send(key: key, up: false)

            case .keyUp(let key):
                try send(key: key, up: true)

            case .key(let key):
                try send(key: key, up: false)
                try send(key: key, up: true)

            case .sleep(let microseconds):
                // Sleep takes milliseconds. A file asking for 500 microseconds
                // gets 1ms rather than 0, because rounding a sub-millisecond
                // wait down to nothing turns a deliberate pause into no pause
                // at all.
                Sleep(DWORD(max(1, microseconds / 1000)))
        }
    }

    private func move(to point: Point, in geometry: WindowGeometry) throws {
        let position = geometry.screenPosition(of: point)

        // The virtual desktop, not the primary monitor: on a multi-monitor
        // setup the two differ, and using the primary one puts every click on
        // the wrong screen when the window is not on it.
        let left = Double(GetSystemMetrics(SM_XVIRTUALSCREEN))
        let top = Double(GetSystemMetrics(SM_YVIRTUALSCREEN))
        let width = Double(GetSystemMetrics(SM_CXVIRTUALSCREEN))
        let height = Double(GetSystemMetrics(SM_CYVIRTUALSCREEN))
        guard width > 0, height > 0 else {
            throw SynthesiserError.unsupported("virtual screen metrics")
        }

        let normalisedX = (Double(position.x) - left) / width * 65535
        let normalisedY = (Double(position.y) - top) / height * 65535

        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dx = LONG(normalisedX.rounded())
        input.mi.dy = LONG(normalisedY.rounded())
        input.mi.dwFlags = DWORD(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK)
        try dispatch(&input)
    }

    private func send(mouseFlags: Int32) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dwFlags = DWORD(mouseFlags)
        try dispatch(&input)
    }

    private func send(key: Key, up: Bool) throws {
        guard let code = Self.virtualKey(for: key) else {
            throw SynthesiserError.unsupported("key '\(key.rawValue)' on Windows")
        }
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = WORD(code)
        input.ki.dwFlags = up ? DWORD(KEYEVENTF_KEYUP) : 0
        try dispatch(&input)
    }

    private func dispatch(_ input: inout INPUT) throws {
        let sent = withUnsafeMutablePointer(to: &input) {
            SendInput(1, $0, Int32(MemoryLayout<INPUT>.size))
        }
        guard sent == 1 else {
            throw SynthesiserError.toolFailed("SendInput", status: Int32(GetLastError()))
        }
    }

    private static func downFlag(for button: MouseButton) -> Int32 {
        switch button {
            case .left: MOUSEEVENTF_LEFTDOWN
            case .right: MOUSEEVENTF_RIGHTDOWN
            case .middle: MOUSEEVENTF_MIDDLEDOWN
        }
    }

    private static func upFlag(for button: MouseButton) -> Int32 {
        switch button {
            case .left: MOUSEEVENTF_LEFTUP
            case .right: MOUSEEVENTF_RIGHTUP
            case .middle: MOUSEEVENTF_MIDDLEUP
        }
    }

    /// Our macOS-derived names to Windows virtual-key codes.
    ///
    /// The traps this table has to absorb, both inherited from taking macOS
    /// names: our `delete` is Backspace, which Windows calls `VK_BACK` and
    /// spells `VK_DELETE` for the other one; and our `command` is the physical
    /// key in that position, which is the Windows key.
    private static func virtualKey(for key: Key) -> Int32? {
        switch key {
            case .a: 0x41
            case .b: 0x42
            case .c: 0x43
            case .d: 0x44
            case .e: 0x45
            case .f: 0x46
            case .g: 0x47
            case .h: 0x48
            case .i: 0x49
            case .j: 0x4A
            case .k: 0x4B
            case .l: 0x4C
            case .m: 0x4D
            case .n: 0x4E
            case .o: 0x4F
            case .p: 0x50
            case .q: 0x51
            case .r: 0x52
            case .s: 0x53
            case .t: 0x54
            case .u: 0x55
            case .v: 0x56
            case .w: 0x57
            case .x: 0x58
            case .y: 0x59
            case .z: 0x5A

            case .zero: 0x30
            case .one: 0x31
            case .two: 0x32
            case .three: 0x33
            case .four: 0x34
            case .five: 0x35
            case .six: 0x36
            case .seven: 0x37
            case .eight: 0x38
            case .nine: 0x39

            case .delete: VK_BACK
            case .forwardDelete: VK_DELETE
            case .return: VK_RETURN
            case .escape: VK_ESCAPE
            case .space: VK_SPACE
            case .tab: VK_TAB

            case .leftArrow: VK_LEFT
            case .rightArrow: VK_RIGHT
            case .upArrow: VK_UP
            case .downArrow: VK_DOWN
            case .home: VK_HOME
            case .end: VK_END
            case .pageUp: VK_PRIOR
            case .pageDown: VK_NEXT

            case .shift: VK_LSHIFT
            case .rightShift: VK_RSHIFT
            case .control: VK_LCONTROL
            case .rightControl: VK_RCONTROL
            case .option: VK_LMENU
            case .rightOption: VK_RMENU
            case .command: VK_LWIN
            case .rightCommand: VK_RWIN
            case .capsLock: VK_CAPITAL
            // No Windows equivalent: Fn is handled in keyboard firmware and
            // never reaches the OS as a key. nil rather than a wrong code, so
            // the caller is told instead of pressing something else.
            case .function: nil

            case .f1: VK_F1
            case .f2: VK_F2
            case .f3: VK_F3
            case .f4: VK_F4
            case .f5: VK_F5
            case .f6: VK_F6
            case .f7: VK_F7
            case .f8: VK_F8
            case .f9: VK_F9
            case .f10: VK_F10
            case .f11: VK_F11
            case .f12: VK_F12
            case .f13: VK_F13
            case .f14: VK_F14
            case .f15: VK_F15
            case .f16: VK_F16
            case .f17: VK_F17
            case .f18: VK_F18
            case .f19: VK_F19
            case .f20: VK_F20

            case .keypad0: VK_NUMPAD0
            case .keypad1: VK_NUMPAD1
            case .keypad2: VK_NUMPAD2
            case .keypad3: VK_NUMPAD3
            case .keypad4: VK_NUMPAD4
            case .keypad5: VK_NUMPAD5
            case .keypad6: VK_NUMPAD6
            case .keypad7: VK_NUMPAD7
            case .keypad8: VK_NUMPAD8
            case .keypad9: VK_NUMPAD9
            case .keypadDecimal: VK_DECIMAL
            case .keypadPlus: VK_ADD
            case .keypadMinus: VK_SUBTRACT
            case .keypadMultiply: VK_MULTIPLY
            case .keypadDivide: VK_DIVIDE
            // The keypad's Enter is VK_RETURN with the extended-key flag, which
            // this does not set; unmodified it is the main Return. Close enough
            // for a UI test and noted so nobody reads it as exact.
            case .keypadEnter: VK_RETURN
            // No virtual-key code exists for either.
            case .keypadEquals: nil
            case .keypadClear: VK_CLEAR
        }
    }
}

#endif
