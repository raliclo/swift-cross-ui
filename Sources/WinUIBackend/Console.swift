import Foundation
import WinSDK

#if canImport(CRT)
    import CRT
#endif

extension WinUIBackend {
    /// Attaches the app's standard IO streams to the parent's console.
    ///
    /// This allows the stdout/stderr of SwiftCrossUI GUI apps to be
    /// viewed by starting them from the command line, even when they're
    /// built and linked as /SUBSYSTEM:WINDOWS apps (GUI apps). Without
    /// this fix the output of GUI apps is basically impossible to access.
    ///
    /// Adapted from: https://stackoverflow.com/a/55875595/8268001
    static func attachToParentConsole() throws {
        // Leave a deliberate redirect alone. `./app > out.txt 2>&1` and
        // `./app | grep x` both set the standard handles to a file or a pipe,
        // and taking those over is not "attaching to the parent's console" --
        // it is discarding what the caller asked for.
        //
        // The order matters. `releaseConsole()` does
        // `freopen_s("NUL:", "w", stderr)`, and `AttachConsole` fails whenever
        // there is no parent console -- from a pipe, a service, or a detached
        // process. Releasing first and unconditionally therefore left stderr
        // pointing at NUL and destroyed every byte the app wrote: measured
        // 2026-09-04, P35-WinUI.exe produced 0 bytes on both streams through a
        // pipe while still writing its own log file.
        //
        // The cost was not just lost output. A check whose result is discarded
        // cannot fail, so it cannot pass either: "-GPU 2 printed nothing" was
        // read as evidence about adapter selection when it was evidence about
        // nothing at all.
        //
        // 若呼叫端刻意做了重導，就完全不要動它。`./app > out.txt 2>&1` 與 `./app | grep x` 都會把
        // 標準控制代碼設成檔案或管線，而接手它們並不是「附加到父行程的主控台」——那是把呼叫端所
        // 要求的東西丟掉。
        //
        // 順序很重要：`releaseConsole()` 會做 `freopen_s("NUL:", "w", stderr)`，而沒有父主控台時
        // (管線、服務、分離的行程)`AttachConsole` 一定會失敗。若先無條件釋放，stderr 就停在 NUL，
        // app 寫出的每一個位元組都被銷毀：2026-09-04 實測，P35-WinUI.exe 透過管線執行時兩個串流
        // 都是 0 位元組，卻仍寫出了自己的 log 檔。
        //
        // 代價不只是輸出遺失。**一個結果會被丟棄的檢查無法失敗，因此也無法通過**：「-GPU 2 什麼
        // 都沒印」曾被當成關於介面卡選擇的證據，而它其實什麼都不是。
        // CRT calls from here validate their descriptors, and the default handler for a bad one is the
        // fail-fast this ends by guarding against: errors rather than a crash, on this thread, until done.
        // 從這裡起的 CRT 呼叫會驗證描述元，而預設的 handler 對壞的描述元就是本函式最後要防止的 fail-fast:在這條執行緒上，
        // 直到結束前都改成回傳錯誤而不是當掉。
        let previousHandler = _set_thread_local_invalid_parameter_handler { _, _, _, _, _ in }
        defer { _ = _set_thread_local_invalid_parameter_handler(previousHandler) }
        // Whatever path this takes, it ends with three usable streams; see
        // `ensureUsableStandardStreams`. / 不論走哪條路，結束時三個串流都可用；見 `ensureUsableStandardStreams`。
        var path = "finding a stream already redirected"
        defer { ensureUsableStandardStreams(after: path) }
        guard !standardStreamIsRedirected() else { return }

        // Copies of the three streams as they were, put back if no console
        // comes of this. `releaseConsole` points them at NUL before it frees the
        // console, so a throw part-way through it, or an `AttachConsole` that
        // fails (no parent console), left stdout at NUL for the rest of the run
        // (review, 2026-11-04; the 2026-10-29 fix below covered only a failure
        // after the attach).
        // 三個串流原本的複本，沒能接上主控台時放回去。`releaseConsole` 在釋放主控台之前就把它們指向 NUL,所以它中途
        // 丟出錯誤，或 `AttachConsole` 失敗(沒有父主控台)時,stdout 在之後整個執行期間都留在 NUL(審查,2026-11-04;
        // 下方 2026-10-29 的修正只涵蓋接上之後的失敗)。
        let saved = SavedStandardStreams()
        defer { saved.close() }
        do {
            try Self.releaseConsole()
        } catch {
            path = "failing to release the console"
            saved.restore()
            throw error
        }
        // -1 attaches to parent's console
        guard AttachConsole(DWORD(bitPattern: -1)) else {
            path = "finding no parent console to attach to"
            saved.restore()
            return
        }
        path = "attaching to the parent console"
        // From here stdin, stdout and stderr are at NUL, so a step that
        // throws must not leave them there: the caller logs the error and
        // carries on, and every later print was lost -- or, if stdout had
        // already been moved onto the filter pipe, written into a pipe nobody
        // read, which blocks the app once its 64 KB fill (review, 2026-10-29).
        // The buffer size is only the scrollback, so its failure is ignored;
        // any other failure falls back to the console without the filter.
        // 從這裡起 stdin、stdout、stderr 都在 NUL,所以丟出錯誤的步驟不能把它們留在那裡：呼叫端記下錯誤就繼續，
        // 之後的每一次輸出都會遺失——若 stdout 已經被接到過濾管線，則寫進一條沒人讀的管線，管線的 64 KB 寫滿後
        // app 就被卡住(審查,2026-10-29)。緩衝區大小只影響捲動範圍，失敗就略過；其他失敗則退回不經過濾的主控台。
        try? Self.adjustConsoleBuffer(1024)
        do {
            try Self.redirectConsoleIO()
        } catch {
            path = "attaching, then failing to redirect to the console"
            Self.redirectToConsoleUnfiltered()
            throw error
        }
    }

