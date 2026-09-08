import DefaultBackend
import Foundation
import SwiftCrossUI

// P54 exercises `.refreshable`, added 2026-09-09 for Q7.
//
// The number was checked, not guessed. `ls testapp` gives P50..P53; `git ls-files`
// has no P54; and nothing under matrix_coverage, mistakes or testapp/plan mentions
// the name. A free filename and a free NAME are different questions, and P46's
// header records what happens when only the first is asked.
//
// **Only one of the five backends has a pull gesture, and the app has to be
// readable on all five.** UIKit gets a UIRefreshControl -- installed on the
// enclosing RootScrollHost, which is the scroll view whose pan gesture actually
// wins. AppKit and WinUI get a floating "Refresh" button, because a desktop
// toolkit either has no pull or cannot report one from every input device.
// Android gets a full-width Refresh row above the content, because its
// ScrollContainer is written around having exactly one child. GTK connects
// `edge-overshot`. So this app cannot instruct the reader to "pull down" -- it
// says what the affordance is on each and counts what arrives.
//
// The counter is the whole test. A refresh control that appears and then does
// nothing looks, in a screenshot, exactly like one that works: both show a
// scroll view with a spinner or a button in the corner. `refreshes: 0` becoming
// `refreshes: 2` is the only thing that separates them, and it is what the
// action files assert.
//
// P54 演練 `.refreshable`,於 2026-09-09 為 Q7 新增。
//
// 這個編號是查過的,不是猜的。`ls testapp` 給出 P50..P53;`git ls-files` 中沒有 P54;而
// matrix_coverage、mistakes 與 testapp/plan 底下都沒有提到這個名字。「檔名是空的」與「名稱是空的」
// 是兩個不同的問題,而 P46 的檔頭記錄了「只問了第一個」會發生什麼事。
//
// **五個 backend 中只有一個有下拉手勢,而這支 app 必須在五個上面都讀得懂。** UIKit 得到
// UIRefreshControl——裝在外圍的 RootScrollHost 上,那才是 pan 手勢真正勝出的那個捲動視圖。AppKit 與
// WinUI 得到一顆浮動的「Refresh」按鈕,因為桌面 toolkit 要嘛沒有下拉、要嘛無法從每一種輸入裝置回報
// 下拉。Android 得到一條位於內容上方、佔滿寬度的 Refresh,因為它的 ScrollContainer 是圍繞著
// 「恰好只有一個子項」寫成的。GTK 則連接 `edge-overshot`。因此這支 app 不能叫讀者「往下拉」——
// 它會說明各平台上的操作方式是什麼,並計算抵達了幾次。
//
// 那個計數器就是這項測試的全部。一個「會出現、然後什麼都不做」的重新整理控制項,在螢幕截圖上看起來
// 與一個能用的完全相同:兩者都是一個角落帶著轉圈或按鈕的捲動視圖。`refreshes: 0` 變成
// `refreshes: 2` 是唯一能區分兩者的東西,而那正是動作檔所斷言的。

enum P54Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P54] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P54 ready for refresh checks")
    }
}

@main
@HotReloadable
struct P54RefreshableApp: App {
    var body: some Scene {
        WindowGroup("P54 refreshable") {
            #hotReloadable {
                P54RootView()
            }
        }
        .defaultSize(width: 720, height: 620)
    }
}

struct P54RootView: View {
    @State var refreshes = 0
    @State var lastRefresh = "(none)"
    @State var rows = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("P54: refreshable")
                    .font(.system(size: 20))
                Text("backend -> \(String(describing: DefaultBackend.self))")

                Text("refreshes: \(refreshes)")
                Text("last refresh added rows up to: \(lastRefresh)")

                Text(
                    "The affordance differs per backend and that is deliberate. UIKit shows a "
                        + "pull-to-refresh spinner; AppKit and WinUI show a Refresh button "
                        + "floating in the scroll view's top-left corner; Android shows a "
                        + "full-width Refresh row above the content; GTK responds to dragging "
                        + "past the top edge."
                )
                Text(
                    "操作方式因 backend 而異,而那是刻意的。UIKit 顯示下拉重新整理的轉圈;"
                        + "AppKit 與 WinUI 在捲動視圖左上角顯示一顆浮動的 Refresh 按鈕;"
                        + "Android 在內容上方顯示一條佔滿寬度的 Refresh;"
                        + "GTK 則對「拖過頂端邊緣」有反應。"
                )
                Text(
                    "Expected: each refresh raises the counter by exactly one and adds two rows. "
                        + "A control that appears and does nothing leaves the counter at 0, and "
                        + "on a photograph that is indistinguishable from one that works."
                )
                Text(
                    "預期:每一次重新整理都讓計數器恰好加一,並新增兩列。一個「會出現、卻什麼都不做」"
                        + "的控制項會讓計數器停在 0,而在照片上,那與一個能用的控制項無法區分。"
                )

                ForEach(Array(0..<rows)) { index in
                    Text("Row \(index)")
                }
            }
            .padding(16)
        }
        .refreshable {
            refreshes += 1
            rows += 2
            lastRefresh = "\(rows)"
            P54Diagnostics.write("refresh \(refreshes) -> rows=\(rows)")
        }
        .onAppear {
            P54Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P54Diagnostics.renderComplete()
        }
    }
}
