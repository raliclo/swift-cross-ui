import DefaultBackend
import Foundation
import SwiftCrossUI

#if os(Windows)
    import WinSDK
#endif

// P52 measures what a custom `ButtonStyle` costs against a `PrimitiveButtonStyle`,
// per press and at first render. It exists because the cost argument for the
// 2026-09-08 button-style landing was REASONED AND NEVER MEASURED.
//
// The reasoning under test, quoted from the request that produced this file:
// primitive is cheaper, because both arms now pay one `AnyView` container per
// button (`Button.Children` is `TupleViewChildren1<AnyView>` unconditionally),
// and a custom style additionally pays, per press transition, a `State` write ->
// `didChange.send()` -> `bottomUpUpdate` -> `computeLayout` -> `makeBody` ->
// `AnyView` -> `commit`.
//
// READING THE SOURCE BEFORE MEASURING ALREADY REFINES THAT, and the refinement
// is the reason the measurement is worth taking rather than a formality:
//
//   - `installPressHandler` is called from `Button.commit` for EVERY button
//     (`Button.swift:349`), not only styled ones, and its guard passes on all
//     five shipped backends. So a press on a `.bordered` button ALSO writes
//     `isPressed`, ALSO publishes, ALSO re-enters `computeLayout` and ALSO
//     commits. The whole update chain the reasoning attributes to the custom
//     style is paid by both arms.
//   - What is genuinely extra for the custom arm is only the inside of
//     `styledLabel(in:)` (`Button.swift:206-220`): `ButtonStyleConfiguration.init`
//     (which builds ONE `AnyView` of the label), `style.makeBody(configuration:)`
//     through an existential, `AnyView` of the result, and then the layout of
//     whatever view tree the body produced. The primitive arm's branch of the
//     same function is one line, `return AnyView(label())`.
//   - The saving the reasoning credits to the custom arm is smaller than it
//     sounds. `Button.buttonEnvironment(from:)` forces `.plain`, and
//     `buttonPadding(in:)` then returns `SIMD2(0, 0)` instead of
//     `measureBorderedButtonPadding()` -- but that measurement is CACHED on both
//     Windows backends (`GtkBackend+Button.swift:107`,
//     `WinUIBackend+Button.swift:35`, both `if let borderedButtonPadding { return
//     borderedButtonPadding }`). The saving is one cached return and two integer
//     subtractions, not a measurement.
//
// So the honest question is not "does the custom style add a whole update
// chain" -- it does not -- but "how much does makeBody plus one extra AnyView
// plus the style body's own layout add to an update both arms already pay".
// That is what this app times. If the answer is small, the reasoning's
// CONCLUSION survives while its ARGUMENT does not, and that distinction is the
// result worth reporting.
//
// P52 量測自訂 `ButtonStyle` 相對於 `PrimitiveButtonStyle` 的代價：每次按壓一次，以及首次繪製
// 一次。它之所以存在，是因為 2026-09-08 按鈕樣式落地時的成本論證**只有推理、從未量測**。
//
// 受測的推理，引自產生本檔的那份請求：primitive 比較便宜，因為兩邊現在每顆按鈕都要付一個
// `AnyView` 容器（`Button.Children` 無條件是 `TupleViewChildren1<AnyView>`），而自訂樣式在每一次
// 按壓轉換上還要額外付出 `State` 寫入 -> `didChange.send()` -> `bottomUpUpdate` ->
// `computeLayout` -> `makeBody` -> `AnyView` -> `commit`。
//
// **在量測之前先讀原始碼，就已經修正了這段推理**，而這項修正正是「這次量測值得做、而非只是走個
// 形式」的理由：
//
//   - `installPressHandler` 是由 `Button.commit` 對**每一顆**按鈕呼叫的（`Button.swift:349`），
//     不只針對有樣式的那些，且其 guard 在五個已發布 backend 上全都通過。因此按下一顆 `.bordered`
//     按鈕**同樣**會寫入 `isPressed`、**同樣**會發布、**同樣**會重新進入 `computeLayout`、
//     **同樣**會 commit。推理歸給自訂樣式的那整條更新鏈，其實兩邊都在付。
//   - 自訂那一邊真正多出來的，只有 `styledLabel(in:)` 內部（`Button.swift:206-220`）：
//     `ButtonStyleConfiguration.init`（它會建一個 label 的 `AnyView`）、透過 existential 呼叫
//     `style.makeBody(configuration:)`、把結果包成 `AnyView`，以及該 body 所產生之 view 樹的排版。
//     primitive 那一邊在同一個函式中的分支只有一行：`return AnyView(label())`。
//   - 推理算給自訂那一邊的「節省」比聽起來小。`Button.buttonEnvironment(from:)` 會強制 `.plain`，
//     於是 `buttonPadding(in:)` 回傳 `SIMD2(0, 0)` 而非 `measureBorderedButtonPadding()`——但那次
//     量測在兩個 Windows backend 上都是**有快取的**（`GtkBackend+Button.swift:107`、
//     `WinUIBackend+Button.swift:35`，皆為 `if let borderedButtonPadding { return
//     borderedButtonPadding }`）。所省下的是一次快取回傳與兩次整數相減，不是一次量測。
//
// 因此誠實的問題不是「自訂樣式是否多加了一整條更新鏈」——它沒有——而是「在兩邊都已經要付的那次更新
// 之上，makeBody 加上一個額外的 AnyView 加上樣式 body 自身的排版，究竟多花了多少」。這正是本 app
// 所計時的東西。若答案很小，那麼該推理的**結論**成立而其**論證**不成立，而這個區別正是值得回報的
// 結果。

// MARK: - Process CPU time
//
// Wall time says which arm is slower; user and sys say whether the difference is
// computation or system calls, and those need opposite fixes. Two conclusions on
// this project were overturned for reading wall time alone, which is why this is
// here rather than left out as a nicety.
//
// TWO IMPLEMENTATIONS, AND NO `getrusage`. On Windows, `GetProcessTimes` is the
// only route -- `clock()` in Microsoft's CRT returns WALL time since process
// start, not CPU time, so it would silently duplicate the wall measurement with
// a different name. On Linux this reads `/proc/self/stat` fields 14 and 15
// rather than calling `getrusage`, because `RUSAGE_SELF` imports differently
// across Glibc versions and a file read cannot fail to compile. Everywhere else
// returns nil and the report says the numbers are unavailable rather than
// printing zeroes that look like a measurement.
//
// BOTH CLOCKS ARE COARSE, and the report states it next to the numbers:
// `GetProcessTimes` advances on the scheduler tick (~15.6 ms on this host) and
// `/proc/self/stat` counts in USER_HZ (10 ms). That is why CPU is accumulated
// across every sample in a phase and reported as a phase total, never per
// sample -- a per-sample CPU delta at this resolution is mostly zero and
// occasionally one tick, which is noise wearing a number's clothes.
//
// 掛鐘時間說的是哪一邊比較慢；user 與 sys 說的是差異出在計算還是系統呼叫，而這兩者的修法相反。
// 本專案已有兩項結論因為只讀掛鐘時間而被推翻，這才是它出現在此處的理由，而不是因為順手。
//
// **兩種實作，且都不用 `getrusage`。** 在 Windows 上，`GetProcessTimes` 是唯一的路——Microsoft CRT
// 的 `clock()` 回傳的是行程啟動以來的**掛鐘**時間而非 CPU 時間，用它只會換個名字把掛鐘量測再做
// 一次。在 Linux 上此處讀 `/proc/self/stat` 的第 14、15 欄而不呼叫 `getrusage`，因為 `RUSAGE_SELF`
// 在不同 Glibc 版本下的匯入方式不一，而讀檔不可能編不過。其餘平台回傳 nil，報告會說明數字不可得，
// 而不是印出一組看起來像量測結果的零。
//
// **兩個時鐘都很粗**，而報告會把這件事寫在數字旁邊：`GetProcessTimes` 依排程器 tick 前進（本機約
// 15.6 毫秒），`/proc/self/stat` 以 USER_HZ（10 毫秒）計數。這正是為何 CPU 是在一個階段中累加所有
// 樣本、並以階段總計回報，絕不逐樣本回報——在這個解析度下，逐樣本的 CPU 差值大多是零、偶爾是一個
// tick，那是穿著數字外衣的雜訊。
struct P52CPUTimes {
    var user: Double
    var system: Double