    /// Reopens on NUL any standard stream left without a usable handle, and says
    /// so through `OutputDebugString`.
    ///
    /// A GUI app with nowhere to write must write nowhere, not die. On the CI
    /// runner, WinUI apps started by pwsh's `Start-Process` with no redirect died
    /// intermittently with 0xC0000409: UCRT's `write_internal` raised an invalid
    /// parameter, under `fwrite` on the UI fiber, because the stream's descriptor
    /// had no live handle -- P2 in one run, P116 in the next (M4's dump,
    /// 2026-11-13). One way there: the app got a console of its own, the release
    /// above freed it, attaching to the parent failed, and `restore` put back
    /// copies of handles to the console that was gone. Run on every path out of
    /// `attachToParentConsole`, so the cause is recorded rather than guessed.
    ///
    /// `attachToParentConsole` runs it, and everything before it, under a no-op
    /// invalid-parameter handler: `_get_osfhandle` or `_dup` on a dead descriptor raises the same fail-fast.
    ///
    /// 把沒有可用 handle 的標準串流改開到 NUL,並以 `OutputDebugString` 說明。沒有地方可寫的 GUI app 應該寫到不存在的地方，
    /// 而不是當掉。在 CI runner 上，由 pwsh 的 `Start-Process` 啟動、沒有重導的 WinUI app 會間歇地以 0xC0000409 結束:UI fiber
    /// 上的 `fwrite` 底下，UCRT 的 `write_internal` 觸發 invalid parameter,因為串流的描述元已沒有活著的 handle——這次是 P2,
    /// 下次是 P116(M4 的傾印,2026-11-13)。其中一條路：app 有自己的主控台，上面的釋放把它關掉，附加到父行程失敗,`restore`
    /// 又放回那個已不存在之主控台的 handle 複本。`attachToParentConsole` 的每條出口都會執行它，讓原因被記錄下來而不是用猜的。
    /// `attachToParentConsole` 在不做事的 invalid parameter handler 下執行它以及之前的一切：對失效的描述元呼叫 `_get_osfhandle` 或 `_dup` 會觸發同一個
    /// fail-fast。
    private static func ensureUsableStandardStreams(after path: String) {
        let streams: [(name: String, file: UnsafeMutablePointer<FILE>, mode: String, standard: DWORD)] = [
            ("stdin", stdin, "r", STD_INPUT_HANDLE),
            ("stdout", stdout, "w", STD_OUTPUT_HANDLE),
            ("stderr", stderr, "w", STD_ERROR_HANDLE),
        ]
        for stream in streams where !hasUsableHandle(stream.file) {
            var reopened = UnsafeMutablePointer<FILE>?.none
            let didReopen = freopen_s(&reopened, "NUL:", stream.mode, stream.file) == 0
            if didReopen {
                SetStdHandle(
                    stream.standard,
                    UnsafeMutableRawPointer(bitPattern: _get_osfhandle(_fileno(stream.file)))
                )
            }
            let message =
                "SwiftCrossUI: \(stream.name) had no usable handle after \(path); "
                + (didReopen ? "reopened it on NUL\n" : "could not reopen it on NUL\n")
            message.withCString(encodedAs: UTF16.self) { OutputDebugStringW($0) }
        }
    }

