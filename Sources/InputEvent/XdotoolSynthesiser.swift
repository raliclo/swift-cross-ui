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

    /// What the toolkit laid out with, when the caller knows. `nil` means 1,
    /// which is what X itself implies.
    /// 呼叫端知道 toolkit 用了什麼比例時，採用此值。`nil` 代表 1，也就是 X 自身所隱含的值。
    private let layoutScale: Double?

    public init(layoutScale: Double? = nil) throws {
        guard let found = Self.locate("xdotool") else {
            throw SynthesiserError.toolMissing("xdotool")
        }
        executable = found
        self.layoutScale = layoutScale
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
        // X reports pixels and has no notion of a logical point, so 1 is the
        // right default and a point is a pixel. On a scaled Wayland session
        // under XWayland the app is scaled by the compositor rather than by X,
        // so that stays true from XTEST's side.
        //
        // The caller can still override it, and the two cases collapse into one
        // rule rather than needing to be told apart: whatever GTK reports as its
        // scale factor is also the factor between a logical point and an X
        // pixel. Compositor-scaled, GTK renders at 1 and reports 1; told
        // `GDK_SCALE=2`, GTK renders at 2 and X sees 2 -- and reports 2.
        //
        // X 回報的是像素，且沒有邏輯點的概念，因此預設 1 是對的，一個點就是一個像素。在
        // XWayland 之下、經過縮放的 Wayland session 中，app 是由 compositor 縮放而非由 X 縮放，
        // 因此就 XTEST 這一側而言此事仍然成立。
        //
        // 呼叫端仍可覆寫，而且這兩種情況會收斂為同一條規則，不需要分辨：GTK 所回報的 scale
        // factor，同時也就是「邏輯點」與「X 像素」之間的倍率。由 compositor 縮放時，GTK 以 1
        // 繪製並回報 1；被指定 `GDK_SCALE=2` 時，GTK 以 2 繪製、X 也看到 2——而它回報 2。
        // Divided by the scale, so that `screenPosition` multiplying the whole
        // sum back leaves the origin where X put it and scales only the point.
        // Win32Synthesiser has always done this; here it was invisible while
        // the scale was hard-coded to 1, and became a bug the moment it was not.
        //
        // Measured 2026-08-27, before the division existed. A file saying
        // `move,410,400` under `GDK_SCALE=2` put the cursor at 1204,906 when
        // 1012,853 was right -- the window origin had been doubled along with
        // the point. What identified it was that solving for the origin under
        // `(origin + point) * scale` gave an inset of exactly -38,-59 at both
        // scales, the same reparenting inset this file documents above, while
        // solving under `origin + point * scale` gave -38,-59 at scale 1 and
        // 154,-6 at scale 2. Four digits agreeing across two axes and two
        // scales is what made that a diagnosis rather than a guess.
        //
        // 先除以該比例，如此 `screenPosition` 把整個總和乘回去時，原點會停在 X 所給的位置，只有
        // 「點」被縮放。Win32Synthesiser 一向如此；此處在比例被寫死為 1 時看不出來，而一旦不再
        // 是 1，它立刻成為 bug。
        //
        // 於 2026-08-27、在此除法尚不存在時實測。`GDK_SCALE=2` 下，一個寫著 `move,410,400` 的
        // 檔案把游標放到了 1204,906，而正確答案是 1012,853——視窗原點連同該點一起被加倍了。
        // 據以指認的關鍵是：以 `(origin + point) * scale` 反解原點，兩種縮放下都得到 -38,-59，
        // 恰為本檔上方所記載的同一個 reparenting 偏移；而以 `origin + point * scale` 反解，
        // scale 1 得 -38,-59、scale 2 卻得 154,-6。四個數字在兩個軸、兩種縮放下一致，才使這成為
        // 一項診斷而非一個猜測。
        let scale = layoutScale ?? 1
        return WindowGeometry(
            frameOrigin: ((x - inset.left) / scale, (y - inset.top) / scale),
            clientOrigin: (x / scale, y / scale),
            scale: scale
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
                let position = try geometry.screenPosition(of: point)
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

            case .scroll(let dx, let dy):
                // X11 has no scroll axis: the wheel arrives as button presses,
                // 4 up, 5 down, 6 left, 7 right. One press per notch, which is
                // what `--repeat` does.
                // X11 沒有捲動軸：滾輪是以按鍵事件形式送達，4 為上、5 為下、6 為左、7 為右。
                // 每一格對應一次按壓，而 `--repeat` 正是如此運作。
                if dy != 0 {
                    try run(["click", "--repeat", "\(abs(dy))", dy > 0 ? "5" : "4"])
                }
                if dx != 0 {
                    try run(["click", "--repeat", "\(abs(dx))", dx > 0 ? "7" : "6"])
                }

            case .focus(let window):
                try focusWindow(titled: window)


            case .sleep(let microseconds):
                usleep(UInt32(max(0, microseconds)))
        }
    }

    /// Raises this process's window with that exact title.
    ///
    /// **`xdotool search --name` takes a REGEX and matches a SUBSTRING.** Left
    /// bare, `focus "P50"` would also match "P50 tables" and "Old P50", and it
    /// would pick whichever the search listed first. That is exactly the failure
    /// this action exists to remove -- `Synthesiser.focusWindow` says so, and
    /// both the AppKit and Win32 implementations match exactly. So the title is
    /// escaped and anchored, which makes all three platforms agree.
    ///
    /// `--pid` as well, so a window belonging to another application cannot be
    /// activated even if its title matches. Same scope as AppKit's
    /// `NSApp.windows.filter { $0.isVisible }`.
    ///
    /// **THE SECOND HALF IS NOT OPTIONAL, and this is the third platform to
    /// need it.** Raising the window is the visible part; making
    /// ``currentWindowIdentity()`` notice is what makes the rows AFTER a
    /// `focus` mean anything. Without it the focus succeeds, the replay reports
    /// every action done, and each later coordinate is still converted against
    /// the window measured before the replay began. AppKit hit this
    /// (`a8627210`, identity returned the protocol default of 0), Win32 hit a
    /// different shape of it (identity answered with largest-by-area, and a
    /// second window is usually smaller), and this file had the AppKit shape:
    /// no override at all.
    ///
    /// 讓本行程中標題**完全相符**的視窗上前。
    ///
    /// **`xdotool search --name` 收的是正規表示式,而且比對的是子字串。** 若原樣傳入,
    /// `focus "P50"` 也會匹配到「P50 tables」與「Old P50」,並挑走搜尋結果中的第一個。
    /// 那正是這個動作存在所要消除的失敗——`Synthesiser.focusWindow` 已寫明,而 AppKit 與 Win32
    /// 兩個實作都是完全相符。因此此處將標題跳脫並加上錨點,使三個平台語意一致。
    ///
    /// 同時使用 `--pid`,使得即便標題相符,屬於其他應用程式的視窗也不會被啟用。範圍與 AppKit 的
    /// `NSApp.windows.filter { $0.isVisible }` 相同。
    ///
    /// **第二半不是可選的,而這已經是第三個需要它的平台。** 把視窗抬起來是看得見的部分;讓
    /// ``currentWindowIdentity()`` 察覺到它,才是讓 `focus` **之後**那些列具有意義的東西。
    /// 少了它,focus 會成功、replay 會回報每個動作都完成,而其後每一個座標仍然是相對於
    /// 「重放開始前所量測的那個視窗」換算的。AppKit 撞過這個(`a8627210`,identity 回傳協定預設 0),
    /// Win32 撞的是它的另一種形狀(identity 以「面積最大」作答,而第二個視窗通常比較小),
    /// 而本檔是 AppKit 的那一種:**根本沒有覆寫**。
    public func focusWindow(titled title: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        // `NSRegularExpression.escapedPattern(for:)` rather than a hand-written
        // character table, and that is the Mac side's version kept over mine.
        // We fixed this same compile break independently (123e95f4 and
        // 53a576f7) and their escape is better: a standard-library function
        // cannot disagree with itself about which metacharacters exist, and mine
        // was a list I had typed out.
        //
        // 使用 `NSRegularExpression.escapedPattern(for:)` 而非手寫的字元表,而**這是採用 Mac 端的
        // 版本、捨棄我的**。我們各自獨立修了同一個編譯中斷(123e95f4 與 53a576f7),而他們的跳脫
        // 更好:一個標準庫函式不可能對「哪些是元字元」與自己意見不合,而我的是一份自己打出來的清單。
        let pattern = "^\(NSRegularExpression.escapedPattern(for: title))$"
        let listing =
            (try? capture(["search", "--onlyvisible", "--pid", "\(pid)", "--name", pattern])) ?? ""
        let matches = listing.split(whereSeparator: \.isNewline).map(String.init)

        guard let window = matches.first else {
            // The visible titles are listed, so a mismatch is one line to
            // diagnose rather than a guess -- the same courtesy the AppKit
            // implementation extends.
            // 列出所有可見視窗的標題,使一次不相符只需一行就能診斷,而不是靠猜——這與 AppKit
            // 的實作所提供的便利相同。
            let visible =
                (try? capture(["search", "--onlyvisible", "--pid", "\(pid)"])) ?? ""
            let titles = visible.split(whereSeparator: \.isNewline).map { id in
                let name = (try? capture(["getwindowname", String(id)])) ?? ""
                return "'\(name.trimmingCharacters(in: .whitespacesAndNewlines))'"
            }
            throw SynthesiserError.unsupported(
                "focus '\(title)': no visible window of this process has that exact title; "
                    + "visible titles are \(titles.joined(separator: ", "))"
            )
        }

        try run(["windowactivate", "--sync", window])
        Self.rememberFocus(window)
    }

    /// The window a `focus` row named, or empty when no row has.
    ///
    /// Static and `nonisolated(unsafe)` for the same reason as the Win32
    /// implementation's: one replay per process, and it is the idiom this module
    /// already uses.
    ///
    /// 一列 `focus` 所指名的視窗;沒有任何一列指名過時為空字串。
    ///
    /// 使用 static 與 `nonisolated(unsafe)`,理由與 Win32 實作相同:每個行程只有一次重放,
    /// 而這正是本 module 既有的寫法。
    nonisolated(unsafe) private static var focusedWindow = ""
    private static let focusLock = NSLock()

    private static func rememberFocus(_ window: String) {
        focusLock.lock()
        defer { focusLock.unlock() }
        focusedWindow = window
    }

    /// Cleared at the start of every replay, so a focus cannot outlive the file
    /// that asked for it.
    /// 在每次重放開始時清除,使一次 focus 無法活得比要求它的那個檔案更久。
    private static func forgetFocus() {
        focusLock.lock()
        defer { focusLock.unlock() }
        focusedWindow = ""
    }

    private static func rememberedFocus() -> String? {
        focusLock.lock()
        defer { focusLock.unlock() }
        return focusedWindow.isEmpty ? nil : focusedWindow
    }

    /// Clears the remembered focus before anything is measured.
    ///
    /// The only reason this override exists -- the protocol's default does
    /// nothing and that was right until a `focus` row could leave state behind.
    /// Two replays in one process would otherwise have the second start pointed
    /// at the first one's window, and `ownWindow()` reads this before it reads
    /// anything else.
    ///
    /// 在任何量測開始之前,清除被記住的焦點。
    ///
    /// **這個覆寫存在的唯一理由**——協定的預設實作什麼都不做,而在「一列 `focus` 會留下狀態」之前,
    /// 那是對的。否則同一行程中的第二次重放,會從「指向第一次那個視窗」的狀態開始,
    /// 而 `ownWindow()` 讀它的時機早於讀任何其他東西。
    public func prepareForReplay(_ actions: [InputAction]) throws {
        Self.forgetFocus()
    }

    /// The X window id `currentWindowGeometry()` will measure, as a comparable
    /// number.
    ///
    /// `0` when it cannot be answered, which the caller reads as "unchanged" --
    /// an identity check that cannot be answered must not abort a replay.
    ///
    /// 以可比較的數值回傳 `currentWindowGeometry()` 將會量測的那個 X window id。
    ///
    /// 無法回答時回傳 `0`,呼叫端會把它讀作「未改變」——一個答不出來的識別檢查,不該中止整個重放。
    public func currentWindowIdentity() -> Int {
        guard let window = try? ownWindow(), let id = Int(window) else { return 0 }
        return id
    }

    private func moveIfNeeded(_ point: Point?, in geometry: WindowGeometry) throws {
        guard let point else { return }
        let position = try geometry.screenPosition(of: point)
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

        // A `focus` row overrides the usual pick, and only a `focus` row can.
        //
        // Without this, `currentWindowIdentity()` above would keep answering
        // with whichever window the ordinary selection returns, so a successful
        // focus would report NO CHANGE and no geometry would be re-measured --
        // the override would be decorative. The two have to agree or neither
        // means anything.
        //
        // `candidates.contains` is the guard that matters: a window that has
        // since closed must not keep steering the replay. Falling back is the
        // pre-`focus` behaviour, which is what every file without a `focus` row
        // still gets, unchanged.
        //
        // 一列 `focus` 會覆蓋原本的選擇,而且只有 `focus` 能。
        //
        // 少了這一段,上方的 `currentWindowIdentity()` 會持續以「一般選擇所回傳的那個視窗」作答,
        // 於是一次成功的 focus 會回報**沒有改變**,也就不會重新量測任何幾何——那個覆寫將淪為裝飾。
        // **兩者必須一致,否則哪一個都沒有意義。**
        //
        // `candidates.contains` 是關鍵的那道防護:一個已經關閉的視窗不可以繼續主導重放。
        // 退回原本的選擇即是 `focus` 出現之前的行為,也正是每一個沒有 `focus` 列的檔案至今
        // 原封不動得到的行為。
        if let focused = Self.rememberedFocus(), candidates.contains(focused) {
            return focused
        }
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
