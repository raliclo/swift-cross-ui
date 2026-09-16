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

    /// Which graphics adapter the backend should ask for: `-GPU N`.
    ///
    /// `0` means no GPU: render in software and do not ask for Direct
    /// Composition. `1` is the default and asks for hardware. `2` and above
    /// also ask for hardware, and additionally name which adapter is wanted.
    ///
    /// Defaults to `1` in every build, release included, because it is a
    /// rendering policy rather than a diagnostic -- only the *flag* is
    /// debug-only, through ``value(after:)``. A release binary therefore takes
    /// the default and cannot be talked out of it on the command line.
    ///
    /// The number is deliberately the same scale as Windows' own
    /// `GpuPreference`: 0 unspecified, 1 power-saving/integrated, 2
    /// high-performance/discrete. That is not a coincidence to be tidied away
    /// -- it is what lets `-GPU 2` mean the same thing here and in the registry
    /// value Windows actually reads.
    ///
    /// backend 應要求哪一張繪圖介面卡：`-GPU N`。
    ///
    /// `0` 表示不使用 GPU：以軟體繪製，且不要求 Direct Composition。`1` 為預設值，要求硬體。
    /// `2` 以上同樣要求硬體，並額外指明想要哪一張介面卡。
    ///
    /// 在所有建置（含 release）中預設為 `1`，因為這是繪製政策而非診斷功能——只有那個**旗標**
    /// 是 debug 限定的（透過 ``value(after:)``）。因此 release 執行檔一律採用預設值，且無法
    /// 由命令列改變。
    ///
    /// 此數字刻意與 Windows 自己的 `GpuPreference` 同一套刻度：0 未指定、1 省電／內顯、
    /// 2 高效能／獨顯。這並非可以順手「整理掉」的巧合——正是它讓 `-GPU 2` 在此處與在 Windows
    /// 實際讀取的登錄檔值中意義相同。
    public static let gpuSelection: Int = {
        guard let raw = value(after: "-GPU"), let n = Int(raw), n >= 0 else { return 1 }
        return n
    }()

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
            "-allow-rootscroll       offer the actualView/rwdView control (release builds)",
        ]
        #else
        return [
            "-allow-rootscroll       offer the actualView/rwdView control",
        ]
        #endif
    }

    /// Whether the root view-mode control may be shown.
    ///
    /// UIKitBackend hosts every window's content in a scroll view so that
    /// content wider than the phone can be reached, and offers a floating
    /// button that switches between showing it at its natural size and scaling
    /// it to fit. That control is a testing affordance, so a release build must
    /// not float it over an application's content by default.
    ///
    /// **`-allow-rootscroll` is read in release builds, and deliberately so.**
    /// Every other flag here goes through ``value(after:)`` or `isEnabled`,
    /// both of which return nothing in a release build -- a diagnostic flag
    /// that a shipped binary honours is a diagnostic flag an attacker honours.
    /// This one is different in kind: it does not enable diagnostics, it makes
    /// an existing piece of user interface visible, and the reason to have it
    /// is that a release build is exactly where you cannot rebuild to see the
    /// control. So the default flips with the build and the flag exists to
    /// override it, rather than the flag being compiled away.
    ///
    /// 是否可顯示根視圖的模式控制項。
    ///
    /// UIKitBackend 把每個視窗的內容都放進一個捲動視圖中，讓比手機寬的內容得以觸及，並提供一個
    /// 浮動按鈕，用以在「以自然尺寸顯示」與「縮放至塞得下」之間切換。該控制項是測試用的輔助功能，
    /// 因此 release 建置不得預設把它浮在應用程式的內容之上。
    ///
    /// **`-allow-rootscroll` 在 release 建置中會被讀取，而這是刻意的。** 此處其他每一個旗標都經由
    /// ``value(after:)`` 或 `isEnabled`，兩者在 release 建置中都不回傳任何東西——一個「已出貨的
    /// 執行檔會採納的診斷旗標」，就是一個「攻擊者也會採納的診斷旗標」。這一個在性質上不同：它不
    /// 開啟任何診斷功能，只是讓一個既有的使用者介面元件變為可見；而需要它的理由正是——release
    /// 建置恰恰是你無法靠重新建置來看見該控制項的那種建置。因此預設值隨建置而翻轉，並由旗標來
    /// 覆寫它，而不是把旗標本身編譯掉。
    public static let allowsRootScrollControl: Bool = {
        #if SCUI_DEBUG
        return true
        #else
        return CommandLine.arguments.contains("-allow-rootscroll")
        #endif
    }()
}