    static let zero = P52CPUTimes(user: 0, system: 0)

    static func + (lhs: P52CPUTimes, rhs: P52CPUTimes) -> P52CPUTimes {
        P52CPUTimes(user: lhs.user + rhs.user, system: lhs.system + rhs.system)
    }

    static func - (lhs: P52CPUTimes, rhs: P52CPUTimes) -> P52CPUTimes {
        P52CPUTimes(user: lhs.user - rhs.user, system: lhs.system - rhs.system)
    }

    /// This process's accumulated user and system CPU time, in seconds, or nil
    /// where the platform is not covered.
    /// 本行程累計的 user 與 system CPU 時間（秒），若平台未涵蓋則為 nil。
    static func read() -> P52CPUTimes? {
        #if os(Windows)
            var creationTime = FILETIME()
            var exitTime = FILETIME()
            var kernelTime = FILETIME()
            var userTime = FILETIME()
            // The return value is discarded rather than checked. `BOOL` imports
            // differently across Swift/WinSDK versions (Int32, WindowsBool), and
            // a comparison that does not compile would cost more than the check
            // is worth: on failure the FILETIMEs stay zero-initialised, the
            // deltas come out zero, and the report shows a zero CPU total, which
            // is visibly wrong rather than quietly wrong.
            // 此處刻意丟棄回傳值而不檢查。`BOOL` 在不同 Swift/WinSDK 版本下的匯入型別不同
            // （Int32、WindowsBool），一個編不過的比較所付出的代價高於該檢查的價值：失敗時
            // FILETIME 維持零初始化，差值為零，報告會顯示零的 CPU 總計——那是看得出來的錯，
            // 而不是安靜的錯。
            _ = GetProcessTimes(
                GetCurrentProcess(),
                &creationTime,
                &exitTime,
                &kernelTime,
                &userTime
            )
            return P52CPUTimes(
                user: p52FileTimeSeconds(userTime),
                system: p52FileTimeSeconds(kernelTime)
            )
        #elseif os(Linux) || os(Android)
            guard
                let raw = try? String(contentsOfFile: "/proc/self/stat", encoding: .utf8),
                // The `comm` field is parenthesised and may itself contain
                // spaces and brackets, so the split has to start after the LAST
                // ')' rather than at the second field.
                // `comm` 欄位帶括號且其內容本身可能含空白與括號，因此切分必須從**最後**一個
                // ')' 之後開始，而不是從第二欄開始。
                let closingBracket = raw.lastIndex(of: ")")
            else {
                return nil
            }

            let fields = raw[raw.index(after: closingBracket)...].split(separator: " ")
            // fields[0] is `state`, which is field 3 of the line. utime is field
            // 14 and stime is field 15, hence 11 and 12 here.
            // fields[0] 是 `state`，即整行的第 3 欄。utime 是第 14 欄、stime 是第 15 欄，
            // 因此此處為 11 與 12。
            guard
                fields.count > 12,
                let userTicks = Double(fields[11]),
                let systemTicks = Double(fields[12])
            else {
                return nil
            }

            // USER_HZ is 100 on every Linux this project builds for. Named
            // rather than inlined so the assumption is visible.
            // 本專案所建置的每一種 Linux 上，USER_HZ 都是 100。此處具名而非內嵌，讓這項假設
            // 看得見。
            let userHz = 100.0
            return P52CPUTimes(user: userTicks / userHz, system: systemTicks / userHz)
        #else
            return nil
        #endif
    }
}

#if os(Windows)
    /// A `FILETIME` counts 100-nanosecond intervals across two 32-bit halves.
    /// `FILETIME` 以兩個 32 位元半部計數 100 奈秒為單位的區間。
    func p52FileTimeSeconds(_ value: FILETIME) -> Double {
        let ticks = (UInt64(value.dwHighDateTime) << 32) | UInt64(value.dwLowDateTime)
        return Double(ticks) / 10_000_000.0
    }
#endif

/// A monotonic timestamp in nanoseconds.
///
/// `DispatchTime`, not `Date`: `Date` is wall-clock and steps when the system
/// clock is adjusted, which on an interval of a few milliseconds can produce a
/// negative elapsed time that reads as an impossibly fast arm.
///
/// 以奈秒表示的單調時間戳記。
///
/// 用 `DispatchTime` 而非 `Date`：`Date` 是掛鐘時間，會在系統時鐘被調整時跳動，而在數毫秒等級的
/// 區間上，那可能產生負的經過時間，讀起來就像某一邊快得不可能。
func p52Now() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

// MARK: - Diagnostics

/// P22's writer, unchanged apart from the app name and the log file.
///
/// Deliberately not a second measurement style. P22 gates on `--debug`, prints
/// one line per fact with `[Pnn]` on stdout, appends the same line to
/// `pnn-debug-events.log` under `SCUI_DEBUG_EVENTS_DIR`, and ends with a
/// `RENDER COMPLETE` marker an action file can wait on. A reader comparing P22's
/// output with P52's should not have to translate between two formats to do it.
///
/// 與 P22 的寫入器相同，只換了 app 名稱與 log 檔名。
///
/// 刻意不另立第二套量測風格。P22 以 `--debug` 為開關、每項事實印一行並在 stdout 前綴 `[Pnn]`、把同
/// 一行附加到 `SCUI_DEBUG_EVENTS_DIR` 下的 `pnn-debug-events.log`，並以動作檔可等待的
/// `RENDER COMPLETE` 標記作結。想並排比較 P22 與 P52 輸出的讀者，不該還要先在兩種格式之間翻譯。
enum P52Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P52] \(message)")

        guard let data = "P52 \(Date()) \(message)\n".data(using: .utf8) else { return }
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p52-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Models

