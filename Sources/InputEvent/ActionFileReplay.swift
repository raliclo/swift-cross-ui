import Foundation

/// The `-actionfile` flag: synthesised input, driven from a CSV file.
///
/// Lives here rather than in each backend because none of it is
/// backend-specific. It parses a command-line flag, picks the platform's
/// synthesiser, and replays a file off the main thread; copies of that in
/// each backend would drift apart.
///
/// A backend calls ``replayIfRequested()`` from wherever it shows a window,
/// and that is the whole integration.
///
/// The format is documented in this module's README.
///
/// `-actionfile` 旗標：以 CSV 檔驅動的合成輸入。
///
/// 置於此處而非各個 backend 之中，因為其中沒有任何一部分是 backend 特有的。它解析一個命令列旗標、
/// 挑選該平台的 synthesiser，並在非主執行緒上重放檔案；在每個 backend 各放一份副本，副本之間會漸行漸遠。
///
/// backend 只需在其顯示視窗之處呼叫 ``replayIfRequested()``，整合工作到此為止。
public enum ActionFileReplay {
    /// The file named by `-actionfile`, if the flag was passed.
    public static var requestedFile: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-actionfile"),
              index + 1 < arguments.count
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Where the view showing a text is: the middle of it, in points from the
    /// window's client origin, or `nil` when nothing shows it. Set by a backend
    /// that can search its own view tree; called from the replay thread.
    ///
    /// This is what makes `taplabel` work on the desktop. The synthesisers there
    /// post events to the system and know no views, so the row is turned into a
    /// click at the place the backend reports (``Synthesiser/replay(_:in:)``).
    /// AppKitBackend, GtkBackend and WinUIBackend set it; AndroidSynthesiser
    /// answers `taplabel` itself and the iOS runner does so through XCUITest.
    ///
    /// 顯示某段文字的 view 在哪裡：它的中心，以距視窗 client 原點的點數表示；沒有 view 顯示它時為 `nil`。由能搜尋自己
    /// view 樹的 backend 設定；從重放執行緒呼叫。這就是讓 `taplabel` 在桌面上可用的東西：那裡的合成器把事件送給系統、
    /// 不認識 view,所以這一列會被換成在 backend 回報之處的一次點擊(``Synthesiser/replay(_:in:)``)。AppKitBackend、
    /// GtkBackend 與 WinUIBackend 會設定它;AndroidSynthesiser 自己回應 `taplabel`,iOS runner 則透過 XCUITest。
    public nonisolated(unsafe) static var locateLabel: (@Sendable (String) -> (x: Double, y: Double)?)?

    /// How far the window's content sits from the synthesiser's client origin,
    /// in points, asked before each row; `nil` or `(0, 0)` leaves rows as they are.
    ///
    /// Set by GtkBackend on Linux. WSL runs are launched under X11 with
    /// `GTK_CSD=1`, so the title bar is GTK's own dark header bar, as on
    /// Windows, rather than the light frame WSLg's window manager draws.
    /// That bar is inside the X window, so xdotool's client origin is its
    /// top-left and the content starts about 39 points lower. Measured on P10:
    /// `click,74,232` from actions/wsl/P10-hit-testing.actions hit nothing under
    /// `GTK_CSD=1` without this offset, and the 346 `client` rows in
    /// actions/wsl are written against the content. Only `client` rows move
    /// (``InputAction/shiftingClientPoint(dx:dy:)``); `taplabel` does not, as
    /// ``locateLabel`` already answers from the surface's top-left.
    ///
    /// 視窗內容距合成器的 client 原點多遠(點數),每一列之前詢問；`nil` 或 `(0, 0)` 表示不動。由 Linux 上的
    /// GtkBackend 設定。WSL 以 X11 加 `GTK_CSD=1` 啟動，標題列是 GTK 自己的深色 header bar,
    /// 與 Windows 相同，而不是 WSLg 視窗管理員畫的淺色框。那條標題列在 X 視窗之內，所以 xdotool 的 client 原點
    /// 是它的左上角，內容往下約 39 點。P10 實測:actions/wsl/P10-hit-testing.actions 的 `click,74,232` 在
    /// `GTK_CSD=1` 下若沒有這個位移就什麼都點不到；actions/wsl 裡的 346 列 `client` 座標是對內容量的。只有
    /// `client` 列會移動(``InputAction/shiftingClientPoint(dx:dy:)``);`taplabel` 不動，因為 ``locateLabel``
    /// 本來就以 surface 左上角作答。
    public nonisolated(unsafe) static var clientContentOffset: (@Sendable () -> (x: Double, y: Double))?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var hasReplayed = false

