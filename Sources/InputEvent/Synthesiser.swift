import Foundation

/// Where the window is, in screen coordinates, and how big.
///
/// Supplied by the caller because this module does not know about windows. It
/// takes numbers and posts events; keeping it that way is what lets it be
/// tested without a running application.
public struct WindowGeometry: Equatable, Sendable {
    /// Top-left of the window frame, decorations included, in screen points.
    public var frameOrigin: (x: Double, y: Double)

    /// Top-left of the client area, in screen points. On a platform using
    /// client-side decorations this can equal ``frameOrigin``.
    public var clientOrigin: (x: Double, y: Double)

    /// Physical pixels per logical point. Action files are written in points so
    /// they survive being replayed at a different display scale; the conversion
    /// happens here, at the last moment.
    public var scale: Double

    public init(
        frameOrigin: (x: Double, y: Double),
        clientOrigin: (x: Double, y: Double),
        scale: Double = 1
    ) {
        self.frameOrigin = frameOrigin
        self.clientOrigin = clientOrigin
        self.scale = scale
    }

    public static func == (a: WindowGeometry, b: WindowGeometry) -> Bool {
        a.frameOrigin == b.frameOrigin && a.clientOrigin == b.clientOrigin && a.scale == b.scale
    }

    /// Converts a window-relative point to physical screen pixels.
    public func screenPosition(of point: Point) -> (x: Int, y: Int) {
        let origin = point.origin == .frame ? frameOrigin : clientOrigin
        return (
            x: Int(((origin.x + point.x) * scale).rounded()),
            y: Int(((origin.y + point.y) * scale).rounded())
        )
    }
}

/// Posts input events to the system.
///
/// Two of the three implementations are system-wide: `SendInput` posts to the
/// foreground window and XTEST to the X server's focus. Neither targets a chosen
/// window, which is why the caller presents its window before replaying
/// anything. ``AppKitSynthesiser`` is the exception -- it posts into the app's
/// own event queue and addresses its window by number -- and the reason is in
/// that type's own documentation.
///
/// Deliberately not `@MainActor`, and a replay must not be run on the main
/// thread. A replay spends nearly all its time asleep -- waiting for a process,
/// waiting out a `sleep` row -- and on the main thread that sleep is the UI's
/// too. Measured: a two-click file that opens a menu and presses an item ran
/// without error and changed nothing, because the application never got to
/// process the first click and map the popover before the second click was
/// posted at where the popover should have been. Both implementations are
/// thread-safe: one runs a subprocess, the other calls `SendInput`. The macOS one
/// hops each individual post to the main queue, since AppKit may only be touched
/// there, and leaves the sleeping on the replay's own thread.
///
/// 刻意不標記 `@MainActor`，且重放不得在主執行緒上執行。重放的絕大部分時間都在睡眠——等待行程、
/// 等待某個 `sleep` 列——而在主執行緒上，那份睡眠同時也是 UI 的睡眠。實測：一個「開啟選單、按下
/// 項目」的兩步動作檔未報任何錯誤卻毫無變化，因為應用程式根本來不及處理第一次點擊並將 popover
/// map 出來，第二次點擊就已經投遞到「popover 應該在」的位置了。兩個實作都是執行緒安全的：一個
/// 執行子行程，另一個呼叫 `SendInput`。
public protocol Synthesiser: Sendable {
    func perform(_ action: InputAction, in geometry: WindowGeometry) throws

    /// The geometry of whatever window currently has focus.
    ///
    /// Asked of the operating system rather than of the UI toolkit, for two
    /// reasons. GTK 4 does not expose a window's position at all -- Wayland has
    /// no such concept, so the API does not offer one on any backend -- and both
    /// injection paths already target the focused window, so the focused
    /// window's geometry is exactly the frame of reference an action file is
    /// written against.
    ///
    /// Keeping it here also keeps this module independent of any backend, which
    /// is what lets it be tested without a running application.
    func currentWindowGeometry() throws -> WindowGeometry