/// One arm's state: how many buttons it holds, and a generation counter.
///
/// **One model object per arm, and that is the whole reason the arms can be
/// timed separately.** `ViewGraphNode` subscribes to a view's observable
/// properties when the node is created (`ViewGraphNode.swift:139`), so a change
/// published here schedules `bottomUpUpdate()` on the node of the view that
/// holds THIS object and no other. A single shared model would have re-laid out
/// every arm on every tick, and the three numbers would all have been the same
/// number.
///
/// `SwiftCrossUI.` on both wrapper names for the reason P46 records: Foundation
/// re-exports Combine's `ObservableObject` and `Published` on Apple platforms,
/// and unqualified names then fail to build there with "is ambiguous for type
/// lookup in this context" while building fine on Windows, WSL and Android.
///
/// 一個 arm 的狀態：它持有幾顆按鈕，以及一個世代計數器。
///
/// **每個 arm 一個 model 物件，而這正是三個 arm 能被分開計時的全部理由。** `ViewGraphNode` 在建立
/// 節點時訂閱該 view 的可觀察屬性（`ViewGraphNode.swift:139`），因此此處發布的一次變更，只會在持有
/// **這一個**物件的 view 之節點上排入 `bottomUpUpdate()`，不會影響其他節點。若共用單一 model，每次
/// tick 都會重新排版每一個 arm，三個數字最後會是同一個數字。
///
/// 兩個包裝器名稱都加上 `SwiftCrossUI.`，理由如 P46 所記：Apple 平台上 Foundation 會再匯出 Combine
/// 的 `ObservableObject` 與 `Published`，未加限定時會在該處以「is ambiguous for type lookup in this
/// context」失敗，卻在 Windows、WSL 與 Android 上建得起來。
final class P52ArmModel: SwiftCrossUI.ObservableObject {
    /// Bumped once per timed press sample. Nothing reads it for its value; it is
    /// handed to the grid so that the recomputed body genuinely differs, which is
    /// what a press does to `Button.isPressed`.
    /// 每個計時的按壓樣本遞增一次。沒有人讀它的數值；它被交給 grid，好讓重新計算出的 body 確實
    /// 不同——那正是一次按壓對 `Button.isPressed` 所做的事。
    @SwiftCrossUI.Published var generation = 0

    /// False collapses the arm to zero buttons. Toggling it false then true is
    /// the first-render measurement, and it is kept strictly apart from
    /// `generation` because the two answer different questions.
    /// 設為 false 會讓該 arm 塌縮成零顆按鈕。先設 false 再設 true 就是首次繪製的量測，而它與
    /// `generation` 嚴格分開，因為兩者回答的是不同的問題。
    @SwiftCrossUI.Published var mounted = true
}

/// The lines shown on screen once the run has finished.
///
/// Published ONCE, at the end. Every publish re-lays out the root and therefore
/// both arms, so a progress display that updated as it went would have been
/// measuring itself.
///
/// 執行結束後顯示於畫面上的文字行。
///
/// **只發布一次**，在最後。每一次發布都會重新排版 root、進而重排兩個 arm，因此一個「邊跑邊更新」的
/// 進度顯示，量到的會是它自己。
final class P52ResultsModel: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var lines: [String] = []
}

// MARK: - The style under test

/// A custom ``ButtonStyle``, written the way the protocol's own documentation
/// writes one.
///
/// The exact requirement, quoted from `ButtonStyle.swift:65`:
///
///     func makeBody(configuration: Configuration) -> Body
///
/// with `Configuration` a typealias for `ButtonStyleConfiguration`, whose `label`
/// is `AnyView` (`ButtonStyle.swift:100`).
///
/// **`highlighted` exists so that a timed sample changes the body the way a real
/// press changes it.** `isPressed` cannot be driven from inside the app --
/// `Button.isPressed` is `@State private` and only the backend's press handler
/// writes it -- so a benchmark that only re-ran `makeBody` with an unchanged
/// result would have measured a cheaper thing than a press. `configuration.isPressed`
/// is read as well, so a real click on this screen still lights the button and
/// the picture agrees with the numbers.
///
/// 一個自訂的 ``ButtonStyle``，寫法比照該 protocol 自身文件中的範例。
///
/// 其確切的 requirement，引自 `ButtonStyle.swift:65`：
///
///     func makeBody(configuration: Configuration) -> Body
///
/// 其中 `Configuration` 是 `ButtonStyleConfiguration` 的 typealias，而後者的 `label` 型別為
/// `AnyView`（`ButtonStyle.swift:100`）。
///
/// **`highlighted` 的存在，是為了讓一個計時樣本以「真實按壓改變 body 的方式」改變 body。**
/// `isPressed` 無法從 app 內部驅動——`Button.isPressed` 是 `@State private`，只有 backend 的按壓
/// handler 會寫它——因此若基準測試只是以不變的結果重跑 `makeBody`，量到的會是比一次按壓更便宜的
/// 東西。此處同時也讀取 `configuration.isPressed`，因此在這個畫面上真的點一下仍會讓按鈕亮起，
/// 圖與數字彼此一致。
struct P52PressStyle: ButtonStyle {
    var highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(3)
            .border(
                (highlighted || configuration.isPressed) ? Color.orange : Color.gray,
                width: 2
            )
    }
}

// MARK: - The benchmark

/// The measurement engine: configuration, the schedule, the driver and the
/// report.
///
/// ## What is measured, and what is not
///
/// **Measured.** The interval from the instant a state write is issued on one
/// arm to the instant that arm's layout subtree stops moving. That covers the
/// publish, the hop through `Publisher.observeAsUIUpdater`'s serial queue and
/// `backend.runInMainThread` (`Publisher.swift:104-133`), `bottomUpUpdate`,
/// every layout pass the update produces INCLUDING the layout system's
/// flexibility probes, `styledLabel(in:)` for each button, and `commit`.
///
/// **Not measured.** Anything before the state write: the platform's own
/// delivery of a mouse-down to the widget, and the backend's press handler up to
/// the point it assigns `isPressedState.wrappedValue`. Also not measured: what
/// the platform draws for a `.bordered` button's own pressed appearance, which
/// happens inside the toolkit and never calls back into Swift. That last
/// exclusion FAVOURS the primitive arm, and is stated because a reader who does
/// not know it would over-read the result.
///
/// **Why not real clicks.** Driving presses from an action file would time the
/// synthesiser and the toolkit's event loop as well, and would cap the sample
/// count at whatever a CSV can hold. Relaunching per sample was rejected
/// outright: process spawn on this host costs 20-100x what it does on Linux, so
/// a per-launch design measures the launcher.
///
/// **Why a state write is a fair stand-in for a press.** `Button.isPressed` is a
/// `@State` like any other and its comment says so: "a press is an ordinary
/// state change and gets the ordinary re-render" (`Button.swift:34`). The write
/// here enters the same publisher machinery at the same point. The one honest
/// difference is scale: a real press re-lays out ONE button, this re-lays out N,
/// so the per-pass fixed overhead is amortised here and is not in a real press.
/// That is exactly why the control arm exists -- it measures that overhead
/// directly so it can be subtracted rather than assumed away.
///
/// 量測引擎：組態、排程、驅動器與報告。
///
/// ## 量到什麼、沒量到什麼
///
/// **量到的。** 從「在某個 arm 上發出一次 state 寫入」到「該 arm 的排版子樹停止變動」之間的區間。
/// 這涵蓋了發布、經由 `Publisher.observeAsUIUpdater` 的序列佇列與 `backend.runInMainThread`
/// （`Publisher.swift:104-133`）的跳轉、`bottomUpUpdate`、該次更新所產生的每一趟排版（**包含**排版
/// 系統的彈性探測）、每顆按鈕的 `styledLabel(in:)`，以及 `commit`。
///
/// **沒量到的。** state 寫入之前的一切：平台自身把 mouse-down 送達 widget，以及 backend 的按壓
/// handler 直到它指派 `isPressedState.wrappedValue` 為止。同樣沒量到的還有：平台為一顆 `.bordered`
/// 按鈕自身的按下外觀所繪製的東西——那發生在工具箱內部，從不回呼 Swift。最後這項排除**對 primitive
/// 那一邊有利**，此處寫明，是因為不知道這件事的讀者會過度解讀結果。
///
/// **為何不用真實點擊。** 以動作檔驅動按壓會連合成器與工具箱的事件迴圈一併計時，而且樣本數會被
/// CSV 能容納的行數封頂。「每個樣本重啟一次行程」則直接否決：本機的行程啟動成本是 Linux 的 20 到
/// 100 倍，這種設計量到的是啟動器。
///
/// **為何一次 state 寫入是按壓的公允替身。** `Button.isPressed` 與其他任何 `@State` 無異，它的註解
/// 也這麼說：「按下就是一次普通的狀態改變，得到的也是普通的重新繪製」（`Button.swift:34`）。此處的
/// 寫入是在同一個位置進入同一套 publisher 機制。唯一誠實的差別在規模：真實按壓重排**一顆**按鈕，
/// 此處重排 N 顆，因此每趟的固定額外開銷在此被攤提，而真實按壓中並沒有被攤提。這正是 control arm
/// 存在的理由——它直接量出該開銷，好讓它被**減掉**而不是被假設掉。
enum P52Bench {
    // MARK: Arm identity