    /// The replay in progress, for ``reportIfCutShort()``: the file, its actions,
    /// and the index of the action being performed. Nil before the replay starts
    /// and after it reports `replayed` or `failed`.
    ///
    /// **An app may end its own process in the middle of a replay, and that can be
    /// the thing under test.** A GTK application quits when its last window
    /// closes, so P75's "Close this window" on GtkBackend ended the process
    /// during the file's closing sleep and the replay never printed `replayed`.
    /// The harness waited for that line for 600 s and the sweep recorded a
    /// timeout, although the close and its `onDisappear` line had both happened
    /// (macOS, 2026-10-22).
    ///
    /// 進行中的重放，供 ``reportIfCutShort()`` 使用：檔案、它的動作，以及正在執行的動作索引。重放開始前
    /// 與回報 `replayed` 或 `failed` 之後為 nil。**app 可能在重放途中結束自己的行程，而那可能正是受測的
    /// 事。**GTK 應用程式在最後一個視窗關閉時結束，所以 P75 的「Close this window」在 GtkBackend 上於檔案
    /// 結尾的 sleep 期間結束了行程，重放從未印出 `replayed`。harness 為那一行等了 600 秒，sweep 記成逾時，
    /// 而關閉與它的 `onDisappear` 那一行其實都已發生(macOS,2026-10-22)。
    private nonisolated(unsafe) static var inFlight: (file: String, actions: [InputAction], index: Int)?

    /// Records which action the replay is on. The replay loop calls it before
    /// each action; it does nothing when no file replay is in progress.
    /// 記下重放進行到哪一個動作。重放迴圈在每個動作之前呼叫；沒有檔案重放進行中時不做任何事。
    public static func noteAction(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        if inFlight != nil { inFlight?.index = index }
    }

    /// Runs at a normal exit (`atexit`) and says how the replay ended, if it had
    /// not said so yet.
    ///
    /// - Every action after the current one is a sleep: each input was sent and
    ///   the app ended itself while the file was only waiting, or during the
    ///   input that ended it. That is `replayed`, with the reason on the same
    ///   line.
    /// - Any input still unsent: `failed`, naming how many.
    ///
    /// A crash does not come here: a signal or a trap skips `atexit` handlers,
    /// and the harness still sees no `replayed` line, as before.
    ///
    /// 在正常結束(`atexit`)時執行，若重放尚未說明自己如何結束，就在此說明。目前動作之後的每個動作都是
    /// sleep:每個輸入都已送出，而 app 是在檔案只是在等待時、或在結束它的那個輸入期間結束自己——那是
    /// `replayed`,原因寫在同一行。仍有輸入尚未送出則是 `failed`,並寫出幾個。崩潰不會來到這裡：信號或
    /// trap 會略過 `atexit`,harness 一如以往看不到 `replayed`。
    static func reportIfCutShort() {
        lock.lock()
        let state = inFlight
        inFlight = nil
        lock.unlock()
        guard let state else { return }
        let after = state.actions.dropFirst(state.index + 1)
        let unsent = after.filter { if case .sleep = $0 { return false } else { return true } }.count
        if unsent == 0 {
            report(
                "replayed \(state.file) (\(state.actions.count) actions; the app exited during action "
                    + "\(state.index + 1), and only sleeps followed it)"
            )
        } else {
            report(
                "failed: the app exited during action \(state.index + 1) of \(state.actions.count) "
                    + "with \(unsent) input action(s) still unsent"
            )
        }
    }

    /// Ends the in-progress record once the replay has reported for itself.
    /// 重放自己回報之後，結束進行中的紀錄。
    private static func finishInFlight() {
        lock.lock()
        inFlight = nil
        lock.unlock()
    }

