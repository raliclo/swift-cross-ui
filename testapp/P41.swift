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
                P41Cell(label: ".automatic", date: $automatic, style: .automatic)
                P41Cell(label: ".graphical", date: $graphical, style: .graphical)
            }

            HStack(spacing: 20) {
                P41Cell(label: ".compact", date: $compact, style: .compact)
                P41Cell(label: ".wheel", date: $wheel, style: .wheel)
            }
        }
        .padding(18)
    }
}

struct P41Cell: View {
    var label: String
    @Binding var date: Date
    var style: any DatePickerStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))

            DatePicker(label, selection: $date, displayedComponents: .date)
                .datePickerStyle(style)

            Text(P41Cell.formatter.string(from: date))
                .font(.system(size: 12))
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
}