    /// Whether a stream's descriptor has a live OS handle. `GetFileType` gives
    /// FILE_TYPE_UNKNOWN (0) with an error for a dead handle, and 0 with no error
    /// only for a live one of unknown type. -2 is UCRT's "no handle" marker.
    /// 串流的描述元是否有活著的 OS handle。`GetFileType` 對失效的 handle 回傳 FILE_TYPE_UNKNOWN(0)並帶錯誤，只有對類型不明
    /// 但活著的 handle 才回傳 0 且無錯誤。-2 是 UCRT「沒有 handle」的標記。
    private static func hasUsableHandle(_ file: UnsafeMutablePointer<FILE>) -> Bool {
        let descriptor = _fileno(file)
        guard descriptor >= 0 else { return false }
        let handle = _get_osfhandle(descriptor)
        guard handle != -1, handle != -2 else { return false }
        SetLastError(0)
        return GetFileType(HANDLE(bitPattern: handle)) != 0 || GetLastError() == 0
    }

    /// Copies of the CRT's descriptors 0, 1 and 2, taken before the console is
    /// released, so a failed attach can put the streams back where they were.
    /// `freopen_s` reopens a stream on the same descriptor, so `_dup2` onto it
    /// redirects the `FILE` too. The Win32 standard handles are set from the
    /// restored descriptors rather than saved, because `freopen_s` closed the
    /// handles they had. A descriptor that had no handle (`_dup` gives -1) is
    /// left as it is.
    /// 在釋放主控台之前取得的 CRT 描述元 0、1、2 的複本，讓附加失敗時能把串流放回原處。`freopen_s` 在同一個描述元上
    /// 重新開啟串流，所以對它 `_dup2` 也會重導 `FILE`。Win32 的標準 handle 依還原後的描述元設定，而不是事先存下，
    /// 因為 `freopen_s` 已經關掉它們原本的 handle。原本沒有 handle 的描述元(`_dup` 回傳 -1)維持原狀。
    private final class SavedStandardStreams {
        private var copies: [CInt]

        init() {
            copies = (0...2).map { _dup(CInt($0)) }
        }

        func restore() {
            fflush(stdout)
            fflush(stderr)
            let standardHandles = [STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE]
            for (descriptor, copy) in copies.enumerated() where copy >= 0 {
                guard _dup2(copy, CInt(descriptor)) == 0 else { continue }
                SetStdHandle(
                    standardHandles[descriptor],
                    UnsafeMutableRawPointer(bitPattern: _get_osfhandle(CInt(descriptor)))
                )
            }
        }

        func close() {
            for copy in copies where copy >= 0 {
                _close(copy)
            }
            copies = []
        }
    }

    /// The fallback when the filtered redirect fails: stdout and stderr straight
    /// to the console, with the backdrop noise left in.
    /// 過濾式重導失敗時的退路:stdout 與 stderr 直接接到主控台，背景雜訊照樣出現。
    private static func redirectToConsoleUnfiltered() {
        var fp = UnsafeMutablePointer<FILE>?.none
        if freopen_s(&fp, "CONOUT$", "w", stdout) == 0 {
            setvbuf(stdout, nil, _IONBF, 0)
            SetStdHandle(
                STD_OUTPUT_HANDLE,
                UnsafeMutableRawPointer(bitPattern: _get_osfhandle(_fileno(stdout)))
            )
        }
        _ = freopen_s(&fp, "CONOUT$", "w", stderr)
    }

