import DefaultBackend
import Foundation
import SwiftCrossUI

// P41 date picker styles: all four, side by side, with the resolved date shown.
//
// Added 2026-08-27 with the GtkBackend `.wheel` implementation. Until then no
// app on this side used DatePicker at all -- only P11 did, and P11 is the
// macOS-scoped one. So GtkBackend declining `.wheel`, and every other style
// question, had no picture anywhere.
//
// The four styles are shown at once because that is the only way to tell them
// apart. A style that quietly falls back looks completely reasonable on its own;
// it is only wrong next to the style it fell back to. Until 2026-08-27 `.wheel`
// on GtkBackend was `.automatic`, and `datePickerStyle(_:)` downgrades any style
// a backend does not list WITHOUT SAYING SO in a release build -- so the two
// cells being identical is the exact failure this layout is built to show.
//
// The date line under each is not decoration either. A picker that renders
// beautifully and reports nothing is a different defect from one that does not
// render, and a screenshot cannot tell them apart without it.
//
// P41 日期選擇器樣式：四種並排，並顯示解析後的日期。
//
// 於 2026-08-27 隨 GtkBackend 的 `.wheel` 實作一同加入。在此之前，本側沒有任何 app 使用過
// DatePicker——只有 P11 用，而 P11 屬於 macOS 範圍。因此 GtkBackend 拒絕 `.wheel` 這件事，連同其他
// 所有樣式問題，在任何地方都沒有畫面可看。
//
// 四種樣式同時呈現，因為那是唯一能分辨它們的方式。一個悄悄退回預設的樣式，單獨看完全合理；唯有
// 與「它所退回的那個樣式」並列時才顯得錯誤。在 2026-08-27 之前，GtkBackend 上的 `.wheel` 就是
// `.automatic`，而 `datePickerStyle(_:)` 在 release build 中會**不發一語地**降級任何 backend 未列出
// 的樣式——因此「兩格看起來一模一樣」正是本版面所要揭露的失敗。
//
// 每一格下方的日期文字同樣不是裝飾。一個畫得很漂亮卻什麼都不回報的選擇器，與一個根本畫不出來的
// 選擇器，是兩種不同的缺陷，而少了它，截圖無法區分兩者。
//
//     zsh testapp/run.zsh P41
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P41DatePickerStylesApp: App {
    var body: some Scene {
        WindowGroup("P41 date picker styles") {
            #hotReloadable {
                // In a ScrollView (2026-10-29): the content is about 1136 DIPs
                // tall, and without one SwiftCrossUI grows the window to fit it,
                // past the bottom of a 1080-line screen at 125%, where the
                // .rows cells could not be clicked.
                // 放進 ScrollView(2026-10-29):內容約 1136 DIP 高，沒有它 SwiftCrossUI 會把視窗撐到容得下內容，
                // 在 125% 的 1080 線螢幕上超出底部,.rows 那幾格點不到。
                ScrollView {
                    P41RootView()
                }
            }
        }
        .defaultSize(width: 1340, height: 820)
    }
}

struct P41RootView: View {
    #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
        static let seconds: DatePickerComponents = .hourAndMinute
    #else
        static let seconds: DatePickerComponents = .hourMinuteAndSecond
    #endif

    // A fixed date rather than `Date()`, so two runs are comparable and a
    // screenshot does not change meaning overnight.
    // 使用固定日期而非 `Date()`，使兩次執行可互相比較，且截圖的意義不會在隔夜之後改變。
    static let start = Date(timeIntervalSince1970: 1_756_000_000)

    // SCUI_P41_LOCALE=zh_TW draws every cell under that locale (2026-10-20), so
    // the styles P90 does not cover -- .compact, .clock, .rows -- can be checked
    // in a region other than the machine's. Unset, the inherited locale, as before.
    // SCUI_P41_LOCALE=zh_TW 會讓每一格都以該 locale 繪製(2026-10-20),以便在本機以外的地區檢查 P90 沒涵蓋的
    // 樣式——.compact、.clock、.rows。未設定時照舊沿用繼承來的 locale。
    static let localeOverride: Locale? =
        ProcessInfo.processInfo.environment["SCUI_P41_LOCALE"].map(Locale.init(identifier:))
    @Environment(\.locale) var inheritedLocale
    @State var chosenLocale: String? = nil

