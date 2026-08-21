import Foundation

/// Whether the debug features were compiled into this binary.
///
/// A compile-time constant, not a runtime setting. `SCUI_DEBUG=1` at build time
/// defines `SCUI_DEBUG`, and everything gated on this constant is removed from
/// a build without it -- the flag parsing, the messages, and the code that
/// replays an action file.
///
/// 本執行檔是否編入了 debug 功能。
///
/// 這是編譯期常數，而非執行期設定。建置時的 `SCUI_DEBUG=1` 會定義 `SCUI_DEBUG`，而所有以此常數
/// 為條件的東西，在未定義它的建置中都會被移除——包含旗標解析、訊息輸出，以及重放動作檔的程式碼。
public enum DebugFeatures {
    #if SCUI_DEBUG
    public static let isCompiledIn = true
    #else
    public static let isCompiledIn = false
    #endif

    /// Whether `--debug` was passed **and** the debug features are compiled in.
    ///
    /// Reads the command line once. A release binary returns `false` without
    /// looking, because there is nothing for the flag to switch on.
    ///
    /// 是否傳入了 `--debug`，**且**本執行檔編入了 debug 功能。
    ///
    /// 只讀取命令列一次。release 建置會直接回傳 `false` 而不去查看，因為該旗標沒有任何東西可以
    /// 開啟。
    public static let isEnabled: Bool = {
        #if SCUI_DEBUG
        return CommandLine.arguments.contains("--debug")
        #else
        return false
        #endif
    }()

    /// Whether action-file replay is available.
    ///
    /// Separate from ``isEnabled`` because it answers a different question.
    /// `isEnabled` is about this run; this is about the binary. A release build
    /// has no way to synthesise input at all, which is the point -- a shipped
    /// application should not be able to drive its own interface.
    ///
    /// 是否可使用動作檔重放。
    ///
    /// 與 ``isEnabled`` 分開，因為兩者回答的是不同的問題。`isEnabled` 關乎「這一次執行」，此處
    /// 關乎「這個執行檔」。release 建置根本無從合成輸入，而那正是重點——已出貨的應用程式不應該
    /// 有能力驅動自己的介面。
    public static var supportsActionFiles: Bool { isCompiledIn }

    /// The value after a flag, or `nil` when the flag is absent or last.
    ///
    /// Always returns `nil` in a release build, so a flag that only makes sense
    /// alongside the debug features cannot be honoured by accident.
    ///
    /// 某個旗標之後的值；若該旗標不存在或位於最後，則回傳 `nil`。
    ///
    /// 在 release 建置中一律回傳 `nil`，使「僅在 debug 功能存在時才有意義的旗標」不會被意外採納。
    public static func value(after flag: String) -> String? {
        #if SCUI_DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    /// Writes a line to standard error when debugging is on.
    ///
    /// `@autoclosure` so the message is not built in a release binary. A
    /// diagnostic that interpolates a description costs the description even
    /// when nothing prints it, and those add up in a loop.
    ///
    /// 於 debug 開啟時，向標準錯誤輸出一行訊息。
    ///
    /// 使用 `@autoclosure`，使該訊息在 release 建置中根本不會被建構。一則會插值物件描述的診斷
    /// 訊息，即使沒有任何東西印出它，仍會付出建構描述的代價——而在迴圈中，這些代價會累積。
    public static func log(_ message: @autoclosure () -> String) {
        #if SCUI_DEBUG
        guard isEnabled else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
        #endif
    }

    /// What this binary was built with, one line per switch.
    ///
    /// Every compile-time option in one place, so "which build is this" is a
    /// question the binary answers rather than one someone reconstructs from a
    /// shell history. Two builds of the same version are otherwise
    /// indistinguishable, and that is how a stale executable gets debugged for
    /// an hour.
    ///
    /// The backend is not here, because this module cannot know it:
    /// `SCUI_DEFAULT_BACKEND` is read when the *manifest* is evaluated, and
    /// nothing carries the name into the compiled code. An application knows
    /// its own backend and should print `String(describing: DefaultBackend.self)`
    /// beside this.
    ///
    /// 本執行檔的建置設定，每個開關一行。
    ///
    /// 將所有編譯期選項集中於一處，使「這是哪一種建置」成為執行檔自己能回答的問題，而非某人從 shell
    /// 歷史紀錄中拼湊出來的答案。否則同一版本的兩個建置彼此無從分辨——而那正是「對著一個過期的執行檔
    /// 除錯一小時」的成因。
    ///
    /// backend 不在此列，因為本模組無從得知：`SCUI_DEFAULT_BACKEND` 是在評估 *manifest* 時讀取的，
    /// 而沒有任何東西把該名稱帶進編譯後的程式碼。應用程式知道自己的 backend，應在此之外自行印出
    /// `String(describing: DefaultBackend.self)`。
    public static var summary: [String] {
        [
            "debug features: \(isCompiledIn ? "compiled in" : "not compiled in")",
            "action files:   \(supportsActionFiles ? "available" : "not available")",
            "--debug:        \(isEnabled ? "on for this run" : "off")",
        ]
    }

    /// The flags this binary understands, for a `--help` listing.
    ///
    /// Empty in a release build, so help text describes what the binary can
    /// actually do rather than what some build of it could.
    ///
    /// 本執行檔可辨識的旗標，供 `--help` 列出。
    ///
    /// 在 release 建置中為空，使說明文字描述的是「此執行檔實際能做什麼」，而非「它的某個建置版本
    /// 能做什麼」。
    public static var flagSummary: [String] {
        #if SCUI_DEBUG
        return [
            "--debug                 print diagnostics to stderr",
            "-actionfile <path>      replay a CSV of synthesised input",
        ]
        #else
        return []
        #endif
    }
}
