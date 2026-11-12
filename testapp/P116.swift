// P116: a field-matrix-shaped page for timing layout. Up to 40 rows of 6 cells,
// each a toggle, two texts and a button inside a ScrollView, wrapped in two
// `.onChange` modifiers. P116_MODE = text, toggle, button or full (the default)
// picks the widgets; P116_ROWS (1...40, default 10) the rows. It prints the
// onAppear phases and "appear-to-hop N ms": the time from onAppear to the next
// main-queue turn, which covers the first layout and commit.
// Named P998 until 2026-11-12, when it was a scratch app; todo.md's "Layout
// passes" measurements were taken with it under that name.
//
// P116：用來量測排版的欄位矩陣頁面。最多 40 列、每列 6 格，每格是一個開關、兩段文字與一個按鈕，放在
// ScrollView 裡，外面包兩個 `.onChange`。P116_MODE = text、toggle、button 或 full(預設)決定元件;
// P116_ROWS(1...40,預設 10)決定列數。它會印出 onAppear 時的 phase,以及「appear-to-hop N ms」:
// 從 onAppear 到主佇列下一輪的時間，涵蓋第一次排版與 commit。
// 2026-11-12 之前名為 P998,當時是臨時 app;todo.md「Layout passes」的量測是用那個名稱做的。
import DefaultBackend
import Foundation
import SwiftCrossUI

let p116Mode = ProcessInfo.processInfo.environment["P116_MODE"] ?? "full"
// At most 40: `checked` holds 6 x 40 bindings. / 最多 40:`checked` 只有 6 x 40 個 binding。
let p116Rows = min(40, max(1, Int(ProcessInfo.processInfo.environment["P116_ROWS"] ?? "10") ?? 10))

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

    var body: some View {
        VStack(spacing: 1) {
            if p116Mode == "toggle" || p116Mode == "full" {
                Toggle("run", isOn: $checked)
            }
            if p116Mode == "text" || p116Mode == "full" {
                Text("elmer")
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
    @Environment(\.appPhase) var appPhase
    @Environment(\.scenePhase) var scenePhase
    let reason = String(
        repeating: "solver did not converge within the iteration limit; mesh refinement suggested. ",
        count: 4)

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(0..<p116Rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { column in
                            P116Cell(checked: $checked[row * 6 + column], reason: reason)
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
        }
    }
}
