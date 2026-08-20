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
public final class XdotoolSynthesiser: Synthesiser, Sendable {
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

    /// Asks X where our own window is.
    ///
    /// Not `getwindowgeometry`. Under a reparenting window manager xdotool
    /// reports a position that is neither origin: measured on the same window,
    /// `getwindowgeometry` said `X=1021 Y=348` while the true screen position
    /// was `983,289` and the window's offset inside its frame was `38,59` --
    /// xdotool had added the frame offset to a position that already included
    /// it. A click computed from that number missed by exactly the decoration,
    /// which is why the first two replays reported success and changed nothing.
    ///
    /// The client origin is instead obtained by asking xdotool to move the
    /// pointer to the window's own `0,0` and reading back where it landed. That
    /// is definitional rather than derived: it measures the very transform
    /// `mousemove --window` applies, so the numbers cannot disagree with the
    /// mechanism they are computed for. The cost is that the pointer moves to
    /// the window's corner before a replay begins, which is harmless because
    /// every replay moves it anyway.
    ///
    /// 不使用 `getwindowgeometry`。在 reparenting 視窗管理員之下，xdotool 回報的位置兩種原點
    /// 都不是：對同一個視窗實測，`getwindowgeometry` 給出 `X=1021 Y=348`，而真正的螢幕位置是
    /// `983,289`、該視窗在其框架內的偏移是 `38,59`——xdotool 把框架偏移加到了一個已經包含它的
    /// 位置上。由該數字算出的點擊恰好偏離了裝飾的大小，這正是前兩次重放回報成功卻毫無變化的原因。
    ///
    /// 改以「請 xdotool 將指標移至該視窗自身的 `0,0`，再讀回落點」取得 client origin。這是定義性
    /// 而非推導性的：它量測的正是 `mousemove --window` 所套用的那個轉換，因此數字不可能與其服務的
    /// 機制相牴觸。代價是重放開始前指標會移到視窗角落，而這無害——任何重放本來就會移動指標。
    public func currentWindowGeometry() throws -> WindowGeometry {
        // Our own window, found by process id, and raised before anything is
        // measured or posted.
        //
        // Not `getactivewindow`. XTEST posts to whatever the X server has
        // focused, and a window presented at startup is not reliably focused a
        // second later under a window manager -- measured: the first replay ran
        // without error, reported success, and left `last action -> nothing
        // yet` because every click went to another window. Reading geometry
        // from `getactivewindow` compounds it, since the coordinates would then
        // be relative to that other window too.
        //
        // 依 process id 找到自己的視窗，並在任何量測或投遞之前將其提升至前景。
        //
        // 不使用 `getactivewindow`。XTEST 會投遞至 X server 當前聚焦的視窗，而在視窗管理員之下，
        // 啟動時 present 過的視窗並不保證一秒後仍具焦點——實測：第一次重放未報錯、回報成功，卻
        // 留下 `last action -> nothing yet`，因為每一次點擊都送到了別的視窗。若再以
        // `getactivewindow` 讀取幾何，問題會加倍，因為座標也會變成相對於那個別的視窗。
        let window = try ownWindow()
        try run(["windowactivate", "--sync", window])

        try run(["mousemove", "--window", window, "0", "0"])
        let landed = try capture(["getmouselocation", "--shell"])
        func value(_ name: String) -> Double? {
            for line in landed.split(whereSeparator: \.isNewline)
            where line.hasPrefix("\(name)=") {
                return Double(line.dropFirst(name.count + 1))
            }
            return nil
        }
        guard let x = value("X"), let y = value("Y") else {
            throw SynthesiserError.toolFailed("xdotool getmouselocation", status: 0)
        }

        let inset = frameInset(of: window)
        // X reports pixels and has no notion of a logical point, so the scale
        // is 1 and a point is a pixel. On a scaled Wayland session under
        // XWayland the app is scaled by the compositor rather than by X, so
        // this stays true from XTEST's side.
        return WindowGeometry(
            frameOrigin: (x - inset.left, y - inset.top),
            clientOrigin: (x, y),
            scale: 1
        )
    }