    static let locales = ["launch", "en_US", "zh_TW", "ja_JP", "de_DE"]

    var locale: Locale {
        chosenLocale.map(Locale.init(identifier:))
            ?? P41RootView.localeOverride ?? inheritedLocale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P41: date picker styles")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Two cells that look identical mean one style fell back to the other.")

            // Switches every cell's locale in place (2026-10-29), so one run
            // compares languages and also exercises a locale change on a live
            // control, which a launch-time SCUI_P41_LOCALE never does. "launch"
            // goes back to SCUI_P41_LOCALE or the inherited locale.
            // 就地切換每一格的 locale(2026-10-29),讓一次執行就能比較語言，同時測到「已上畫面的控制項換
            // locale」——啟動時的 SCUI_P41_LOCALE 永遠測不到這條路。"launch" 回到 SCUI_P41_LOCALE 或繼承的 locale。
            HStack(spacing: 8) {
                Text("locale -> \(locale.identifier)")
                ForEach(P41RootView.locales, id: \.self) { name in
                    Button(name) {
                        chosenLocale = name == "launch" ? nil : name
                        P41Diagnostics.write("locale button -> \(name)")
                    }
                }
            }

            // Three styles a row (2026-10-18): the wheel, `.clock` and `.rows` are
            // drawn on every backend now -- in SwiftCrossUI views where the
            // backend has no control of its own -- so no cell is gated by
            // platform any more, and the time styles each get a row of their own:
            // a time, a time with seconds, and a date with a time.
            // `.clock` is what AppKit drew for `.hourAndMinute` and `.rows` is
            // what GtkBackend drew; until they had names, the two cells that
            // asked for `.graphical` with a time were two different pictures.
            //
            // 一列三種樣式(2026-10-18):滾輪、`.clock` 與 `.rows` 現在在每個 backend 上都畫得出來——backend 沒有自己的
            // 控制項時以 SwiftCrossUI 的 view 畫——所以不再有格位依平台開關，而時間樣式各佔一列：時間、帶秒的時間、日期加時間。
            // `.clock` 是 AppKit 為 `.hourAndMinute` 畫的,`.rows` 是 GtkBackend 畫的;在它們有名字之前，以 `.graphical`
            // 要求時間的兩格是兩張不同的圖。
            //
            // `.hourMinuteAndSecond` is unavailable on iOS, visionOS and Mac
            // Catalyst, so those cells ask for `.hourAndMinute` there.
            // `.hourMinuteAndSecond` 在 iOS、visionOS 與 Mac Catalyst 上不可用，所以那些格位在那裡要求 `.hourAndMinute`。
            HStack(alignment: .top, spacing: 20) {
                P41Cell(label: ".automatic", style: .automatic, requires: .automatic)
                P41Cell(label: ".graphical", style: .graphical, requires: .graphical)
                P41Cell(label: ".compact", style: .compact, requires: .compact)
            }
            HStack(alignment: .top, spacing: 20) {
                P41Cell(label: ".wheel", style: .wheel, requires: nil)
                P41Cell(
                    label: ".wheel time", style: .wheel, requires: nil,
                    components: .hourAndMinute, format: "HH:mm"
                )
                P41Cell(
                    label: ".wheel date+time", style: .wheel, requires: nil,
                    components: [.date, .hourAndMinute], format: "yyyy-MM-dd HH:mm"
                )
            }
            HStack(alignment: .top, spacing: 20) {
                P41Cell(
                    label: ".clock", style: .clock, requires: nil,
                    components: .hourAndMinute, format: "HH:mm"
                )
                P41Cell(
                    label: ".clock seconds", style: .clock, requires: nil,
                    components: P41RootView.seconds, format: "HH:mm:ss"
                )
                P41Cell(
                    label: ".clock date+time", style: .clock, requires: nil,
                    components: [.date, .hourAndMinute], format: "yyyy-MM-dd HH:mm"
                )
            }
            HStack(alignment: .top, spacing: 20) {
                P41Cell(
                    label: ".rows", style: .rows, requires: nil,
                    components: .hourAndMinute, format: "HH:mm"
                )
                P41Cell(
                    label: ".rows seconds", style: .rows, requires: nil,
                    components: P41RootView.seconds, format: "HH:mm:ss"
                )
                P41Cell(
                    label: ".rows date+time", style: .rows, requires: nil,
                    components: [.date, .hourAndMinute], format: "yyyy-MM-dd HH:mm"
                )
            }
        }
        .padding(18)
        .environment(\.locale, locale)
        .onAppear {
            P41Diagnostics.write("RENDER COMPLETE -- P41 ready for date picker checks")
        }
    }
}