    static let control = 0
    static let primitive = 1
    static let custom = 2
    static let armCount = 3
    static let armNames = ["control", "primitive", "custom"]

    // MARK: Configuration

    /// Buttons per arm.
    ///
    /// **48, and the count is on every line of the report so nothing has to be
    /// remembered.** It was picked to make the arm's own work several times the
    /// fixed per-pass overhead -- and rather than assert that ratio, the control
    /// arm measures it, so a reader can divide the two printed numbers and check.
    /// If `control` is not comfortably smaller than `primitive`, the count is too
    /// low on that machine and `--buttons=N` raises it; the report says so in
    /// those words when the margin is thin.
    ///
    /// The ceiling is the window: 48 buttons in 8 columns is a 6-row block that
    /// fits beside a second one at 1000 points wide, and both arms must be
    /// on screen at once so that neither pays a construction cost the other does
    /// not.
    ///
    /// 每個 arm 的按鈕數。
    ///
    /// **48，且報告的每一行都附上這個數字，因此不需要記住它。** 選它是為了讓 arm 自身的工作量達到
    /// 每趟固定開銷的數倍——而此處不去斷言這個比值，改由 control arm 量出來，讓讀者可以把兩個印出來
    /// 的數字相除自行核對。若 `control` 沒有明顯小於 `primitive`，代表在該機器上這個數量太低，
    /// `--buttons=N` 可以調高；當餘裕不足時，報告會照這個意思寫出來。
    ///
    /// 上限來自視窗：48 顆按鈕排成 8 欄即 6 列，在 1000 點寬之下能與另一塊並排，而兩個 arm 必須同時
    /// 在畫面上，如此才不會有一邊付出另一邊沒付的建構成本。
    static let buttonsPerArm = intArgument("--buttons=", fallback: 48)
    static let columns = intArgument("--columns=", fallback: 8)

    /// Ten rounds, because six has been dominated by an outlier on this project
    /// before.
    /// 十輪，因為在本專案上六輪曾被一個離群值主導。
    static let rounds = intArgument("--rounds=", fallback: 10)
    static let passesPerRound = intArgument("--passes=", fallback: 5)
    static let mountsPerRound = intArgument("--mounts=", fallback: 1)

    /// How the driver decides an update has finished.
    ///
    /// A `GeometryReader` closure runs inside `GeometryReader.computeLayout`
    /// (`GeometryReader.swift:63`), so it fires on EVERY layout pass -- and the
    /// layout system probes each view with width 0 and width infinity before the
    /// real pass, which P22 records as producing two contradictory readings per
    /// sample. So a single firing is not the end of the update. The driver
    /// instead polls until the arm's most recent firing is `quietMillis` old, and
    /// takes that firing as the end. Bounded by `maxPolls` so a wedged update
    /// reports a miss instead of hanging the app.
    ///
    /// 驅動器如何判定一次更新已結束。
    ///
    /// `GeometryReader` 的 closure 在 `GeometryReader.computeLayout` 內執行
    /// （`GeometryReader.swift:63`），因此它在**每一趟**排版都會觸發——而排版系統會在真正那一趟之前
    /// 以寬度 0 與寬度無限大探測每個 view，P22 記錄過這會使每個樣本產生兩個互相矛盾的讀數。所以單次
    /// 觸發並不等於更新結束。驅動器改為輪詢，直到該 arm 最近一次觸發已經靜止 `quietMillis`，並以
    /// 那次觸發作為結束點。以 `maxPolls` 設限，好讓卡住的更新回報一次 miss 而不是把 app 掛住。
    static let pollMillis = intArgument("--poll=", fallback: 15)
    static let quietMillis = intArgument("--quiet=", fallback: 45)
    static let maxPolls = intArgument("--max-polls=", fallback: 80)
    static let warmupMillis = intArgument("--warmup=", fallback: 2000)

    static let armWidth = 340.0
    static let armHeight = 230.0

    /// The primitive arm's style, and the reason it is spelled as a typed nil.
    ///
    /// `.buttonStyle(nil)` reaches the `PrimitiveButtonStyle?` overload only --
    /// `ButtonStyleModifier.swift:14` says so: "`nil` reaches only this one, since
    /// `S` cannot be inferred from it". Naming the type here removes even that
    /// question from the call site.
    ///
    /// **A typed nil, not `.bordered`, and the difference is availability not
    /// meaning.** `PrimitiveButtonStyle.bordered` carries
    /// `@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *)`
    /// (`PrimitiveButtonStyle.swift:62`), and this package's deployment target is
    /// `.iOS(.v13)`, so writing it would need an `if #available` ladder or would
    /// break the iOS build of a file that has no reason to touch it. With nil,
    /// `EnvironmentValues.resolvedButtonStyle` falls back to
    /// `defaultButtonStyle()`, which BOTH Windows backends return as `.bordered`
    /// (`GtkBackend+Button.swift:103`, `WinUIBackend+Button.swift:32`). The arm
    /// therefore gets real bordered chrome, and `Button.computeLayout` runs the
    /// identical path it would for an explicit `.bordered`: same
    /// `resolvedButtonStyle`, same `buttonPadding`, same one-line branch of
    /// `styledLabel(in:)`.
    ///
    /// primitive 那一邊所用的樣式，以及它為何寫成一個帶型別的 nil。
    ///
    /// `.buttonStyle(nil)` 只會解析到 `PrimitiveButtonStyle?` 那個多載——`ButtonStyleModifier.swift:14`
    /// 就是這麼說的：「至於 `nil`，只有本版本收得到，因為由它推導不出 `S`」。此處指名型別，是為了讓
    /// 呼叫端連這個問題都不必存在。
    ///
    /// **用帶型別的 nil 而非 `.bordered`，差別在可用性標註而非語意。**
    /// `PrimitiveButtonStyle.bordered` 帶有 `@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *)`
    /// （`PrimitiveButtonStyle.swift:62`），而本套件的部署目標是 `.iOS(.v13)`，因此寫它就需要一整段
    /// `if #available`，否則會弄壞一個根本不需要碰它的檔案之 iOS 建置。用 nil 時，
    /// `EnvironmentValues.resolvedButtonStyle` 會退回 `defaultButtonStyle()`，而**兩個** Windows
    /// backend 都回傳 `.bordered`（`GtkBackend+Button.swift:103`、`WinUIBackend+Button.swift:32`）。
    /// 因此這一邊拿到的是真正的有框外觀，而 `Button.computeLayout` 走的路徑與明寫 `.bordered` 完全
    /// 相同：同一個 `resolvedButtonStyle`、同一個 `buttonPadding`、`styledLabel(in:)` 中同一個
    /// 只有一行的分支。
    static let primitiveStyle: PrimitiveButtonStyle? = nil

