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
public final class Win32Synthesiser: Synthesiser, Sendable {
    public init() {}

    /// The user's setting, read from the system rather than assumed.
    /// `GetDoubleClickTime` returns milliseconds and defaults to 500, but it is
    /// adjustable in Control Panel, so a file that hard-coded a gap would
    /// behave differently on two machines.
    public var doubleClickInterval: Int { Int(GetDoubleClickTime()) * 1000 }

    /// Asks Windows for our own window's frame and client origins.
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
    ///
    /// Our own window, not `GetForegroundWindow`'s. `SendInput` posts to
    /// whatever is in front, so measuring a different window would compute
    /// coordinates in one frame of reference and deliver clicks in another. The
    /// equivalent assumption on Linux was measured to be wrong -- a window
    /// presented at startup was not focused a second later, and a replay
    /// reported success while driving something else.
    ///
    /// 使用自己的視窗，而非 `GetForegroundWindow` 的。`SendInput` 會投遞至位於前方的任何視窗，
    /// 因此量測另一個視窗會導致「在某個參考座標系中計算座標，卻在另一個座標系中投遞點擊」。
    /// Linux 上的同一項假設已實測為錯誤——啟動時 present 的視窗一秒後並未取得焦點，而重放回報
    /// 成功，實際驅動的卻是別的程式。
    public func currentWindowGeometry() throws -> WindowGeometry {
        let window = try ownWindow()

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

    /// Pins our window above every other window, and takes focus if the file
    /// needs it.
    ///
    /// Measuring the right window is not enough on its own. `SendInput` posts to
    /// whatever is on top at the point it names, so a window that is behind
    /// another one gets a replay delivered to that other application: correct
    /// coordinates, computed from the correct window, wrong target. Nothing
    /// reports it -- `SendInput` accepts the events and returns success.
    ///
    /// Measured 2026-08-26, twice, against a real desktop. This was a bare
    /// `SetForegroundWindow(window)` with its result discarded, while every
    /// other Win32 call in this file is guarded, and both runs clicked into the
    /// editor covering the app instead: the first collapsed two tree items in
    /// it, the second opened a new document. Both runs reported success.
    ///
    /// `SetForegroundWindow` cannot be the mechanism. Windows refuses a
    /// foreground change asked for by a process that is neither already in front
    /// nor the owner of the last input event, and flashes the taskbar button
    /// instead -- so an app launched from a background shell can never take it.
    /// `testapp/P6.swift` recorded exactly this and solved it with
    /// `SetWindowPos(HWND_TOPMOST)`, which is subject to no such rule: any
    /// process may raise its own window, and `SWP_NOACTIVATE` means it does not
    /// even ask for focus. Same remedy here.
    ///
    /// Focus is a separate question, and only a keyboard event needs it -- those
    /// go to whatever holds focus, wherever the pointer is. So focus is
    /// attempted, and its failure is fatal only for a file that presses keys. A
    /// mouse-only file is safe on the topmost pin alone, and refusing to run it
    /// would be refusing something that works.
    ///
    /// 將我方視窗釘在所有視窗之上；若動作檔需要，再取得焦點。
    ///
    /// 光是「量對視窗」並不足夠。`SendInput` 投遞至其所指定座標上方的視窗，因此位於他人之後的
    /// 視窗，會把整場重放交給那個應用程式：座標正確、來源視窗也正確，目標卻是錯的。而且沒有任何
    /// 東西會回報——`SendInput` 會接受這些事件並回報成功。
    ///
    /// 於 2026-08-26 對真實桌面實測兩次。此處原本是一行捨棄回傳值的 `SetForegroundWindow(window)`
    /// ——而本檔其他每個 Win32 呼叫都有防護——兩次都改而點進了覆蓋在 app 上方的編輯器：第一次摺疊了
    /// 其中兩個樹狀項目，第二次開了一份新文件。兩次都回報成功。
    ///
    /// `SetForegroundWindow` 不能作為此處的機制。Windows 會拒絕「既不在前方、也不擁有最後一個輸入
    /// 事件」之行程所提出的前景切換，改為閃爍其工作列按鈕——因此由背景 shell 啟動的 app 永遠拿不到
    /// 前景。`testapp/P6.swift` 記錄過的正是此事，並以 `SetWindowPos(HWND_TOPMOST)` 解決；後者不受
    /// 該規則約束：任何行程都可以抬升自己的視窗，而 `SWP_NOACTIVATE` 代表它甚至不會索取焦點。此處
    /// 採用相同的解法。
    ///
    /// 焦點是另一個問題，且只有鍵盤事件需要它——按鍵會送往持有焦點者，與指標位置無關。因此焦點是
    /// 「嘗試取得」，而其失敗僅對「會按鍵的動作檔」才是致命的。只用滑鼠的檔案單靠置頂即可安全執行，
    /// 拒絕執行它等於拒絕了一件本來可行的事。
    public func prepareForReplay(_ actions: [InputAction]) throws {
        let window = try ownWindow()

        if IsIconic(window) {
            ShowWindow(window, SW_RESTORE)
        }

        // HWND_TOPMOST is `((HWND)-1)`, a macro Swift does not import -- the
        // same bit-pattern construction testapp/P6.swift uses.
        // HWND_TOPMOST 是 `((HWND)-1)` 巨集，Swift 不會匯入——此處採用與 testapp/P6.swift 相同的
        // bit-pattern 構造方式。
        guard
            SetWindowPos(
                window, HWND(bitPattern: -1), 0, 0, 0, 0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        else {
            throw SynthesiserError.toolFailed(
                "SetWindowPos(HWND_TOPMOST)", status: Int32(GetLastError())
            )
        }

        guard actions.contains(where: \.needsKeyboardFocus) else { return }

        SetForegroundWindow(window)
        BringWindowToTop(window)

        // The foreground change is asynchronous, so reading it back immediately
        // can miss a switch that is about to happen. Half a second is far longer
        // than it takes whenever it works at all.
        // 前景切換是非同步的，因此立刻讀回可能會錯過一個即將發生的切換。半秒遠長於它在任何能夠
        // 成功的情況下所需的時間。
        for _ in 0..<50 {
            if GetForegroundWindow() == window {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        throw SynthesiserError.windowNotForeground(
            "this file presses keys, and a key event goes to whichever window has focus"
        )
    }

    /// Lets the window fall back into the normal z-order.
    ///
    /// Not left pinned. Topmost is a state other windows cannot escape, and a
    /// test app that keeps it after its replay sits over everything the user
    /// does next. `testapp/P6.swift` notes the same cost from the other side:
    /// asserting it continuously breaks clicking controls and puts a file
    /// picker behind the window.
    ///
    /// 讓視窗回到正常的 z 順序。
    ///
    /// 不保持釘選狀態。置頂是其他視窗無法擺脫的狀態，一個在重放結束後仍維持置頂的測試 app，會壓在
    /// 使用者接下來所做的每一件事之上。`testapp/P6.swift` 從另一個角度記錄了相同的代價：持續強制
    /// 置頂會使控制項無法點選，也會讓檔案選取對話框跑到視窗後面。
    public func finishReplay() {
        guard let window = try? ownWindow() else { return }
        // HWND_NOTOPMOST is `((HWND)-2)`.
        _ = SetWindowPos(
            window, HWND(bitPattern: -2), 0, 0, 0, 0,
            UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
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

            case .scroll(let dx, let dy):
                // Vertical is inverted here and nowhere else. Windows counts a
                // positive wheel delta as rotation *away* from the user, which
                // scrolls up; our `dy` is positive downwards, matching GDK and
                // the horizontal wheel. Negating here rather than in the format
                // keeps a file meaning the same thing on both platforms, which
                // is the whole point of having one.
                //
                // 只有垂直方向在此處反轉。Windows 將正的滾輪 delta 視為「遠離使用者」的轉動，
                // 亦即向上捲動；而我們的 `dy` 以向下為正，與 GDK 及水平滾輪一致。在此處取負而非
                // 在格式層面處理，可使同一個檔案在兩個平台上意義相同——而那正是統一格式的目的。
                if dy != 0 {
                    try send(wheelFlags: MOUSEEVENTF_WHEEL, delta: -dy * Int(WHEEL_DELTA))
                }
                if dx != 0 {
                    try send(wheelFlags: MOUSEEVENTF_HWHEEL, delta: dx * Int(WHEEL_DELTA))
                }

            case .sleep(let microseconds):
                // Sleep takes milliseconds. A file asking for 500 microseconds
                // gets 1ms rather than 0, because rounding a sub-millisecond
                // wait down to nothing turns a deliberate pause into no pause
                // at all.
                Sleep(DWORD(max(1, microseconds / 1000)))
        }
    }

    /// This process's own visible top-level window, largest by area.
    ///
    /// Largest for the same reason as on Linux: a toolkit owns more than one
    /// top-level window and the first one enumerated can be an invisible helper
    /// or a tooltip host rather than the one the action file was written
    /// against.
    ///
    /// `EnumWindows` takes a C function pointer, which cannot capture, so the
    /// collector is passed through `LPARAM` -- the standard shape for this call
    /// and the reason for the `Unmanaged` round trip.
    ///
    /// 取面積最大者，理由與 Linux 相同：一個 toolkit 會擁有多個 top-level 視窗，而列舉到的第一個
    /// 可能是隱形的輔助視窗或 tooltip host，而非動作檔所針對的那一個。
    ///
    /// `EnumWindows` 接受的是 C function pointer，無法捕獲外部變數，因此收集器透過 `LPARAM`
    /// 傳入——這是此呼叫的標準寫法，也是使用 `Unmanaged` 來回轉換的原因。
    private func ownWindow() throws -> HWND {
        let collector = WindowCollector()
        let context = Unmanaged.passUnretained(collector).toOpaque()
        EnumWindows(
            { window, parameter in
                guard let window,
                    let context = UnsafeRawPointer(bitPattern: Int(parameter))
                else { return true }
                var processID: DWORD = 0
                GetWindowThreadProcessId(window, &processID)
                guard processID == GetCurrentProcessId(), IsWindowVisible(window) else {
                    return true
                }
                Unmanaged<WindowCollector>.fromOpaque(context)
                    .takeUnretainedValue()
                    .windows.append(window)
                return true
            },
            LPARAM(Int(bitPattern: context))
        )

        var best: (window: HWND, area: Int)?
        for window in collector.windows {
            var rect = RECT()
            guard GetWindowRect(window, &rect) else { continue }
            let area = Int(rect.right - rect.left) * Int(rect.bottom - rect.top)
            if best == nil || area > best!.area {
                best = (window, area)
            }
        }

        guard let best else {
            throw SynthesiserError.unsupported("no visible window for this process")
        }
        return best.window
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

    /// One wheel event carrying the whole delta.
    ///
    /// Not one event per notch: `mouseData` is a signed multiple of
    /// `WHEEL_DELTA`, and sending the total in a single event is what a real
    /// wheel with a high-resolution driver produces.
    private func send(wheelFlags: Int32, delta: Int) throws {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.mouseData = DWORD(bitPattern: Int32(delta))
        input.mi.dwFlags = DWORD(wheelFlags)
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

/// Somewhere for the `EnumWindows` callback to put what it finds.
///
/// A class rather than an inout array because the callback is a C function
/// pointer and receives only an opaque `LPARAM`; a reference type is what can
/// survive that round trip.
///
/// 供 `EnumWindows` callback 存放其結果之處。使用 class 而非 inout array，是因為該 callback
/// 是 C function pointer，只能收到一個不透明的 `LPARAM`；能通過這趟轉換的只有 reference type。
private final class WindowCollector {
    var windows: [HWND] = []
}

#endif