/// The event log for driven runs, written only with `--debug`. Same contract as
/// the other apps: `SCUI_DEBUG_EVENTS_DIR` when set, else the launch directory.
/// Added 2026-09-17 because the 2026-09-07 result row says "no log writer in
/// P41.swift -- judge from the capture", and a capture cannot tell a calendar
/// that wrote the date back from one that only highlighted it.
///
/// 驅動執行用的事件 log,只在 `--debug` 時寫入。約定與其他 app 相同:有 `SCUI_DEBUG_EVENTS_DIR`
/// 時寫入該處,否則寫入啟動目錄。2026-09-17 加入,因為 2026-09-07 的結果列寫著「P41.swift 沒有
/// log writer——只能看擷圖判斷」,而擷圖分不出「把日期寫回了的月曆」與「只是把那天標亮的月曆」。
enum P41Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P41] \(message)")
        guard let data = "P41 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p41-debug-events.log")
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

struct P41Cell: View {
    var label: String
    @State var date = P41RootView.start
    var style: any DatePickerStyle
    /// The backend vocabulary name for `style`, so the cell can look it up in
    /// `supportedDatePickerStyles` before asking for it. Passed rather than
    /// derived, because `_asBackendDatePickerStyle` is SPI and an app is not
    /// supposed to reach it -- P11 compares against this enum too.
    /// `style` 在 backend 詞彙中的名稱，好讓這一格在索取之前先到 `supportedDatePickerStyles` 中
    /// 查詢。採用傳入而非推導，因為 `_asBackendDatePickerStyle` 屬於 SPI，而 app 不應該碰它
    /// ——P11 比對的也是這個 enum。
    /// `nil` for a style every backend draws, in SwiftCrossUI views where it has no control of its own (`.wheel`, `.clock`, `.rows`).
    /// `nil` 表示每個 backend 都畫得出的樣式;backend 沒有自己的控制項時以 SwiftCrossUI 的 view 畫(`.wheel`、`.clock`、`.rows`)。
    var requires: BackendDatePickerStyle?
    /// Defaults to `.date`, which is what the style cells above compare.
    /// 預設為 `.date`，那正是上方各 style 格所比較的內容。
    var components: DatePickerComponents = .date
    /// The readback below has to show whatever was asked for, or a time that
    /// never changed and a time that changed correctly print the same line.
    /// 下方的回讀必須顯示「所要求的內容」，否則「時間從未改變」與「時間正確改變」會印出同一行。
    var format: String = "yyyy-MM-dd"