    // MARK: Shared state

    nonisolated(unsafe) static let models = [P52ArmModel(), P52ArmModel(), P52ArmModel()]
    nonisolated(unsafe) static let results = P52ResultsModel()

    /// The last time each arm's sentinel `GeometryReader` ran, in nanoseconds.
    /// 每個 arm 的哨兵 `GeometryReader` 最後一次執行的時間，單位為奈秒。
    nonisolated(unsafe) static var lastSentinel = [UInt64](repeating: 0, count: 3)

    nonisolated(unsafe) static var pressRounds: [[[Double]]] = []
    nonisolated(unsafe) static var mountRounds: [[[Double]]] = []
    nonisolated(unsafe) static var pressCPU = [P52CPUTimes](repeating: .zero, count: 3)
    nonisolated(unsafe) static var mountCPU = [P52CPUTimes](repeating: .zero, count: 3)
    nonisolated(unsafe) static var misses = [Int](repeating: 0, count: 3)
    nonisolated(unsafe) static var cpuAvailable = false
    nonisolated(unsafe) static var steps: [P52Step] = []
    nonisolated(unsafe) static var stepIndex = 0
    nonisolated(unsafe) static var didStart = false

    // MARK: Argument parsing

    static func intArgument(_ prefix: String, fallback: Int) -> Int {
        for argument in CommandLine.arguments where argument.hasPrefix(prefix) {
            if let value = Int(argument.dropFirst(prefix.count)), value >= 0 {
                return value
            }
        }
        return fallback
    }

    /// Called from the sentinel overlay on each arm.
    /// 由每個 arm 上的哨兵 overlay 呼叫。
    static func markSentinel(_ arm: Int) {
        lastSentinel[arm] = p52Now()
    }
}

/// One scheduled sample.
/// 一個排定的樣本。
struct P52Step {
    var round: Int
    var arm: Int
    var isMount: Bool
}

// MARK: - Driver

extension P52Bench {
    /// Builds the schedule and starts it after a warm-up.
    ///
    /// The warm-up is not politeness. The first samples after a window appears
    /// include font measurement, `measureBorderedButtonPadding()` populating its
    /// cache, and whatever the toolkit does on its first frames -- all of which
    /// land on whichever arm happens to be scheduled first.
    ///
    /// 建立排程，並在暖機之後啟動它。
    ///
    /// 暖機不是禮貌。視窗出現後的最初幾個樣本會包含字型量測、`measureBorderedButtonPadding()` 填入
    /// 其快取，以及工具箱在最初幾幀所做的任何事——而這些全都會落在剛好被排在最前面的那個 arm 上。
    static func start() {
        guard !didStart else { return }
        didStart = true

        cpuAvailable = P52CPUTimes.read() != nil
        buildSchedule()

        let empty = [[Double]](repeating: [], count: max(rounds, 1))
        pressRounds = [[[Double]]](repeating: empty, count: armCount)
        mountRounds = [[[Double]]](repeating: empty, count: armCount)

        P52Diagnostics.write(
            "CONFIG buttons/arm=\(buttonsPerArm) columns=\(columns) rounds=\(rounds) "
                + "press-passes/round=\(passesPerRound) mounts/round=\(mountsPerRound) "
                + "steps=\(steps.count)"
        )
        P52Diagnostics.write(
            "CONFIG poll=\(pollMillis)ms quiet=\(quietMillis)ms max-polls=\(maxPolls) "
                + "warmup=\(warmupMillis)ms cpu-clock=\(cpuClockName())"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(warmupMillis)) {
            runStep()
        }
    }

    static func cpuClockName() -> String {
        #if os(Windows)
            return cpuAvailable ? "GetProcessTimes (~15.6ms tick)" : "unavailable"
        #elseif os(Linux) || os(Android)
            return cpuAvailable ? "/proc/self/stat (10ms USER_HZ)" : "unavailable"
        #else
            return "unavailable on this platform"
        #endif
    }

    /// Round-robin over the three arms, rotating which one goes first.
    ///
    /// **Interleaved, never all-of-one-then-all-of-the-other.** On this project
    /// repeated heavy work has made later measurements monotonically worse
    /// (1.74 -> 3.08 -> 5.45 -> 5.99 s), which makes whichever arm ran first look
    /// faster. Rotating the starting arm per round removes the within-round
    /// ordering bias on top of that: over ten rounds each arm leads three or four
    /// of them.
    ///
    /// The press phase runs to completion before the mount phase begins, because
    /// mounting destroys and recreates 48 widgets and leaves the toolkit in a
    /// different state than steady-state re-layout does. Mixing them would put
    /// that cost inside the press numbers.
    ///
    /// 對三個 arm 做輪替，並旋轉誰先跑。
    ///
    /// **交錯進行，絕不「先跑完一邊再跑另一邊」。** 在本專案上，重複的繁重工作使得較晚的量測單調
    /// 變差（1.74 -> 3.08 -> 5.45 -> 5.99 秒），這會讓先跑的那一邊看起來比較快。每輪旋轉起始 arm 則
    /// 進一步消除輪內的順序偏差：十輪下來，每個 arm 各領先三到四輪。
    ///
    /// 按壓階段會完全跑完才開始掛載階段，因為掛載會銷毀並重建 48 個 widget，讓工具箱處於與穩態重排
    /// 不同的狀態。把兩者混在一起，會把該成本算進按壓的數字裡。
    static func buildSchedule() {
        steps = []
        for round in 0..<rounds {
            for _ in 0..<passesPerRound {
                for offset in 0..<armCount {
                    steps.append(
                        P52Step(round: round, arm: (round + offset) % armCount, isMount: false)
                    )
                }
            }
        }
        for round in 0..<rounds {
            for _ in 0..<mountsPerRound {
                for offset in 0..<armCount {
                    steps.append(
                        P52Step(round: round, arm: (round + offset) % armCount, isMount: true)
                    )
                }
            }
        }
    }

