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
                P41RootView()
            }
        }
        .defaultSize(width: 940, height: 620)
    }
}

struct P41RootView: View {
    @State var automatic = P41RootView.start
    @State var graphical = P41RootView.start
    @State var compact = P41RootView.start
    @State var wheel = P41RootView.start
    @State var hourMinute = P41RootView.start
    @State var hourMinuteSecond = P41RootView.start

    // A fixed date rather than `Date()`, so two runs are comparable and a
    // screenshot does not change meaning overnight.
    // 使用固定日期而非 `Date()`，使兩次執行可互相比較，且截圖的意義不會在隔夜之後改變。
    static let start = Date(timeIntervalSince1970: 1_756_000_000)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P41: date picker styles")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Two cells that look identical mean one style fell back to the other.")

            HStack(spacing: 20) {
                P41Cell(label: ".automatic", date: $automatic, style: .automatic, requires: .automatic)
                P41Cell(label: ".graphical", date: $graphical, style: .graphical, requires: .graphical)
            }

            // `.wheel` only where the enum has it.
            //
            // `BackendDatePickerStyle.wheel` is `@available(macOS, unavailable)`,
            // so naming it unconditionally made P41 fail to compile for macOS --
            // it has never built there. The same commit that added this app,
            // f704f304, also added `.wheel` to GtkBackend's supported list and
            // broke `swift test` on a Mac the same way; that half was fixed
            // separately.
            //
            // The macOS cell says so rather than being dropped. A row that
            // silently loses a cell on one platform reads as a layout
            // difference, which is the one thing P41 is for comparing.
            //
            // 只在 enum 具備該 case 的平台上使用 `.wheel`。
            //
            // `BackendDatePickerStyle.wheel` 帶有 `@available(macOS, unavailable)`，因此無條件
            // 指名它會使 P41 無法為 macOS 編譯——它在該平台上從未建置成功過。加入本 app 的同一個
            // commit f704f304，也把 `.wheel` 加進了 GtkBackend 的支援清單，以同樣的方式弄壞了
            // Mac 上的 `swift test`；那一半已另行修復。
            //
            // macOS 上的那一格會說明情況，而不是直接消失。在某個平台上悄悄少掉一格的列，讀起來會像
            // 是版面差異——而版面差異正是 P41 要用來比較的東西。
            HStack(spacing: 20) {
                P41Cell(label: ".compact", date: $compact, style: .compact, requires: .compact)
                #if os(macOS)
                    Text(".wheel is unavailable on macOS")
                #else
                    P41Cell(label: ".wheel", date: $wheel, style: .wheel, requires: .wheel)
                #endif
            }

            // Components, not styles. Both cells below use `.graphical` so the
            // only thing that differs is what was asked for, and a difference
            // between them is about components rather than about a style
            // falling back.
            //
            // These exist because nothing exercised them. `TimeRow` is
            // implemented and wired -- `updateDatePicker` derives its precision
            // from the requested components and `applyDate` writes the hour,
            // minute and second back into it -- and no test app had ever asked
            // for a time component, so the whole path was untested. An
            // implemented and unexercised feature reads as done until someone
            // relies on it.
            //
            // 這裡比較的是 components，不是 styles。下方兩格都使用 `.graphical`，因此唯一的差異
            // 就是「要求了什麼」，兩者之間的不同便是關於 components，而非某個 style 退回。
            //
            // 它們之所以存在，是因為先前沒有任何東西驅動過它們。`TimeRow` 已實作也已接上——
            // `updateDatePicker` 由所要求的 components 推導其精度，`applyDate` 也會把時、分、秒
            // 寫回其中——但從來沒有任何測試 app 要求過時間 component，因此整條路徑未被測試過。
            // 一個「已實作但從未被驅動」的功能，在有人真的依賴它之前，讀起來都像是完成的。
            HStack(spacing: 20) {
                P41Cell(
                    label: ".hourAndMinute",
                    date: $hourMinute,
                    style: .graphical,
                    requires: .graphical,
                    components: .hourAndMinute,
                    format: "yyyy-MM-dd HH:mm"
                )
                // The same trap this file's own header describes, one section
                // up, and it caught this cell too.
                //
                // `DatePickerComponents.hourMinuteAndSecond` carries
                // `@available(iOS, unavailable)`, `@available(visionOS,
                // unavailable)` and `@available(macCatalyst, unavailable)`, so
                // naming it unconditionally meant P41 had never built for iOS
                // at all -- no `output/P41-ios.app`, and not one `p41-ios-*`
                // capture in `output/screenshots/` while every other app there
                // has some. The header explains why `.wheel` is guarded for
                // macOS and then this cell, added by the same commit, was
                // written without the matching guard.
                //
                // The cell says so rather than disappearing, for the reason the
                // header gives about `.wheel`: a row that silently loses a cell
                // on one platform reads as a layout difference, and layout
                // differences are what P41 exists to compare.
                //
                // 這正是本檔自己的檔頭在上一節所描述的同一個陷阱，而它也逮到了這一格。
                //
                // `DatePickerComponents.hourMinuteAndSecond` 帶有 `@available(iOS, unavailable)`、
                // `@available(visionOS, unavailable)` 與 `@available(macCatalyst, unavailable)`，
                // 因此無條件指名它，意味著 P41 從來沒有為 iOS 建置成功過——沒有 `output/P41-ios.app`，
                // `output/screenshots/` 中也沒有任何一張 `p41-ios-*`，而其他每一支 app 在那裡都有。
                // 檔頭說明了 `.wheel` 為何要為 macOS 加上防護，而這一格——由同一個 commit 加入——
                // 卻沒有寫上對應的防護。
                //
                // 這一格會說明情況而不是直接消失，理由與檔頭對 `.wheel` 所給的相同：一個在某平台上
                // 悄悄少掉一格的列，讀起來會像是版面差異——而版面差異正是 P41 要用來比較的東西。
                #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    Text(".hourMinuteAndSecond is unavailable on this platform")
                #else
                    P41Cell(
                        label: ".hourMinuteAndSecond",
                        date: $hourMinuteSecond,
                        style: .graphical,
                        requires: .graphical,
                        components: .hourMinuteAndSecond,
                        format: "yyyy-MM-dd HH:mm:ss"
                    )
                #endif
            }
        }
        .padding(18)
    }
}

struct P41Cell: View {
    var label: String
    @Binding var date: Date
    var style: any DatePickerStyle
    /// The backend vocabulary name for `style`, so the cell can look it up in
    /// `supportedDatePickerStyles` before asking for it. Passed rather than
    /// derived, because `_asBackendDatePickerStyle` is SPI and an app is not
    /// supposed to reach it -- P11 compares against this enum too.
    /// `style` 在 backend 詞彙中的名稱，好讓這一格在索取之前先到 `supportedDatePickerStyles` 中
    /// 查詢。採用傳入而非推導，因為 `_asBackendDatePickerStyle` 屬於 SPI，而 app 不應該碰它
    /// ——P11 比對的也是這個 enum。
    var requires: BackendDatePickerStyle
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
            if supportedDatePickerStyles.contains(requires) {
                DatePicker(label, selection: $date, displayedComponents: components)
                    .datePickerStyle(style)

                Text(P41Cell.string(from: date, format: format))
                    .font(.system(size: 12))
            } else {
                Text("not offered by this backend")
                    .font(.system(size: 12))
            }
        }
        .frame(width: 420, alignment: .leading)
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
