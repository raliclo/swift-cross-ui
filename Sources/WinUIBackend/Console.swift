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
        // MEASURED 2026-09-04, and the old order made this worse than it looks.
        // `releaseConsole()` ran FIRST and UNCONDITIONALLY, and it does
        // `freopen_s("NUL:", "w", stderr)`. When `AttachConsole` then failed --
        // which is exactly what happens with no parent console, so from a pipe,
        // a service, or a detached process -- stderr was left pointing at NUL
        // and every byte the app wrote was thrown away. Not redirected
        // elsewhere: destroyed. P35-WinUI.exe produced 0 bytes on both streams
        // through a pipe while still writing its own log file, and the -GPU
        // line added in this session vanished the same way.
        //
        // The cost of that was not just lost output. A check whose result is
        // discarded cannot fail, so it cannot pass either: "-GPU 2 printed
        // nothing" was read as possible evidence about adapter selection when
        // it was evidence about nothing at all.
        //
        // 若呼叫端刻意做了重導，就完全不要動它。`./app > out.txt 2>&1` 與 `./app | grep x` 都會把
        // 標準控制代碼設成檔案或管線，而接手它們並不是「附加到父行程的主控台」——那是把呼叫端所
        // 要求的東西丟掉。
        //
        // **2026-09-04 實測**，而舊有的順序讓情況比表面更糟。`releaseConsole()` 是**最先**且
        // **無條件**執行的，而它會做 `freopen_s("NUL:", "w", stderr)`。當其後的 `AttachConsole`
        // 失敗時——那正是「沒有父主控台」時會發生的事，也就是從管線、服務或分離的行程啟動時——
        // stderr 就停在 NUL，app 寫出的每一個位元組都被丟棄。不是被導到別處：是被銷毀。
        // P35-WinUI.exe 透過管線執行時兩個串流都是 0 位元組，卻仍然寫出了自己的 log 檔；本次
        // session 新增的 -GPU 行也是以同樣的方式消失的。
        //
        // 它的代價不只是輸出遺失。**一個結果會被丟棄的檢查無法失敗，因此也無法通過**：
        // 「-GPU 2 什麼都沒印」曾被當成關於介面卡選擇的可能證據，而它其實什麼都不是。
        guard !standardStreamIsRedirected() else { return }

        try Self.releaseConsole()
        // -1 attaches to parent's console
        if AttachConsole(DWORD(bitPattern: -1)) {
            try Self.adjustConsoleBuffer(1024)
            try Self.redirectConsoleIO()
        }
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
        guard _pipe(&pipeEnds, 65536, _O_BINARY) == 0 else {
            throw Error(message: "Failed to create console filter pipe")
        }
        let readEnd = pipeEnds[0]
        let writeEnd = pipeEnds[1]

        guard _dup2(writeEnd, _fileno(stdout)) == 0 else {
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

        var consoleFile = UnsafeMutablePointer<FILE>?.none
        guard fopen_s(&consoleFile, "CONOUT$", "w") == 0, let console = consoleFile else {
            throw Error(message: "Failed to open console for filtered output")
        }
        let consoleAddress = UInt(bitPattern: console)

        Thread.detachNewThread {
            let console = UnsafeMutablePointer<FILE>(bitPattern: consoleAddress)!
            var buffer = [UInt8](repeating: 0, count: 4096)
            var pending = ""
            var lastLineWasNoise = false
            while true {
                let count = _read(readEnd, &buffer, UInt32(buffer.count))
                guard count > 0 else { break }
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