    /// Whether stdout or stderr already points at a file or a pipe.
    ///
    /// `GetFileType` is the question that distinguishes "a console this process
    /// should attach to" from "somewhere the caller is collecting output".
    /// Checking BOTH streams, because `2>&1` and `>` are separate acts and a run
    /// that redirects only one still means the caller wants its output.
    ///
    /// The constants are spelled out rather than named: they are `#define`s in
    /// `WinBase.h`, and this project already writes Win32 flag values literally
    /// for the same reason -- Swift imports values, not macros.
    ///
    /// stdout 或 stderr 是否已經指向檔案或管線。
    ///
    /// `GetFileType` 正是那個能區分「這是本行程該附加的主控台」與「這是呼叫端正在收集輸出的地方」
    /// 的問題。**兩個串流都檢查**，因為 `2>&1` 與 `>` 是兩個獨立的動作，而只重導其中一個的執行，
    /// 仍然代表呼叫端要它的輸出。
    ///
    /// 常數以字面值寫出而非使用名稱：它們是 `WinBase.h` 中的 `#define`，而本專案基於相同理由
    /// 一向把 Win32 旗標值直接寫出——Swift 匯入的是值，不是巨集。
    private static func standardStreamIsRedirected() -> Bool {
        // FILE_TYPE_DISK is 0x0001 and FILE_TYPE_PIPE is 0x0003; a console is
        // FILE_TYPE_CHAR 0x0002, and an invalid handle gives FILE_TYPE_UNKNOWN 0.
        // FILE_TYPE_DISK 為 0x0001、FILE_TYPE_PIPE 為 0x0003；主控台是 FILE_TYPE_CHAR 0x0002，
        // 而無效的控制代碼會得到 FILE_TYPE_UNKNOWN 0。
        func isFileOrPipe(_ stdHandle: DWORD) -> Bool {
            let type = GetFileType(GetStdHandle(stdHandle))
            return type == 0x0001 || type == 0x0003
        }
        // STD_OUTPUT_HANDLE is -11 and STD_ERROR_HANDLE is -12.
        // STD_OUTPUT_HANDLE 為 -11，STD_ERROR_HANDLE 為 -12。
        return isFileOrPipe(DWORD(bitPattern: -11)) || isFileOrPipe(DWORD(bitPattern: -12))
    }

    /// Releases existing files associated with the app's standard IO streams.
    private static func releaseConsole() throws {
        var fp = UnsafeMutablePointer<FILE>?.none
        guard
            freopen_s(&fp, "NUL:", "r", stdin) == 0,
            freopen_s(&fp, "NUL:", "w", stdout) == 0,
            freopen_s(&fp, "NUL:", "w", stderr) == 0,
            FreeConsole()
        else {
            throw Error(message: "Failed to release existing console")
        }
    }

    /// Redirect the application's standard IO streams to the current console.
    private static func redirectConsoleIO() throws {
        var fp = UnsafeMutablePointer<FILE>?.none
        guard
            freopen_s(&fp, "CONIN$", "r", stdin) == 0,
            freopen_s(&fp, "CONOUT$", "w", stderr) == 0
        else {
            throw Error(message: "Failed to redirect console IO")
        }
        try redirectFilteredStandardOutput()
    }

