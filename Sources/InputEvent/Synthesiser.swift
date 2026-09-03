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

    /// Physical pixels per logical point, **as the toolkit laid the window
    /// out** -- not as the display reports it. The two are not always the same
    /// number, and where they differ it is the toolkit's that a coordinate
    /// means.
    ///
    /// Action files are written in points so they survive being replayed at a
    /// different display scale; the conversion happens here, at the last moment.
    ///
    /// Measured 2026-08-27, from this repository's own history rather than from
    /// a fresh run. When this machine went from 125% to 100%, every Windows
    /// action file had to be re-measured, and all 13 y coordinates changed by
    /// exactly 1.25 -- P21 195 -> 244, P8 300 -> 375, P19 180 -> 225, without
    /// one exception. So the widgets had not moved in *physical* pixels at all:
    /// GTK 4 on Windows rounds the scale to an integer and laid out at 1 at both
    /// DPIs. The synthesiser multiplied by 1.25 regardless, and the files
    /// absorbed the error -- which is why a format meant to be scale
    /// independent was not.
    ///
    /// 每個邏輯點所對應的實體像素數——以**該 toolkit 實際排版時所用的比例**為準，而非顯示器所
    /// 回報的比例。兩者未必相同，而在兩者不同之處，座標所依據的是 toolkit 的那一個。
    ///
    /// 動作檔以「點」書寫，如此才能在不同的顯示縮放下重放；換算就發生在此處，且是最後一刻。
    ///
    /// 於 2026-08-27 自本專案自身的歷史量得，而非來自一次新的執行。這台機器由 125% 改為 100%
    /// 時，所有 Windows 動作檔都必須重新測量，而 13 個 y 座標**無一例外**恰好變動 1.25 倍——
    /// P21 195 -> 244、P8 300 -> 375、P19 180 -> 225。也就是說，widget 的**實體**像素位置根本
    /// 沒有移動：Windows 上的 GTK 4 會將比例取整為整數，兩種 DPI 下都以 1 排版。而 synthesiser
    /// 仍然照乘 1.25，誤差便由動作檔吸收了——這正是一個「本應與縮放無關」的格式並非如此的原因。
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

    /// Puts the window this replay drives where the events will reach it, and
    /// refuses if it cannot.
    ///
    /// Called once, before the first action. It takes the action list because
    /// what "reachable" means depends on what the file does: a mouse event goes
    /// to whatever is on top at that point, a key event to whatever holds focus,
    /// and on Windows those are two different things a caller can obtain
    /// separately.
    ///
    /// 在重放開始前，將受驅動的視窗置於事件能夠抵達之處；若做不到則拒絕執行。
    ///
    /// 於第一個動作之前呼叫一次。它接收動作清單，因為「可抵達」的意義取決於該檔案做些什麼：滑鼠
    /// 事件送往該點上方的視窗，按鍵事件送往持有焦點的視窗，而在 Windows 上這兩者是可以分別取得
    /// 的兩件事。
    func prepareForReplay(_ actions: [InputAction]) throws

    /// Undoes whatever ``prepareForReplay(_:)`` did.
    ///
    /// Called after the last action, and after a failure too. Not throwing: a
    /// cleanup that can fail the run it is cleaning up after replaces the real
    /// error with its own.
    ///
    /// 復原 ``prepareForReplay(_:)`` 所做的一切。
    ///
    /// 於最後一個動作之後呼叫，失敗時亦然。不會拋出錯誤：一個能讓「它所善後的那次執行」失敗的
    /// 清理程序，只會用自己的錯誤取代掉真正的錯誤。
    func finishReplay()

    /// Identifies the window ``currentWindowGeometry()`` would measure right now.
    ///
    /// Only for noticing that it has become a DIFFERENT window. The value is
    /// opaque -- compare it, do not interpret it -- and `0` means "this platform
    /// cannot tell", which is read as "unchanged" and preserves the old
    /// behaviour exactly.
    ///
    /// This exists because an app that opens a dialog changes which window an
    /// action file's coordinates are relative to, and nothing else notices.
    /// Measured on 2026-09-04: with P1's sheet up, the sheet's frame begins at
    /// (188,265) and the owner's at (78,78), so every subsequent `origin=frame`
    /// coordinate was resolved 110 and 187 points away from where the file said.
    /// The clicks landed on the owner, where GTK's modal grab discarded them,
    /// and four apps (P1, P5, P18, P31) looked like they ignored their input.
    ///
    /// A protocol REQUIREMENT rather than an extension, deliberately.
    /// `ActionFileReplay` holds an `any Synthesiser`, so a method that lives only
    /// in an extension cannot be overridden by a conforming type -- the
    /// extension's version is what runs, silently. `replay(_:in:)` below is
    /// exactly that shape, which is why the change goes here and the loop stays
    /// where it is.
    ///
    /// 指出 ``currentWindowGeometry()`` 此刻會量測哪一個視窗。
    ///
    /// 僅用於察覺它已變成**另一個**視窗。此值是不透明的——只能比較，不可解讀——而 `0` 代表
    /// 「本平台無法判斷」，會被讀作「未改變」，因而完整保留原有行為。
    ///
    /// 它之所以存在，是因為「一個開啟對話框的 app，會改變動作檔座標所相對的那個視窗」，而在此之前
    /// 沒有任何東西會察覺這件事。2026-09-04 實測：P1 的 sheet 開啟時，sheet 的框架起點為
    /// (188,265)、其擁有者為 (78,78)，因此其後每一個 `origin=frame` 座標，都被解析到距離檔案所指
    /// 之處 110 與 187 點之外。那些點擊落在擁有者上，被 GTK 的 modal grab 丟棄，於是四支 app
    /// （P1、P5、P18、P31）看起來就像忽略了自己的輸入。
    ///
    /// 刻意置於 protocol **requirement** 而非 extension。`ActionFileReplay` 持有的是
    /// `any Synthesiser`，因此只存在於 extension 的方法無法被遵循型別覆寫——實際執行的會是
    /// extension 的版本，而且是靜默的。下方的 `replay(_:in:)` 正是這個形狀，這也是本次改動放在此處、
    /// 而迴圈維持原位的原因。
    func currentWindowIdentity() -> Int
}