    static func runStep() {
        guard stepIndex < steps.count else {
            report()
            return
        }

        let step = steps[stepIndex]
        let model = models[step.arm]

        if step.isMount {
            // Tear down first, and do not time it. The number wanted here is the
            // cost of BUILDING N buttons, and an interval that also contained
            // their destruction would answer a question nobody asked.
            // 先拆除，且不計時。此處要的數字是**建立** N 顆按鈕的成本，而一個同時包含銷毀的區間
            // 回答的是沒有人問過的問題。
            let teardownStart = p52Now()
            model.mounted = false
            waitQuiet(arm: step.arm, after: teardownStart, attempt: 0) { _ in
                let started = p52Now()
                let cpuBefore = P52CPUTimes.read()
                model.mounted = true
                waitQuiet(arm: step.arm, after: started, attempt: 0) { finished in
                    record(step, started: started, finished: finished, cpuBefore: cpuBefore)
                    stepIndex += 1
                    runStep()
                }
            }
        } else {
            let started = p52Now()
            let cpuBefore = P52CPUTimes.read()
            model.generation += 1
            waitQuiet(arm: step.arm, after: started, attempt: 0) { finished in
                record(step, started: started, finished: finished, cpuBefore: cpuBefore)
                stepIndex += 1
                runStep()
            }
        }
    }

    /// Polls until this arm's sentinel has been still for `quietMillis`, then
    /// hands back the timestamp of its last firing.
    ///
    /// Recursive through `asyncAfter` rather than a loop, because the main thread
    /// has to be free for the update to run on it at all -- a spin here would
    /// deadlock against the very work being timed.
    ///
    /// 輪詢直到該 arm 的哨兵已靜止 `quietMillis`，然後交回它最後一次觸發的時間戳記。
    ///
    /// 以 `asyncAfter` 遞迴而非用迴圈，因為主執行緒必須空出來，該次更新才跑得起來——在此處空轉會與
    /// 正在被計時的那件事互相卡死。
    static func waitQuiet(
        arm: Int,
        after started: UInt64,
        attempt: Int,
        completion: @escaping (UInt64?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(pollMillis)) {
            let last = lastSentinel[arm]
            let now = p52Now()
            if last > started, now >= last, (now - last) >= UInt64(quietMillis) * 1_000_000 {
                completion(last)
            } else if attempt + 1 >= maxPolls {
                completion(nil)
            } else {
                waitQuiet(arm: arm, after: started, attempt: attempt + 1, completion: completion)
            }
        }
    }

    static func record(
        _ step: P52Step,
        started: UInt64,
        finished: UInt64?,
        cpuBefore: P52CPUTimes?
    ) {
        let cpuAfter = P52CPUTimes.read()

        guard let finished, finished > started else {
            misses[step.arm] += 1
            return
        }

        let microseconds = Double(finished - started) / 1000.0
        if step.isMount {
            mountRounds[step.arm][step.round].append(microseconds)
        } else {
            pressRounds[step.arm][step.round].append(microseconds)
        }

        if let cpuBefore, let cpuAfter {
            // Accumulated across the whole phase, never reported per sample: at a
            // 10-15 ms clock tick a per-sample delta is mostly zero and
            // occasionally one tick. The quiet window inside the interval is idle
            // and contributes almost no CPU, and it is the same length for every
            // arm.
            // 在整個階段中累加，絕不逐樣本回報：在 10 至 15 毫秒的時鐘刻度下，逐樣本的差值大多是
            // 零、偶爾是一個刻度。區間內的靜止視窗是閒置的、幾乎不貢獻 CPU，而且對每個 arm 長度
            // 相同。
            let delta = cpuAfter - cpuBefore
            if step.isMount {
                mountCPU[step.arm] = mountCPU[step.arm] + delta
            } else {
                pressCPU[step.arm] = pressCPU[step.arm] + delta
            }
        }
    }
}

// MARK: - Report

extension P52Bench {
    static func flatten(_ rounds: [[Double]]) -> [Double] {
        rounds.flatMap { $0 }
    }

    /// The minimum, which is what every headline number here is.
    ///
    /// **Not the mean.** Single-run variance on this project has exceeded 2x, and
    /// a mean carries every scheduler preemption and every background process
    /// straight into the result. The minimum of many samples is the closest thing
    /// available to the cost with nothing else running, and both arms get the
    /// same treatment. The maximum is printed beside it so the spread is visible
    /// rather than hidden by the choice.
    ///
    /// 最小值，本檔每一個標題數字都是它。
    ///
    /// **不是平均值。** 本專案單次執行的變異曾超過 2 倍，而平均值會把每一次排程搶佔與每一個背景
    /// 行程原封不動帶進結果。多樣本的最小值是「沒有別的東西在跑時的成本」最接近的可得替代，且兩邊
    /// 受到相同對待。最大值印在它旁邊，讓離散程度看得見，而不是被這個選擇藏起來。
    static func minimum(_ values: [Double]) -> Double? { values.min() }
    static func maximum(_ values: [Double]) -> Double? { values.max() }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func micros(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.0fus", value)
    }

    static func ratio(_ numerator: Double, _ denominator: Double) -> String {
        guard denominator > 0 else { return "n/a" }
        return String(format: "%.2fx", numerator / denominator)
    }

    /// `%d` is avoided deliberately: `String(format:)` takes `CVarArg`, and a
    /// Swift `Int` is 64-bit while `%d` reads 32 bits, which on a mismatch prints
    /// a plausible wrong number rather than failing. The count goes in through
    /// interpolation instead.
    /// 此處刻意避開 `%d`：`String(format:)` 接受的是 `CVarArg`，而 Swift 的 `Int` 是 64 位元、
    /// `%d` 讀 32 位元，兩者不符時會印出一個看似合理的錯誤數字而非失敗。計數改用字串內插帶入。
    static func cpuLine(_ times: P52CPUTimes, samples: Int) -> String {
        guard cpuAvailable else { return "user/sys unavailable on this platform" }
        return String(format: "user=%.3fs sys=%.3fs", times.user, times.system)
            + " over \(samples) samples"
    }