extension DebugFeatures {
    /// How many lazy list-row nodes the framework is currently holding.
    ///
    /// **A conformance readout cannot answer the question this answers.** P57
    /// already prints whether a backend conforms to
    /// `BackendFeatures.LazyListRowLifetimes`, and that is a claim about a type,
    /// not about a callback ever arriving -- Android once compiled a conformance
    /// and took the other path anyway, which is why P57 asks the backend rather
    /// than the file list in the first place. This counts the thing the feature
    /// exists to bound: visit four hundred rows, and a list whose backend
    /// reports releases settles near the size of the visible window, while one
    /// that does not climbs towards
    /// `ListViewChildren.lazyLifetimeBackstopLimit`.
    ///
    /// Written by `List` and read by a test app. `nonisolated(unsafe)` because
    /// every access is on the main thread -- a layout pass writes it, a view
    /// body reads it -- and because a lock here would be a cost paid by a
    /// release build to serve a debug readout.
    ///
    /// 框架當下持有多少個 lazy 清單列節點。
    ///
    /// **一行 conformance 讀數回答不了這個問題。** P57 已經會印出某個 backend 是否 conform 到
    /// `BackendFeatures.LazyListRowLifetimes`,而那是關於一個**型別**的主張,不是關於「那個回呼
    /// 曾經抵達」的主張——Android 曾經把一個 conformance 編了進去、然後照樣走了另一條路,而那正是
    /// P57 一開始就去問 backend、而不是去看有哪些檔案的理由。這個數字量的是這項功能存在所要限制的
    /// 那個東西:走過四百列之後,一個「backend 會回報釋放」的清單會穩定在可見視窗大小附近,
    /// 而一個不會回報的則會朝 `ListViewChildren.lazyLifetimeBackstopLimit` 爬上去。
    ///
    /// 由 `List` 寫入,由測試 app 讀取。標為 `nonisolated(unsafe)`,因為每一次存取都在主執行緒上
    /// ——一次版面計算寫它,一個 view 的 body 讀它——也因為在此加鎖,會是讓 release 建置為了一行
    /// debug 讀數而付出的代價。
    nonisolated(unsafe) public private(set) static var liveLazyListRows = 0

    public static func recordLiveLazyListRows(_ count: Int) {
        #if SCUI_DEBUG
        liveLazyListRows = count
        #endif
    }

    /// How many lazy list-row nodes have been BUILT since launch, counting
    /// every rebuild.
    ///
    /// **This is the half that makes the live count mean something.** On its
    /// own, "holding 6" is consistent with a backend that releases properly and
    /// with one that was never asked to show more than six rows -- and telling
    /// those apart from a screenshot means reasoning about how far a scroll
    /// travelled, which is exactly the kind of arithmetic that turns into a
    /// claim nobody can check. Built against held answers it directly:
    ///
    ///     built 250, holding 6     rows are being released
    ///     built 250, holding 250   nothing is
    ///
    /// Monotonic, and never reset. A reset would need a moment to reset AT, and
    /// every candidate -- a commit, a reload, a row count change -- is a moment
    /// this number is supposed to see through.
    ///
    /// 自啟動以來,總共**建立**過多少個 lazy 清單列節點——重建也算。
    ///
    /// **這是讓那個「現在持有幾個」有意義的另一半。** 單看「持有 6」,它既相容於「一個正確釋放的
    /// backend」,也相容於「一個從未被要求顯示超過六列的 backend」——而要從一張截圖分辨這兩者,
    /// 就得去推算一次捲動走了多遠,而那正是那種會變成「沒有人查得動的主張」的算術。
    /// 「建過幾個」對上「持有幾個」直接回答了它:
    ///
    ///     建過 250、持有 6      各列正在被釋放
    ///     建過 250、持有 250    什麼都沒有被釋放
    ///
    /// 單調遞增,永不重設。要重設就得有一個「重設的時點」,而每一個候選時點——一次 commit、一次
    /// reload、一次列數改變——都正是這個數字應該要能看穿的東西。
    nonisolated(unsafe) public private(set) static var builtLazyListRows = 0

    public static func countLazyListRowBuilt() {
        #if SCUI_DEBUG
        builtLazyListRows += 1
        #endif
    }
}