    /// Redirects stdout into a pipe drained by a background thread that
    /// filters out noise before writing to the console.
    ///
    /// Microsoft.UI.Xaml.dll from WindowsAppSDK 1.5 preview prints backdrop
    /// debugging messages (BVI-*, rcBackdropLocal=, and bare matrix/rect
    /// value lines) straight to stdout whenever an acrylic backdrop
    /// re-renders, and apps have no switch to turn them off. stderr is left
    /// attached directly to the console so that crash output can't get lost
    /// in the pipe. Remove this filter once we're on a stable WindowsAppSDK
    /// (#204).
    private static func redirectFilteredStandardOutput() throws {
        var pipeEnds = [CInt](repeating: 0, count: 2)
        // _O_NOINHERIT: without it both ends were inheritable, and a child
        // started through Foundation's `Process` (bInheritHandles TRUE) held
        // them too -- the same leak P6 closed for its own children (review,
        // 2026-11-04). stdout itself is a duplicate made by `_dup2` below.
        // _O_NOINHERIT:少了它，管線兩端都可被繼承，經 Foundation `Process`(bInheritHandles 為 TRUE)啟動的子行程
        // 也會拿到它們——與 P6 為自己的子行程堵住的是同一種洩漏(審查,2026-11-04)。stdout 本身是下方 `_dup2` 做出的複本。
        guard _pipe(&pipeEnds, 65536, _O_BINARY | _O_NOINHERIT) == 0 else {
            throw Error(message: "Failed to create console filter pipe")
        }
        let readEnd = pipeEnds[0]
        let writeEnd = pipeEnds[1]

        // The console first, and stdout moved onto the pipe only once the
        // reader can start. In the other order a failed `fopen_s` left stdout on
        // a pipe that nothing drained (review, 2026-10-29).
        // 先開主控台，等讀取端確定能啟動才把 stdout 接到管線。順序相反時,`fopen_s` 一失敗,stdout 就留在一條沒有
        // 人排空的管線上(審查,2026-10-29)。
        var consoleFile = UnsafeMutablePointer<FILE>?.none
        guard fopen_s(&consoleFile, "CONOUT$", "w") == 0, let console = consoleFile else {
            _close(readEnd)
            _close(writeEnd)
            throw Error(message: "Failed to open console for filtered output")
        }

        guard _dup2(writeEnd, _fileno(stdout)) == 0 else {
            fclose(console)
            _close(readEnd)
            _close(writeEnd)
            throw Error(message: "Failed to redirect stdout to console filter pipe")
        }
        // The pipe isn't a console, so the CRT switches stdout to full
        // buffering; disable buffering so output flows through immediately.
        setvbuf(stdout, nil, _IONBF, 0)

        // Cover code that writes directly to GetStdHandle(STD_OUTPUT_HANDLE)
        // as well.
        SetStdHandle(
            STD_OUTPUT_HANDLE,
            UnsafeMutableRawPointer(bitPattern: _get_osfhandle(writeEnd))
        )

        let consoleAddress = UInt(bitPattern: console)

        Thread.detachNewThread {
            let console = UnsafeMutablePointer<FILE>(bitPattern: consoleAddress)!
            var buffer = [UInt8](repeating: 0, count: 4096)
            var pending = ""
            var lastLineWasNoise = false
            while true {
                let count = _read(readEnd, &buffer, UInt32(buffer.count))
                guard count > 0 else { break }
                // keeps U+FFFD for invalid UTF-8; the failable initializer would give nil instead
                // swiftlint:disable:next optional_data_string_conversion
                pending += String(decoding: buffer[0..<Int(count)], as: UTF8.self)
                while let newlineIndex = pending.firstIndex(of: "\n") {
                    var line = String(pending[..<newlineIndex])
                    pending = String(pending[pending.index(after: newlineIndex)...])
                    if line.hasSuffix("\r") {
                        line.removeLast()
                    }
                    if isBackdropDebugNoise(line, afterNoiseLine: lastLineWasNoise) {
                        lastLineWasNoise = true
                        continue
                    }
                    lastLineWasNoise = false
                    fputs(line + "\n", console)
                    fflush(console)
                }
            }

            if !pending.isEmpty {
                if pending.hasSuffix("\r") {
                    pending.removeLast()
                }
                if !isBackdropDebugNoise(pending, afterNoiseLine: lastLineWasNoise) {
                    fputs(pending, console)
                    fflush(console)
                }
            }
        }
    }

    /// Decides whether a single output line is WinUI backdrop debugging noise.
    private nonisolated static func isBackdropDebugNoise(
        _ line: String,
        afterNoiseLine: Bool
    ) -> Bool {
        // The noise blocks are interleaved with blank lines; drop blank lines
        // that directly follow a noise line.
        if line.isEmpty {
            return afterNoiseLine
        }
        if line.hasPrefix("BVI-") || line.hasPrefix("rcBackdropLocal=") {
            return true
        }
        // Bare matrix/rect value lines contain only digits and light
        // punctuation, e.g. "(1.25, 0.00, 0.00, 0.00), ..." or
        // "0.00, 0.00, 12.00, 339.20 (12.00 x 339.20)". Only filter them
        // after an explicit backdrop noise prefix so normal numeric stdout
        // such as "12345" still reaches the console.
        return afterNoiseLine && line.allSatisfy { "0123456789.,-() x".contains($0) }
    }

    /// Adjusts the size of the app's console output buffer.
    private static func adjustConsoleBuffer(_ minLength: SHORT) throws {
        let handle = GetStdHandle(STD_OUTPUT_HANDLE)
        var consoleInfo = CONSOLE_SCREEN_BUFFER_INFO()
        guard GetConsoleScreenBufferInfo(handle, &consoleInfo) else {
            throw Error(message: "Failed to get console screen buffer info")
        }
        if consoleInfo.dwSize.Y < minLength {
            consoleInfo.dwSize.Y = minLength
        }
        guard SetConsoleScreenBufferSize(handle, consoleInfo.dwSize) else {
            throw Error(message: "Failed to set console screen buffer size")
        }
    }
}