    /// Prints everything, then publishes the summary to the window.
    ///
    /// The per-round table goes to the log only. It is the evidence for the
    /// headline minimum -- ten numbers per arm, in the order they were taken, so
    /// a drift like this project's 1.74 -> 3.08 -> 5.45 -> 5.99 would be visible
    /// as a trend rather than averaged into invisibility.
    ///
    /// 全部印出，然後把摘要發布到視窗上。
    ///
    /// 逐輪的表格只寫入 log。它是標題最小值的證據——每個 arm 十個數字，依取得順序排列，因此像本專案
    /// 那種 1.74 -> 3.08 -> 5.45 -> 5.99 的漂移，會以趨勢的形式被看見，而不是被平均到看不見。
    static func report() {
        var summary: [String] = []
        func emit(_ line: String) {
            summary.append(line)
            P52Diagnostics.write(line)
        }

        for phase in 0..<2 {
            let isMount = phase == 1
            let name = isMount ? "MOUNT" : "PRESS"
            for round in 0..<rounds {
                var parts: [String] = []
                for arm in 0..<armCount {
                    let values = isMount ? mountRounds[arm][round] : pressRounds[arm][round]
                    parts.append("\(armNames[arm])=\(micros(minimum(values)))")
                }
                P52Diagnostics.write(
                    "\(name) round \(round + 1) of \(rounds), min of "
                        + "\(isMount ? mountsPerRound : passesPerRound): "
                        + parts.joined(separator: " ")
                )
            }
        }

        emit("--- P52 results, \(buttonsPerArm) buttons per arm, \(rounds) rounds ---")
        emit("backend -> \(String(describing: DefaultBackend.self))")

        var pressMin = [Double?](repeating: nil, count: armCount)
        var pressMax = [Double?](repeating: nil, count: armCount)
        var mountMin = [Double?](repeating: nil, count: armCount)
        var pressCounts = [Int](repeating: 0, count: armCount)

        for arm in 0..<armCount {
            let press = flatten(pressRounds[arm])
            let mount = flatten(mountRounds[arm])
            pressMin[arm] = minimum(press)
            pressMax[arm] = maximum(press)
            mountMin[arm] = minimum(mount)
            pressCounts[arm] = press.count

            emit(
                "PRESS \(armNames[arm]) n=\(press.count) min=\(micros(minimum(press))) "
                    + "med=\(micros(median(press))) max=\(micros(maximum(press))) "
                    + "misses=\(misses[arm])"
            )
            P52Diagnostics.write(
                "PRESS \(armNames[arm]) cpu \(cpuLine(pressCPU[arm], samples: press.count))"
            )
            P52Diagnostics.write(
                "MOUNT \(armNames[arm]) n=\(mount.count) min=\(micros(minimum(mount))) "
                    + "med=\(micros(median(mount))) max=\(micros(maximum(mount))) "
                    + "cpu \(cpuLine(mountCPU[arm], samples: mount.count))"
            )
        }

        // Per button, with the control arm's fixed overhead removed. Stated as a
        // subtraction rather than folded in silently, so a reader can redo it
        // from the three printed minima.
        // 逐顆按鈕，並扣除 control arm 的固定開銷。此處寫成一道減法而非默默併入，讓讀者可以從印出的
        // 三個最小值自行重算。
        guard
            let controlMin = pressMin[control],
            let primitiveMin = pressMin[primitive],
            let customMin = pressMin[custom],
            buttonsPerArm > 0
        else {
            emit("NO RESULT -- every sample missed; the sentinel never settled. See misses above.")
            publish(summary)
            return
        }

        let buttons = Double(buttonsPerArm)
        let primitivePerButton = (primitiveMin - controlMin) / buttons
        let customPerButton = (customMin - controlMin) / buttons

        emit(
            "FIXED OVERHEAD per update pass (control arm, 0 buttons) = \(micros(controlMin)), "
                + "n=\(pressCounts[control])"
        )
        emit(
            "PER TRANSITION per button: primitive=(\(micros(primitiveMin))-\(micros(controlMin)))/"
                + "\(buttonsPerArm)=\(String(format: "%.2fus", primitivePerButton)) "
                + "custom=(\(micros(customMin))-\(micros(controlMin)))/\(buttonsPerArm)="
                + String(format: "%.2fus", customPerButton)
        )
        emit(
            "PER CLICK per button (2 transitions, down and up): primitive="
                + String(format: "%.2fus", primitivePerButton * 2) + " custom="
                + String(format: "%.2fus", customPerButton * 2)
        )
        emit("RATIO custom/primitive per transition = \(ratio(customPerButton, primitivePerButton))")

        // The noise rule, spelled out so nobody has to invent one. Overlapping
        // ranges are not a small difference; they are no measured difference.
        // 雜訊判準，此處明說，讓沒有人需要自己發明一個。範圍重疊不代表差異很小，而是代表沒有量到
        // 差異。
        if let primitiveMax = pressMax[primitive], let customMaxValue = pressMax[custom] {
            if primitiveMax < customMin {
                emit(
                    "SEPARATION real: primitive max=\(micros(primitiveMax)) < custom min="
                        + "\(micros(customMin)). Custom is slower and the ranges do not overlap."
                )
            } else if customMaxValue < primitiveMin {
                emit(
                    "SEPARATION real: custom max=\(micros(customMaxValue)) < primitive min="
                        + "\(micros(primitiveMin)). Custom is FASTER and the ranges do not overlap."
                )
            } else {
                emit(
                    "SEPARATION none: ranges overlap (primitive \(micros(primitiveMin))..."
                        + "\(micros(primitiveMax)), custom \(micros(customMin))..."
                        + "\(micros(customMaxValue))). Treat the ratio above as NOISE, not a result."
                )
            }
        }

        if controlMin > primitiveMin * 0.5 {
            emit(
                "WARNING margin thin: the control arm is more than half of the primitive arm, so "
                    + "the per-button numbers are a difference of two similar quantities. Re-run "
                    + "with --buttons=\(buttonsPerArm * 2)."
            )
        }

        if let controlMount = mountMin[control],
            let primitiveMount = mountMin[primitive],
            let customMount = mountMin[custom]
        {
            // Kept separate from the press numbers on purpose: first render and
            // re-render answer different questions, and a reader who conflates
            // them will attribute widget construction to a button press.
            // 刻意與按壓數字分開：首次繪製與重繪回答的是不同的問題，而把兩者混為一談的讀者，會把
            // widget 的建構算到一次按鈕按壓頭上。
            emit(
                "FIRST RENDER per button (separate question): primitive="
                    + String(format: "%.2fus", (primitiveMount - controlMount) / buttons)
                    + " custom="
                    + String(format: "%.2fus", (customMount - controlMount) / buttons)
                    + " (mount minima \(micros(controlMount))/\(micros(primitiveMount))/"
                    + "\(micros(customMount)), n=\(flatten(mountRounds[primitive]).count) each)"
            )
        }

        emit("RE-DERIVE: rebuild and run again; every number above is min-of-n with n printed.")
        P52Diagnostics.write("BENCHMARK COMPLETE")
        publish(summary)
    }

    static func publish(_ lines: [String]) {
        results.lines = lines
    }
}

// MARK: - Views

/// N identical buttons in a grid.
///
/// **Every button carries the same label, at the same fixed frame.** An index in
/// the text would make the buttons different widths, and a width difference
/// between the two arms would put font metrics inside a number that is supposed
/// to be about button styles -- the mistake P22's weight ladder records making
/// and fixing.
///
/// `generation` is stored and never read. It is here so that a tick produces a
/// genuinely different `P52ButtonGrid` value, the way a press produces a
/// genuinely different `ButtonStyleConfiguration`. Both arms take it, so neither
/// gets an advantage from it.
///
/// `Array(0..<n)` rather than this suite's usual `Array(1...n)`, because the
/// mount phase needs to reach zero and `1...0` traps.
///
/// N 顆相同的按鈕排成網格。
///
/// **每顆按鈕都帶相同的標籤、相同的固定 frame。** 若文字中帶索引，各按鈕的寬度就會不同，而兩個 arm
/// 之間的寬度差異，會把字型度量塞進一個本應只談按鈕樣式的數字裡——那正是 P22 的字重階梯所記錄下、
/// 犯過又修好的錯。
///
/// `generation` 被儲存但從未讀取。它在此，是為了讓一次 tick 產生一個確實不同的 `P52ButtonGrid` 值，
/// 一如一次按壓會產生一個確實不同的 `ButtonStyleConfiguration`。兩個 arm 都收下它，因此沒有任何一邊
/// 因它得利。
///
/// 使用 `Array(0..<n)` 而非本套件慣用的 `Array(1...n)`，因為掛載階段必須能到達零，而 `1...0` 會 trap。
struct P52ButtonGrid: View {
    var count: Int
    var columns: Int
    var generation: Int

