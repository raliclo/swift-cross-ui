import Foundation

/// The `-actionfile` flag: synthesised input, driven from a CSV file.
///
/// Lives here rather than in each backend because none of it is
/// backend-specific. It parses a command-line flag, picks the platform's
/// synthesiser, and replays a file off the main thread -- and a backend that
/// wanted this used to have to reimplement all three. Two of them did, in
/// `GtkBackend/ActionFileReplay.swift` and `AppKitBackend/ActionFileReplay.swift`,
/// as near-identical copies that had already begun to disagree in their
/// documentation about a delay both of them set to one second.
///
/// A backend now calls ``replayIfRequested()`` from wherever it shows a window,
/// and that is the whole integration.
///
/// The format is documented in this module's README.
///
/// `-actionfile` 旗標：以 CSV 檔驅動的合成輸入。
///
/// 置於此處而非各個 backend 之中，因為其中沒有任何一部分是 backend 特有的。它解析一個命令列旗標、
/// 挑選該平台的 synthesiser，並在非主執行緒上重放檔案——而想要此功能的 backend 過去必須把這三件事
/// 全部重新實作一遍。其中兩個確實這麼做了（`GtkBackend/ActionFileReplay.swift` 與
/// `AppKitBackend/ActionFileReplay.swift`），成為兩份幾乎相同的副本，且其文件對於「延遲」的敘述已
/// 開始互相矛盾——儘管兩者都設為一秒。
///
/// 現在 backend 只需在其顯示視窗之處呼叫 ``replayIfRequested()``，整合工作到此為止。
public enum ActionFileReplay {
    /// The file named by `-actionfile`, if the flag was passed.
    public static var requestedFile: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-actionfile"),
              index + 1 < arguments.count
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var hasReplayed = false

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
                try makeSynthesiser(layoutScale: layoutScale).replayFile(at: file)
                report("replayed \(file.lastPathComponent)")
            } catch {
                report("failed: \(error)")
            }
        }
    }

    /// Says what happened, on stderr.
    ///
    /// Always, not behind a `--debug` flag. A replay that failed leaves a window
    /// that looks untouched, which is indistinguishable from the application
    /// ignoring the input -- and that is exactly the wrong bug to go looking
    /// for. The line is one per run and only appears when the flag was passed.
    ///
    /// 一律輸出，不受 `--debug` 旗標控制。失敗的重放會留下一個看似未被觸碰的視窗，這與「應用程式
    /// 忽略了輸入」無法區分——而那正是最不該去追查的方向。此訊息每次執行僅一行，且只在有傳入該
    /// 旗標時才會出現。
    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("-actionfile: \(message)\n".utf8))
    }
}