    /// Replays the requested file against this process's own window, once.
    ///
    /// Call it from `show(window:)`. It returns immediately and does nothing at
    /// all unless the flag was passed.
    ///
    /// Once per process, not once per call. `show(window:)` runs for every
    /// window an application opens, and replaying a second time would act on
    /// the state the first run left behind. The guard is a lock rather than a
    /// plain flag because a backend may show windows from more than one thread.
    ///
    /// 由 `show(window:)` 呼叫。它會立即返回，且若未傳入該旗標則完全不做任何事。
    ///
    /// 每個行程僅一次，而非每次呼叫一次。應用程式每開啟一個視窗都會執行 `show(window:)`，而第二次
    /// 重放所作用的，會是第一次所遺留下來的狀態。此處以鎖而非單純的旗標作為防護，因為 backend 可能
    /// 從多個執行緒顯示視窗。
    ///
    /// `layoutScale` is how many physical pixels the backend's toolkit put in a
    /// logical point, for the backends that know it and whose platform would
    /// otherwise guess wrong. Omitting it keeps the platform's own answer.
    ///
    /// `layoutScale` 是該 backend 的 toolkit 在一個邏輯點中放進了多少實體像素——供那些「自己知道
    /// 答案、且其平台若自行推測會猜錯」的 backend 使用。省略則沿用該平台自身的答案。
    public static func replayIfRequested(layoutScale: Double? = nil) {
        guard let file = requestedFile else { return }

        lock.lock()
        let alreadyDone = hasReplayed
        hasReplayed = true
        lock.unlock()
        guard !alreadyDone else { return }

        // The window is not ready when `show(window:)` returns. Presenting a
        // window does not mean it has been mapped, focused and painted, and on
        // the platforms whose injection is system-wide, replaying too early
        // drives whatever else is in front -- silently, since neither SendInput
        // nor XTEST reports where its events landed. AppKitSynthesiser cannot
        // make that particular mistake, because it addresses its own window by
        // number, but it still needs the window laid out before a coordinate
        // means anything. One second covers both.
        //
        // 當 `show(window:)` 返回時，視窗尚未就緒。present 一個視窗並不代表它已被 map、取得焦點並
        // 完成繪製；而在注入方式為系統層級的平台上，太早重放會驅動到前方的其他東西——且是靜默的，
        // 因為 SendInput 與 XTEST 都不會回報其事件落在何處。AppKitSynthesiser 不會犯下該特定錯誤，
        // 因為它依編號定址自身的視窗，但它仍需要視窗完成佈局，座標才具有意義。一秒對兩者都足夠。
        //
        // Off the main thread, deliberately. A replay is nearly all sleeping --
        // waiting for a subprocess, waiting out a `sleep` row -- and on the main
        // thread that sleep is the UI's too, so events already posted sit in the
        // queue unprocessed. Measured on GTK: a file that opened a menu and then
        // pressed an item reported success and changed nothing, because the
        // popover was never mapped before the second click was posted at it.
        //
        // 刻意不在主執行緒上執行。重放的絕大部分時間都在睡眠——等待子行程、等待某個 `sleep` 列——
        // 而在主執行緒上，那份睡眠同時也是 UI 的睡眠，於是已投遞的事件只能滯留在佇列中無法被處理。
        // 在 GTK 上實測：一個「開啟選單、再按下項目」的檔案回報成功卻毫無變化，因為第二次點擊投遞到
        // popover 位置時，該 popover 從未被 map 出來。
        // Said before the replay, not after, because the case that most needs
        // this number is the one where the replay fails or does nothing
        // visible. A wrong scale does not error: every click lands, just not
        // where the file said, and the window afterwards is indistinguishable
        // from an app that ignored its input.
        //
        // 在重放之前輸出而非之後，因為最需要這個數字的情況，正是「重放失敗」或「什麼看得見的事
        // 都沒發生」的那一種。比例取錯不會報錯：每一次點擊都會落下，只是沒落在檔案所指的位置，
        // 而事後的視窗與一個忽略了輸入的 app 完全無法區分。
        report(
            "replaying \(file.lastPathComponent) at layout scale "
                + (layoutScale.map { "\($0)" } ?? "the platform's own")
        )

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
            do {
                let synthesiser = try makeSynthesiser(layoutScale: layoutScale)
                let actions = try ActionFile.load(contentsOf: file)
                lock.lock()
                inFlight = (file.lastPathComponent, actions, 0)
                lock.unlock()
                atexit { ActionFileReplay.reportIfCutShort() }
                try synthesiser.prepareForReplay(actions)
                defer { synthesiser.finishReplay() }
                let geometry = try synthesiser.currentWindowGeometry()
                report(
                    "geometry frame=(\(geometry.frameOrigin.x), \(geometry.frameOrigin.y)) "
                        + "client=(\(geometry.clientOrigin.x), \(geometry.clientOrigin.y)) "
                        + "scale=\(geometry.scale) "
                        // Printed because a nil here is the difference between
                        // "origin=popover resolved" and "origin=popover was
                        // never going to resolve", and those two produce the
                        // same silence.
                        // 之所以印出來，是因為此處為 nil 與否，正是「`origin=popover` 有解析到」與
                        // 「`origin=popover` 從一開始就不可能解析」之間的差別——而那兩者產生的是
                        // 同一種沉默。
                        + "popover="
                        + (geometry.popoverOrigin.map { "(\($0.x), \($0.y))" } ?? "none")
                )
                try synthesiser.replay(actions, in: geometry)
                // The count, because "replayed" alone cannot tell three things
                // apart that a screenshot also cannot.
                //
                // A file that parses to zero actions replays successfully and
                // does nothing; these files are hand-written CSV, and a
                // mistyped column heading is enough. A file cut short by the
                // process being killed prints no line at all, which is only
                // visible if someone counts `replaying` against `replayed`
                // rather than looking for `failed` -- a driver that captured and
                // killed 97 replays mid-flight left every one of them silent,
                // because nothing had gone wrong. And a replay of the wrong file
                // reads identically unless the name and the count are together.
                //
                // 加上動作數,因為單憑「replayed」無法分辨三件事,而那三件事螢幕截圖同樣分辨不了。
                //
                // 一個解析出零個動作的檔案會成功重放且什麼都不做;這些檔案是手寫的 CSV,一個打錯的
                // 欄位標題就夠了。一個因行程被殺而中斷的重放則完全不會印出這一行,而那只有在有人把
                // `replaying` 與 `replayed` 成對計數、而不是去找 `failed` 時才看得見——一個在中途
                // 拍照並殺掉了 97 次重放的驅動，每一次都是靜默的，因為並沒有任何東西出錯。至於重放了
                // 錯的檔案，除非名稱與數量同時出現，否則讀起來一模一樣。
                //
                // Parenthesised rather than comma-separated, because the count
                // is being added to a line that already has readers.
                // `verify_replay_android.zsh` pulls the name out with
                // `grep -o "actionfile: replayed [^ ]*"`, and a comma would be
                // inside that match -- every recorded filename would gain a
                // trailing comma, in a column used to check that an app
                // replayed its own file. Adding a field to an existing line is
                // a change to everything that parses it.
                //
                // 使用括號而非逗號分隔,因為這個數字是加在一行「已經有讀者」的訊息上。
                // `verify_replay_android.zsh` 是以 `grep -o "actionfile: replayed [^ ]*"` 取出名稱的,
                // 而逗號會落在那次比對之內——於是每一個被記錄的檔名都會多一個尾隨逗號,而那一欄正是
                // 用來檢查「某支 app 重放的是不是自己的檔案」。在一行既有訊息上增加欄位,就是在改動
                // 所有解析它的東西。
                finishInFlight()
                report("replayed \(file.lastPathComponent) (\(actions.count) actions)")
            } catch {
                finishInFlight()
                report("failed: \(error)")
            }
        }
    }

    /// Says what happened, on stderr.
    ///
    /// Always, not behind a `--debug` flag. A replay that failed leaves a window
    /// that looks untouched, which is indistinguishable from the application
    /// ignoring the input -- and that is exactly the wrong bug to go looking
    /// for. It is a handful of lines per run: what makes the exemption
    /// defensible is the volume, so anything that fires per event (such as
    /// `Win32Synthesiser.reportMouseMove`) belongs behind `--debug` instead and
    /// calls in through here rather than around it.
    ///
    /// 一律輸出，不受 `--debug` 旗標控制。失敗的重放會留下一個看似未被觸碰的視窗，這與「應用程式
    /// 忽略了輸入」無法區分——而那正是最不該去追查的方向。每次執行只有數行：讓這個豁免站得住腳的
    /// 是「量」，因此任何逐事件觸發的輸出(例如 `Win32Synthesiser.reportMouseMove`)都應改放在
    /// `--debug` 之後，並且經由此處輸出、而非繞過它。
    ///
    /// `public` because `AndroidSynthesiser` lives in AndroidBackend rather
    /// than in this module and the `hover` verb reports from there. The alternative was a second
    /// stderr writer with the same `-actionfile:` prefix, which is exactly the drift this
    /// function's own note asks callers to avoid.
    ///
    /// 設為 `public`,因為 `AndroidSynthesiser` 住在 AndroidBackend 而不是本模組,
    /// 而 `hover` 這個動作是從那裡回報的。另一個選項是再寫一個帶著相同 `-actionfile:` 前綴的 stderr
    /// 輸出點,而那正是本函式自己的註記要求呼叫端避免的漂移。
    public static func report(_ message: String) {
        let line = "-actionfile: \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))

        // Append, or create -- but never replace. `write(to:)` is not a
        // fallback for a handle that cannot be opened, because it truncates: a
        // file that existed but was momentarily unopenable, held by a reader or
        // locked, would silently lose every line already in it.
        // 附加，或建立——但絕不取代。`write(to:)` 不能當作「取不到 handle」時的退路，因為它會截斷
        // 檔案：一個確實存在、只是當下開不起來(正被讀取或遭鎖定)的檔案，會無聲地失去其中已有的每一行。
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("actionfile-replay.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else if !FileManager.default.fileExists(atPath: url.path) {
            try? Data(line.utf8).write(to: url)
        }
    }
}