    var rowCount: Int {
        columns <= 0 ? 0 : (count + columns - 1) / columns
    }

    func buttonsInRow(_ row: Int) -> Int {
        min(columns, max(0, count - row * columns))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(0..<self.rowCount), id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(Array(0..<self.buttonsInRow(row)), id: \.self) { _ in
                        Button(action: {}) {
                            Text("b")
                                .font(.system(size: 10))
                                .frame(width: 14, height: 12)
                        }
                    }
                }
            }
        }
    }
}

/// Wraps an arm in a fixed frame and a timing sentinel.
///
/// **The fixed frame is what keeps an arm's update local.** `bottomUpUpdate`
/// compares the new layout's size against the old one and propagates to the
/// PARENT when they differ (`ViewGraphNode.swift:159`). Without the frame, adding
/// 48 buttons in the mount phase would change this arm's size, the update would
/// climb to the root, and the other two arms would be re-laid out inside the
/// interval being attributed to this one.
///
/// The sentinel is P22's measuring wrapper with a timestamp where P22 records a
/// size: a `GeometryReader` in an `.overlay`, which is where P22 put it so the
/// measurement cannot change the layout it is measuring.
///
/// 以固定 frame 與一個計時哨兵包住一個 arm。
///
/// **固定 frame 正是讓某個 arm 的更新保持在局部的東西。** `bottomUpUpdate` 會把新版面的尺寸與舊的
/// 相比，兩者不同時就往**父節點**傳遞（`ViewGraphNode.swift:159`）。少了這個 frame，掛載階段加入 48
/// 顆按鈕會改變本 arm 的尺寸，更新會一路爬到 root，於是另外兩個 arm 會在「被歸給本 arm」的那個區間
/// 之內被重新排版。
///
/// 這個哨兵就是 P22 的量測包裝，只是把 P22 記錄尺寸的地方換成記錄時間戳記：一個放在 `.overlay` 中的
/// `GeometryReader`——P22 把它放在那裡，正是為了讓量測不會改變它所量測的版面。
struct P52Instrumented<Content: View>: View {
    var arm: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: P52Bench.armWidth, height: P52Bench.armHeight)
            .overlay(alignment: .topTrailing) {
                GeometryReader { _ in
                    let _ = P52Bench.markSentinel(arm)
                    EmptyView()
                }
            }
    }
}

/// The control: the same container, the same style modifier, the same sentinel,
/// zero buttons.
///
/// **Without this arm the per-button numbers would be a guess.** The measured
/// interval contains a queue hop, `bottomUpUpdate`, the container's own layout
/// and the sentinel's -- costs that are paid once per update and have nothing to
/// do with how many buttons there are. Dividing the raw interval by 48 would
/// spread that fixed cost across the buttons and inflate both arms by the same
/// amount, which flatters whichever arm is cheaper by shrinking the ratio.
///
/// 對照組：相同的容器、相同的樣式 modifier、相同的哨兵，零顆按鈕。
///
/// **少了這一個 arm，逐顆按鈕的數字就只是猜測。** 被量測的區間內含一次佇列跳轉、`bottomUpUpdate`、
/// 容器自身的排版以及哨兵的排版——這些成本每次更新只付一次，與有幾顆按鈕無關。若直接把原始區間除以
/// 48，等於把該固定成本攤到按鈕頭上，使兩個 arm 同時被灌水相同的量，而那會因為壓縮比值而偏袒本來
/// 較便宜的那一邊。
struct P52ControlArm: View {
    @ObservedObject var model: P52ArmModel

    var body: some View {
        P52Instrumented(arm: P52Bench.control) {
            P52ButtonGrid(count: 0, columns: P52Bench.columns, generation: model.generation)
                .buttonStyle(P52Bench.primitiveStyle)
        }
    }
}

struct P52PrimitiveArm: View {
    @ObservedObject var model: P52ArmModel

    var body: some View {
        P52Instrumented(arm: P52Bench.primitive) {
            P52ButtonGrid(
                count: model.mounted ? P52Bench.buttonsPerArm : 0,
                columns: P52Bench.columns,
                generation: model.generation
            )
            .buttonStyle(P52Bench.primitiveStyle)
        }
    }
}

struct P52CustomArm: View {
    @ObservedObject var model: P52ArmModel

    var body: some View {
        P52Instrumented(arm: P52Bench.custom) {
            P52ButtonGrid(
                count: model.mounted ? P52Bench.buttonsPerArm : 0,
                columns: P52Bench.columns,
                generation: model.generation
            )
            .buttonStyle(P52PressStyle(highlighted: model.generation % 2 == 1))
        }
    }
}

@main
@HotReloadable
struct P52ButtonStyleCostApp: App {
    var body: some Scene {
        WindowGroup("P52 button style cost") {
            #hotReloadable {
                P52RootView()
            }
        }
        .defaultSize(width: 1000, height: 900)
    }
}

struct P52RootView: View {
    @ObservedObject var results = P52Bench.results

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("P52: PrimitiveButtonStyle against a custom ButtonStyle")
                    .font(.system(size: 18))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text(
                    "Three arms, interleaved round by round. Left: \(P52Bench.buttonsPerArm) "
                        + "buttons with the backend's default PrimitiveButtonStyle. Right: the "
                        + "same count under a custom ButtonStyle. Below: the same container with "
                        + "ZERO buttons, which measures the fixed per-update overhead so it can "
                        + "be subtracted."
                )
                .font(.system(size: 11))
                Text(
                    "三個 arm，逐輪交錯。左：\(P52Bench.buttonsPerArm) 顆按鈕，使用 backend 的預設 "
                        + "PrimitiveButtonStyle。右：相同數量，使用自訂 ButtonStyle。下：同樣的容器但"
                        + "零顆按鈕，用以量出每次更新的固定開銷，好把它減掉。"
                )
                .font(.system(size: 11))
                Text("Run with --debug to also get p52-debug-events.log, which holds the per-round table.")
                    .font(.system(size: 11))

                Divider()

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("primitive arm -- .buttonStyle(nil) -> backend default, .bordered")
                            .font(.system(size: 11))
                        P52PrimitiveArm(model: P52Bench.models[P52Bench.primitive])
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("custom arm -- .buttonStyle(P52PressStyle(...)), makeBody per pass")
                            .font(.system(size: 11))
                        P52CustomArm(model: P52Bench.models[P52Bench.custom])
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("control arm -- 0 buttons, same container and sentinel")
                        .font(.system(size: 11))
                    P52ControlArm(model: P52Bench.models[P52Bench.control])
                }

                Divider()

                // Empty until the run finishes. Publishing progress as it went
                // would re-lay out the root, and therefore both arms, inside the
                // intervals being timed.
                // 在執行結束前是空的。若邊跑邊發布進度，會在被計時的區間之內重新排版 root、進而
                // 重排兩個 arm。
                Text("Results (empty until the run finishes; watch the window, it takes ~20s)")
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(results.lines.indices), id: \.self) { index in
                        Text(results.lines[index])
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(14)
        }
        .onAppear {
            P52Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P52Diagnostics.write(
                "RENDER COMPLETE -- P52 ready; benchmark starts after "
                    + "\(P52Bench.warmupMillis)ms of warm-up"
            )
            P52Bench.start()
        }
    }
}