    /// The platform's double-click interval, in microseconds.
    ///
    /// Read rather than hard-coded. Neither `SendInput` nor XTEST bundles
    /// clicks -- both need two press-release pairs inside this interval -- and
    /// the interval differs between platforms and with the user's settings. A
    /// fixed gap would produce a double click on one machine and two single
    /// clicks on another from the same file.
    var doubleClickInterval: Int { get }
}

extension Synthesiser {
    /// Replays a whole file.
    ///
    /// Stops at the first failure rather than continuing. A synthesiser that
    /// carries on after a failed action produces a run whose later steps acted
    /// on a state the file does not describe, and the screenshot at the end
    /// looks like a product defect.
    public func replay(_ actions: [InputAction], in geometry: WindowGeometry) throws {
        for action in actions {
            try perform(action, in: geometry)
        }
    }

    /// Replays a file against the focused window.
    ///
    /// Geometry is read once, at the start, not per action. Re-reading it would
    /// make a file that moves the window by its title bar measure every
    /// subsequent click against the window's new position, so a drag followed
    /// by a click would land somewhere the file never named.
    public func replay(_ actions: [InputAction]) throws {
        try replay(actions, in: currentWindowGeometry())
    }

    /// Loads a file and replays it against the focused window.
    public func replayFile(at url: URL) throws {
        try replay(ActionFile.load(contentsOf: url))
    }

    /// Two press-release pairs inside the platform's interval, shared by both
    /// implementations so they cannot drift apart on the one behaviour they are
    /// most likely to disagree about.
    public func performDoubleClick(
        _ button: MouseButton,
        at point: Point?,
        in geometry: WindowGeometry
    ) throws {
        try perform(.mouseDown(button, at: point), in: geometry)
        try perform(.mouseUp(button, at: point), in: geometry)
        // Half the interval: comfortably inside it, and far enough from the
        // boundary that a scheduling hiccup does not turn the pair into two
        // single clicks.
        try perform(.sleep(microseconds: doubleClickInterval / 2), in: geometry)
        try perform(.mouseDown(button, at: point), in: geometry)
        try perform(.mouseUp(button, at: point), in: geometry)
    }
}

/// The synthesiser for the platform this was built for.
///
/// One place, and it is this module -- the one that has all three
/// implementations. The choice used to be written inside `GtkBackend`, which
/// meant the Windows synthesiser was reachable only through the GTK backend,
/// and any other backend wanting a replay had to restate the same `#if` and get
/// it right again. `AppKitBackend` restated it and then hard-coded one answer.
///
/// A platform with no implementation throws rather than returning something
/// that quietly does nothing. iOS is that platform today: `UIKitBackend` has no
/// synthesiser, so an `-actionfile` run there says so on stderr instead of
/// leaving a window that looks as though it ignored its input.
///
/// 此建置所對應之平台的 synthesiser。
///
/// 只有一處，且就在本模組——擁有全部三個實作的那一個。此項選擇過去寫在 `GtkBackend` 內，導致
/// Windows 的 synthesiser 只能透過 GTK backend 取得；而任何其他想要重放功能的 backend，都必須重述
/// 同一組 `#if` 並再次把它寫對。`AppKitBackend` 重述了它，然後寫死了單一答案。
///
/// 沒有實作的平台會拋出錯誤，而非回傳一個安靜地什麼也不做的東西。iOS 目前正是這樣的平台：
/// `UIKitBackend` 沒有 synthesiser，因此在該處執行 `-actionfile` 會於 stderr 明說，而不是留下一個
/// 看似忽略了輸入的視窗。
public func makeSynthesiser() throws -> any Synthesiser {
    #if os(Windows)
        return Win32Synthesiser()
    #elseif os(Linux)
        return try XdotoolSynthesiser()
    #elseif os(macOS)
        return AppKitSynthesiser()
    #else
        throw SynthesiserError.unsupported("input synthesis on this platform")
    #endif
}

public enum SynthesiserError: Error, CustomStringConvertible {
    case toolMissing(String)
    case toolFailed(String, status: Int32)
    case unsupported(String)

    public var description: String {
        switch self {
            case .toolMissing(let name):
                "\(name) is not on PATH"
            case .toolFailed(let name, let status):
                "\(name) exited with status \(status)"
            case .unsupported(let what):
                "\(what) is not supported on this platform"
        }
    }
}