    /// What the backend says it can draw, so a cell can ask before asking.
    /// backend 宣稱自己畫得出來的東西，好讓一個格位在索取之前先詢問。
    @Environment(\.supportedDatePickerStyles) var supportedDatePickerStyles

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))

            // Asked for only when the backend lists it, which is what P11 does
            // and what this app did not.
            //
            // `datePickerStyle(_:)` downgrades an unlisted style silently in a
            // release build and calls `assertionFailure` in a debug one, and
            // this harness builds debug. So a cell that asked unconditionally
            // did not produce a downgraded picker to look at -- it ended the
            // process. Measured 2026-09-04 on a Wear OS 5 emulator: this app
            // died at launch with "Unsupported date picker style:
            // GraphicalDatePickerStyle", because a watch is 320 points wide and
            // AndroidBackend does not offer `.graphical` there.
            //
            // The unsupported case now says so on screen. That is more use than
            // a crash and more use than a silent downgrade: the whole subject of
            // this app is which style you actually got.
            //
            // 只有在 backend 列出該樣式時才索取它，那正是 P11 的做法，也是這支 app 過去沒有做的。
            //
            // 對於未列出的樣式，`datePickerStyle(_:)` 在 release build 中會靜默降級，在 debug
            // build 中則會呼叫 `assertionFailure`；而本 harness 建的是 debug。因此一個「無條件索取」
            // 的格位並不會產生一個「降級後的選擇器」供人檢視——它會終結整個行程。2026-09-04 於
            // Wear OS 5 emulator 上實測：這支 app 在啟動時死於「Unsupported date picker style:
            // GraphicalDatePickerStyle」，因為錶只有 320 點寬，而 AndroidBackend 在該處不提供
            // `.graphical`。
            //
            // 現在「不支援」這件事會顯示在畫面上。那比崩潰有用，也比靜默降級有用：這支 app 的整個
            // 主題，就是「你實際拿到的是哪一個樣式」。
            if requires.map(supportedDatePickerStyles.contains) ?? true {
                // No label of its own: the cell's title above already names it, and a
                // second one beside a wide picker squeezed it (P41, 2026-10-18).
                // 不帶自己的標籤：上方的格位標題已經寫了名字，寬的選擇器旁再放一個會把它擠窄(P41,2026-10-18)。
                DatePicker("", selection: $date, displayedComponents: components)
                    .datePickerStyle(style)
                    // A log line per change, so a driven click is judged by the
                    // BINDING rather than by reading a date off a screenshot.
                    // The text below says what is drawn; this says what the
                    // app received, and "the calendar highlighted the day but
                    // nothing was written back" is exactly the gap between them.
                    // 每次變更記一行 log,讓一次驅動的點擊是以 **binding** 來判定,而不是從截圖上讀日期。
                    // 下方文字說的是「畫出了什麼」,這一行說的是「app 收到了什麼」——而「月曆把那天
                    // 標亮了、卻什麼都沒寫回」正好就是兩者之間的落差。
                    .onChange(of: date) {
                        P41Diagnostics.write(
                            "\(label) -> \(P41Cell.string(from: date, format: format))"
                        )
                    }

                Text(P41Cell.string(from: date, format: format))
                    .font(.system(size: 12))
            } else {
                Text("not offered by this backend")
                    .font(.system(size: 12))
            }
        }
        .frame(minWidth: 360, alignment: .leading)
    }

    // `nonisolated(unsafe)` for the same reason the rest of this project uses
    // it on cached formatters: DateFormatter is not Sendable, and every use here
    // is on the main actor by construction.
    // 此處使用 `nonisolated(unsafe)` 的理由，與本專案其他快取 formatter 相同：DateFormatter 並非
    // Sendable，而此處的每一次使用在結構上都位於 main actor。
    nonisolated(unsafe) static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// One formatter, re-pointed per call rather than one per cell.
    ///
    /// Safe here for the same reason the `nonisolated(unsafe)` above is: every
    /// call is on the main actor by construction, so the assignment and the
    /// format cannot interleave. It is a shared mutable formatter all the same,
    /// which is worth saying out loud rather than leaving to be discovered by
    /// whoever first calls it from somewhere else.
    ///
    /// 單一 formatter，每次呼叫時重新指定格式，而非每格一個。
    ///
    /// 此處之所以安全，理由與上方的 `nonisolated(unsafe)` 相同：每一次呼叫在結構上都位於 main
    /// actor，因此賦值與格式化不可能交錯。但它終究是一個共用的可變 formatter——這一點值得明說，
    /// 而不是留給第一個從別處呼叫它的人自行發現。
    static func string(from date: Date, format: String) -> String {
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
