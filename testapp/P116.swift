// P116: a field-matrix-shaped page for timing layout. Up to 40 rows of 6 cells,
// each a toggle, two texts and a button inside a ScrollView, wrapped in two
// `.onChange` modifiers. P116_MODE = text, toggle, button or full (the default)
// picks the widgets; P116_ROWS (1...40, default 10) the rows. It prints the
// onAppear phases and "appear-to-hop N ms": the time from onAppear to the next
// main-queue turn, which covers the first layout and commit. P116_PAGES,
// P116_IDS and P116_FLIPS add paging; see below.
// Named P998 until 2026-11-12, when it was a scratch app; todo.md's "Layout
// passes" measurements were taken with it under that name.
//
// P116：用來量測排版的欄位矩陣頁面。最多 40 列、每列 6 格，每格是一個開關、兩段文字與一個按鈕，放在
// ScrollView 裡，外面包兩個 `.onChange`。P116_MODE = text、toggle、button 或 full(預設)決定元件;
// P116_ROWS(1...40,預設 10)決定列數。它會印出 onAppear 時的 phase,以及「appear-to-hop N ms」:
// 從 onAppear 到主佇列下一輪的時間，涵蓋第一次排版與 commit。
// P116_PAGES、P116_IDS 與 P116_FLIPS 加入分頁，見下方。
// 2026-11-12 之前名為 P998,當時是臨時 app;todo.md「Layout passes」的量測是用那個名稱做的。
import DefaultBackend
import Foundation
import SwiftCrossUI

let p116Mode = ProcessInfo.processInfo.environment["P116_MODE"] ?? "full"
// At most 40: `checked` holds 6 x 40 bindings. / 最多 40:`checked` 只有 6 x 40 個 binding。
let p116Rows = min(40, max(1, Int(ProcessInfo.processInfo.environment["P116_ROWS"] ?? "10") ?? 10))

// Paging, shaped like SoftPCB-UI's field matrix (2026-11-13): P116_PAGES pages
// of P116_ROWS rows, turned P116_FLIPS times, one second apart, after onAppear.
// P116_IDS=item (the default) gives each row its item's id, as the field matrix
// does, so a flip replaces every row; P116_IDS=slot keys rows by position, so a
// flip keeps them and changes only their content.
// 分頁，形狀同 SoftPCB-UI 的欄位矩陣(2026-11-13):P116_PAGES 頁、每頁 P116_ROWS 列，onAppear 後每秒翻一次，共
// P116_FLIPS 次。P116_IDS=item(預設)讓每列用項目的 id,與欄位矩陣相同，翻頁會換掉每一列;P116_IDS=slot 以位置為鍵，
// 翻頁時保留各列，只改內容。
let p116Pages = max(1, Int(ProcessInfo.processInfo.environment["P116_PAGES"] ?? "1") ?? 1)
let p116Flips = max(0, Int(ProcessInfo.processInfo.environment["P116_FLIPS"] ?? "0") ?? 0)
let p116SlotIDs = ProcessInfo.processInfo.environment["P116_IDS"] == "slot"

func p116RowIDs(page: Int) -> [Int] {
    p116SlotIDs ? Array(0..<p116Rows) : Array(page * p116Rows..<(page + 1) * p116Rows)
}

/// "elmer" without paging, so the default page is unchanged. / 不分頁時為 "elmer",預設頁面不變。
func p116Label(page: Int, row: Int) -> String {
    p116Pages > 1 ? "case \(page * p116Rows + row)" : "elmer"
}

@main
struct P116App: App {
    var body: some Scene {
        WindowGroup("P116 layout timing") {
            P116Root()
        }
        .defaultSize(width: 1180, height: 620)
    }
}

struct P116Cell: View {
    @Binding var checked: Bool
    let reason: String
    var label = "elmer"

    var body: some View {
        VStack(spacing: 1) {
            if p116Mode == "toggle" || p116Mode == "full" {
                Toggle("run", isOn: $checked)
            }
            if p116Mode == "text" || p116Mode == "full" {
                Text(label)
                Text(reason).frame(width: 166)
            }
            if p116Mode == "button" || p116Mode == "full" {
                Button("expand") {}
            }
        }
        .frame(width: 174)
    }
}

struct P116Root: View {
    @State var checked = Array(repeating: false, count: 6 * 40)
    @State var appeared = false
    @State var page = 0
    @Environment(\.appPhase) var appPhase
    @Environment(\.scenePhase) var scenePhase
    let reason = String(
        repeating: "solver did not converge within the iteration limit; mesh refinement suggested. ",
        count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(p116RowIDs(page: page), id: \.self) { id in
                    let row = id % p116Rows
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { column in
                            P116Cell(checked: $checked[row * 6 + column], reason: reason, label: p116Label(page: page, row: row))
                        }
                    }
                    Divider()
                }
            }
            .padding(10)
        }
        // Flushed: a killed WinUI process loses buffered stdout.
        // 立即 flush:被終止的 WinUI 行程會遺失緩衝中的 stdout。
        .onChange(of: appPhase) {
            print("P116 onChange appPhase=\(appPhase)")
            fflush(stdout)
        }
        .onChange(of: scenePhase) {
            print("P116 onChange scenePhase=\(scenePhase)")
            fflush(stdout)
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            print("P116 onAppear appPhase=\(appPhase) scenePhase=\(scenePhase)")
            fflush(stdout)
            let appearedAt = Date()
            DispatchQueue.main.async {
                let shown = Int(Date().timeIntervalSince(appearedAt) * 1000)
                print("P116 mode=\(p116Mode) appear-to-hop \(shown) ms")
                fflush(stdout)
            }
            // Page flips, each one update; SCUI_UPDATE_STATS=1 times them.
            // 翻頁，每次一個更新;SCUI_UPDATE_STATS=1 會為它們計時。
            if p116Flips > 0 {
                Task { @MainActor in
                    for _ in 0..<p116Flips {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        page = (page + 1) % p116Pages
                        print("P116 flip to page \(page)")
                        fflush(stdout)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    print("P116 flips done")
                    fflush(stdout)
                }
            }
        }
    }
}