extension Synthesiser {
    /// Nothing to do, which is the case wherever the windowing system does not
    /// let one client outrank another.
    ///
    /// X11 through XTEST and AppKit both deliver to a window this process
    /// already owns or names, so neither has the Windows problem of events
    /// silently landing in a different application.
    ///
    /// 無需任何動作，凡是「視窗系統不容許某個 client 凌駕於另一個之上」的平台皆然。
    ///
    /// 透過 XTEST 的 X11 與 AppKit，都會投遞至本行程已擁有或已指名的視窗，因此兩者都沒有 Windows
    /// 上「事件靜默落入另一個應用程式」的問題。
    public func prepareForReplay(_ actions: [InputAction]) throws {}

    public func finishReplay() {}

    /// Unknown, which keeps every platform that does not implement it on the
    /// pre-2026-09-04 behaviour: geometry read once and never revisited.
    /// 未知；這讓每一個未實作它的平台維持 2026-09-04 之前的行為：幾何只讀一次，之後不再重讀。
    public func currentWindowIdentity() -> Int { 0 }

    /// Replays a whole file.
    ///
    /// Stops at the first failure rather than continuing. A synthesiser that
    /// carries on after a failed action produces a run whose later steps acted
    /// on a state the file does not describe, and the screenshot at the end
    /// looks like a product defect.
    ///
    /// Geometry is re-measured when the target window CHANGES, and only then.
    /// The distinction is the whole design: re-measuring per action would break
    /// the case the caller documents -- a file that drags a window by its title
    /// bar and then clicks would measure that click against the new position,
    /// landing somewhere the file never named. A window that merely moved keeps
    /// its identity, so that file behaves exactly as before. A dialog is a
    /// different window, and its coordinates genuinely are relative to a
    /// different frame.
    ///
    /// 幾何只在目標視窗**改變**時重新量測，且僅限於此。這個區別就是整個設計：逐動作重新量測會破壞
    /// 呼叫端所載明的那個情境——一份「以標題列拖曳視窗後再點擊」的檔案，會把該次點擊對到新位置，
    /// 落在檔案從未指名之處。而僅僅移動過的視窗，其識別值不變，因此那份檔案的行為與先前完全相同。
    /// 對話框則是**另一個**視窗，它的座標確實相對於另一個框架。
    public func replay(_ actions: [InputAction], in geometry: WindowGeometry) throws {
        var geometry = geometry
        var identity = currentWindowIdentity()
        for action in actions {
            let current = currentWindowIdentity()
            if current != 0, current != identity {
                identity = current
                // Prepare BEFORE measuring, the same pairing the file-level
                // `replay(_:)` uses and for the same reason: preparing is what
                // raises the window on the platforms that need raising.
                //
                // It is also a fix in its own right, and a confirmation.
                // `prepareForReplay` pins its window HWND_TOPMOST; a dialog
                // opened afterwards is NOT pinned, so the app's own main window
                // covers its own modal. MEASURED 2026-09-04: P1's sheet existed
                // at 428x174@162,239 -- Win32 reported it, `GW_ENABLEDPOPUP`
                // named it -- and a desktop capture taken at that moment shows
                // no sheet at all, only the main window's buttons in that
                // rectangle. `testapp/actions/win/P5-stacked-alerts.csv` has
                // listed this as a suspicion since 2026-09-03 and said to
                // suspect it first if a capture shows no alert; it was right,
                // and this is the run that turned it into a measurement.
                //
                // 先 prepare 再量測，與檔案層級的 `replay(_:)` 採用相同的配對，理由也相同：
                // 在需要抬升視窗的平台上，正是 prepare 這一步把視窗帶到前面。
                //
                // 它本身也是一項修正，同時是一次確認。`prepareForReplay` 會把它的視窗釘為
                // HWND_TOPMOST；而其後才開啟的對話框**不會**被釘，於是 app 自己的主視窗蓋住了
                // 自己的 modal。**2026-09-04 實測**：P1 的 sheet 確實存在於 428x174@162,239
                // ——Win32 這麼回報，`GW_ENABLEDPOPUP` 也指名了它——而同一時刻的桌面擷圖中完全
                // 看不到任何 sheet，那個矩形裡只有主視窗的按鈕。
                // `testapp/actions/win/P5-stacked-alerts.csv` 自 2026-09-03 起就把這件事列為
                // 懷疑，並寫明「若擷圖看不到 alert，這是第一個該懷疑的東西」；它是對的，而這一次
                // 執行把那個懷疑變成了量測。
                try prepareForReplay(actions)
                geometry = try currentWindowGeometry()
                ActionFileReplay.report(
                    "target window changed -- re-pinned and re-measured geometry "
                        + "frame=(\(geometry.frameOrigin.x), \(geometry.frameOrigin.y)) "
                        + "client=(\(geometry.clientOrigin.x), \(geometry.clientOrigin.y)) "
                        + "scale=\(geometry.scale)"
                )
            }
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
        // Bracketed around the geometry read as well as the actions: reading it
        // is what raises the window on the platforms that need raising, and a
        // window put in front only to be measured, then left to fall behind
        // before the first click, is the failure this pair exists to prevent.
        // 括住的範圍包含幾何量測而不只是動作：在需要抬升視窗的平台上，正是「量測」這一步把視窗
        // 帶到前面；而一個「被抬到前面只為了被量測、接著在第一次點擊之前又落回背後」的視窗，
        // 正是這組成對呼叫所要防止的失敗。
        try prepareForReplay(actions)
        defer { finishReplay() }
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
///
/// `layoutScale` is how many physical pixels the toolkit put in a logical
/// point. Only a caller that owns the widget can answer it, which is why it is
/// a parameter rather than something this module works out: this module
/// deliberately knows nothing about backends. Passing `nil` leaves each
/// synthesiser to ask the operating system, which is right wherever the toolkit
/// and the display agree.
///
/// `layoutScale` 是「該 toolkit 在一個邏輯點中放進了多少實體像素」。只有持有該 widget 的呼叫端
/// 答得出來，因此它是一個參數，而非由本模組自行推導：本模組刻意對任何 backend 一無所知。傳入
/// `nil` 則交由各 synthesiser 去問作業系統——凡 toolkit 與顯示器一致之處，那都是對的。
public func makeSynthesiser(layoutScale: Double? = nil) throws -> any Synthesiser {
    #if os(Windows)
        return Win32Synthesiser(layoutScale: layoutScale)
    #elseif os(Linux)
        return try XdotoolSynthesiser(layoutScale: layoutScale)
    #elseif os(macOS)
        return AppKitSynthesiser()
    #else
        if let registered = try SynthesiserRegistry.make(layoutScale: layoutScale) {
            return registered
        }
        throw SynthesiserError.unsupported("input synthesis on this platform")
    #endif
}

/// Where a backend supplies the synthesiser this module cannot build itself.
///
/// The three implementations above are written against system APIs this module
/// can reach on its own: `SendInput`, XTEST through a subprocess, and AppKit.
/// Android is not like that. Its events are posted into a view hierarchy owned
/// by an `Activity`, and the activity belongs to `AndroidBackend` -- which
/// depends on this module, so this module cannot depend back on it.
///
/// Registration inverts that without weakening the guarantee the `#else` branch
/// makes: a platform with nothing registered still throws, rather than
/// returning something that quietly does nothing.
///
/// **Only consulted where there is no built-in implementation.** Windows, Linux
/// and macOS never reach it, so registering cannot change what already works.
///
/// 由 backend 提供本模組自己建構不出來的 synthesiser 之處。
///
/// 上方三個實作所依據的系統 API，本模組都能自行取得：`SendInput`、經由子行程的 XTEST，以及 AppKit。
/// Android 不是這樣。它的事件是投遞進一個由 `Activity` 所擁有的 view 階層，而該 activity 屬於
/// `AndroidBackend`——後者依賴本模組，因此本模組無法反過來依賴它。
///
/// 註冊機制把這個方向倒過來，同時不削弱 `#else` 分支所做的保證：沒有註冊任何東西的平台依然會拋出
/// 錯誤，而不是回傳一個安靜地什麼也不做的東西。
///
/// **僅在沒有內建實作之處才會被查詢。** Windows、Linux 與 macOS 永遠不會走到這裡，因此註冊不可能
/// 改變任何已經能運作的東西。
public enum SynthesiserRegistry {
    private final class Storage: @unchecked Sendable {
        var factory: (@Sendable (Double?) throws -> any Synthesiser)?
        let lock = NSLock()
    }

    private static let storage = Storage()

    /// Installs the factory. Called once, by a backend, during start-up.
    /// 安裝該工廠函式。由 backend 在啟動時呼叫一次。
    public static func register(
        _ factory: @escaping @Sendable (Double?) throws -> any Synthesiser
    ) {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.factory = factory
    }

    static func make(layoutScale: Double?) throws -> (any Synthesiser)? {
        storage.lock.lock()
        let factory = storage.factory
        storage.lock.unlock()
        return try factory?(layoutScale)
    }
}

public enum SynthesiserError: Error, CustomStringConvertible {
    case toolMissing(String)
    case toolFailed(String, status: Int32)
    case unsupported(String)

    /// The window to replay against could not be brought to the front.
    ///
    /// Its own case because the consequence is specific and worth naming: on a
    /// platform whose injection is system-wide, a replay that runs anyway does
    /// not fail, it drives whichever application is in front.
    ///
    /// 用於「無法將待重放的視窗提到最前」。獨立成一個 case，是因為其後果具體且值得指名：在注入
    /// 方式為系統層級的平台上，仍然繼續執行的重放不會失敗，而是會去驅動位於前方的那個應用程式。
    case windowNotForeground(String)

    public var description: String {
        switch self {
            case .toolMissing(let name):
                "\(name) is not on PATH"
            case .toolFailed(let name, let status):
                "\(name) exited with status \(status)"
            case .unsupported(let what):
                "\(what) is not supported on this platform"
            case .windowNotForeground(let why):
                "could not bring our window to the front: \(why)"
        }
    }
}