    /// How far the client area sits inside the window manager's frame.
    ///
    /// From `_NET_FRAME_EXTENTS`, which the window manager sets to `left,
    /// right, top, bottom`. Absent for an undecorated window, and for one under
    /// GTK's client-side decorations, where the title bar is drawn by the
    /// application inside the client area and the two origins genuinely
    /// coincide -- so a missing property means a zero inset, not a failure.
    ///
    /// `xwininfo`'s "Relative upper-left" is not usable here even though it
    /// carries the same numbers under this window manager: for a window that is
    /// not reparented it degrades to the absolute position, which would be
    /// reported as an enormous frame rather than as none.
    ///
    /// 客戶區位於視窗管理員框架內部多遠，取自 `_NET_FRAME_EXTENTS`（視窗管理員設定為
    /// `left, right, top, bottom`）。未加裝飾的視窗，以及採用 GTK client-side decorations 的
    /// 視窗（標題列由應用程式繪製於客戶區內部，兩種原點確實重合），皆無此屬性——因此屬性不存在
    /// 代表偏移為零，而非失敗。
    ///
    /// 此處不能改用 `xwininfo` 的「Relative upper-left」，即使在此視窗管理員下它帶有相同數值：
    /// 對於未被 reparent 的視窗，它會退化為絕對位置，於是「沒有框架」會被回報成「巨大的框架」。
    private func frameInset(of window: String) -> (left: Double, top: Double) {
        guard let xprop = Self.locate("xprop"),
            let output = try? Self.capture(xprop, ["-id", window, "_NET_FRAME_EXTENTS"])
        else {
            return (0, 0)
        }
        // `_NET_FRAME_EXTENTS(CARDINAL) = 38, 38, 59, 38`
        guard let equals = output.firstIndex(of: "=") else { return (0, 0) }
        let numbers = output[output.index(after: equals)...]
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard numbers.count == 4 else { return (0, 0) }
        return (numbers[0], numbers[2])
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

    /// This process's own visible window, largest first.
    ///
    /// Largest because a GTK app owns more than one X window and the first
    /// match can be a 1x1 helper -- `drive_xdotool.zsh` hit exactly that and
    /// captured a single pixel until it started picking by area.
    private func ownWindow() throws -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        // `search` exits 1 when it matches nothing, so the empty case arrives
        // as a thrown error rather than as an empty list. Both are handled
        // below, and both mean the same thing.
        // `search` 找不到任何匹配時會以狀態 1 結束，因此「空結果」是以擲出錯誤的形式抵達，而非
        // 空清單。以下兩種情形都會處理，且兩者意義相同。
        let listing = (try? capture(["search", "--onlyvisible", "--pid", "\(pid)"])) ?? ""
        let candidates = listing.split(whereSeparator: \.isNewline).map(String.init)
        guard !candidates.isEmpty else {
            // Almost always Wayland rather than a genuinely missing window.
            // XTEST is an X11 extension, and a GTK 4 app on a Wayland session
            // is a Wayland client with no X window for xdotool to find -- by
            // design, since Wayland does not let one client drive another.
            // Measured under WSLg, which offers both: the app rendered, the
            // replay reported a bare `xdotool search ... exited with status 1`,
            // and nothing in that named the cause.
            //
            // 幾乎必然是 Wayland，而非真的沒有視窗。XTEST 是 X11 的擴充，而 Wayland session 上的
            // GTK 4 app 是 Wayland client，沒有任何 X window 可供 xdotool 尋找——這是刻意的設計，
            // 因為 Wayland 不允許一個 client 驅動另一個。在同時提供兩者的 WSLg 上實測：app 正常
            // 繪製，重放卻只回報一句 `xdotool search ... exited with status 1`，完全沒有指出原因。
            if ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil {
                throw SynthesiserError.unsupported(
                    "no X window for pid \(pid); this looks like a Wayland session "
                        + "and XTEST is X11-only -- relaunch with GDK_BACKEND=x11"
                )
            }
            throw SynthesiserError.unsupported("no visible window for pid \(pid)")
        }

        var best: (id: String, area: Int)?
        for candidate in candidates {
            guard let geometry = try? capture(["getwindowgeometry", "--shell", candidate]) else {
                continue
            }
            func value(_ name: String) -> Int? {
                for line in geometry.split(whereSeparator: \.isNewline)
                where line.hasPrefix("\(name)=") {
                    return Int(line.dropFirst(name.count + 1))
                }
                return nil
            }
            guard let width = value("WIDTH"), let height = value("HEIGHT") else { continue }
            let area = width * height
            if best == nil || area > best!.area {
                best = (candidate, area)
            }
        }

        guard let best else {
            throw SynthesiserError.unsupported("no measurable window for pid \(pid)")
        }
        return best.id
    }

    private func capture(_ arguments: [String]) throws -> String {
        try Self.capture(executable, arguments)
    }

    private static func capture(_ executable: URL, _ arguments: [String]) throws -> String {
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
                "\(executable.lastPathComponent) \(arguments.joined(separator: " "))",
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
