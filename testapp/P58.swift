import DefaultBackend
import Foundation
import SwiftCrossUI

// P58: two scroll views under ONE ScrollViewReader.
//
// The number was checked, not guessed: `ls testapp` gives P50..P57, `git
// ls-files` has no P58, and nothing under testapp/plan or matrix_coverage
// mentions the name.
//
// **This is the shape a code review flagged and nothing in the tree drove.**
// `ScrollAnchorRegistry` used to hold a SINGLE scroll closure. Every
// `ScrollView` under a reader installs one on every update, so with two of them
// the second overwrote the first -- and then scrolling to an id inside the
// FIRST container called the SECOND one, which duly scrolled to wherever that
// widget was not. The registry now keys its closures by container identity, and
// `scroll(to:anchor:)` asks all of them because each implementation ignores a
// widget that is not inside it.
//
// The fix was structural and P56 could not have caught it: P56 has one scroll
// view, and with one scroll view the broken code and the fixed code do the same
// thing. That is the whole reason this app exists.
//
// WHAT MAKES IT EVIDENCE. **Both columns are photographed at once, and the one
// that must NOT move is half the reading.** Press "left to 30" and the left
// column jumps to 30 while the right column stays at row 0. Under the old
// single-closure code the right column is the one that moves, because it
// installed its closure last -- and a capture of only the left column looks
// identical either way.
//
// The two columns carry different labels -- `L0..L59` and `R0..R59` -- so a
// screenshot names which container is showing what. Same-numbered rows in both
// columns would make a jump in the wrong column read as a success.
//
// P58:同一個 ScrollViewReader 底下的兩個捲動視圖。
//
// 這個編號是查過的,不是猜的:`ls testapp` 給出 P50..P57,`git ls-files` 中沒有 P58,而
// testapp/plan 與 matrix_coverage 底下都沒有提到這個名字。
//
// **這正是一次程式碼審查指出、而樹裡沒有任何東西實際驅動過的形狀。** `ScrollAnchorRegistry` 過去
// 只持有**一個** scroll closure。reader 底下的每一個 `ScrollView` 都會在每次更新時安裝一個,因此
// 有兩個時,第二個會覆寫第一個——接著「捲到第一個容器中的某個 id」會呼叫到第二個容器,而它會盡責地
// 捲到「那個 widget 不在的地方」。registry 現在以容器身分為索引鍵持有各自的 closure,而
// `scroll(to:anchor:)` 會問過全部,因為每一個實作都會忽略不在自己內部的 widget。
//
// 那次修正是結構性的,而 P56 抓不到它:P56 只有一個捲動視圖,而在只有一個時,壞掉的程式碼與修好的
// 程式碼做的是同一件事。那正是這支 app 存在的全部理由。
//
// 什麼使它成為證據。**兩欄是同時被拍下的,而「那個不該動的欄」是讀數的另一半。** 按下「left to 30」
// 之後,左欄跳到 30,而右欄停在 row 0。在舊的單一 closure 程式碼下,會動的是右欄——因為它是最後
// 安裝 closure 的那一個——而一張只拍左欄的截圖,兩種情況看起來完全相同。
//
// 兩欄採用不同的標籤——`L0..L59` 與 `R0..R59`——因此一張截圖就能說出是哪一個容器顯示了什麼。若兩欄
// 使用相同的編號,一次「跳錯欄」會讀起來像是成功。

enum P58Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P58] \(message)")

        // Written as well as printed, per the SCUI_DEBUG_EVENTS_DIR contract in
        // testapp/test_support/test_common.zsh. A GUI app does not exit, so a
        // pipe's buffer is never flushed and printing alone is unreadable from
        // a script -- which is how an earlier sweep read a file that was never
        // created as a pass in every scenario.
        // 除了 print 之外也寫出檔案,依 testapp/test_support/test_common.zsh 中的
        // SCUI_DEBUG_EVENTS_DIR 約定。GUI app 不會結束,因此管線的緩衝區永遠不會被沖出,只靠
        // print 在腳本中讀不到——而那正是先前一次掃描把「從未被建立的檔案」在每個情境下都讀成通過的
        // 原因。
        guard let data = "P58 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p58-debug-events.log")
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

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P58 ready for two-container scroll checks")
    }
}

@main
@HotReloadable
struct P58TwoScrollViewsApp: App {
    var body: some Scene {
        WindowGroup("P58 two scroll views, one reader") {
            #hotReloadable {
                P58RootView()
            }
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P58RootView: View {
    @State var asked = "(nothing yet)"

    /// Sixty rows each, so a jump to 30 or 45 cannot be confused with rest.
    /// 每欄六十列,好讓「跳到 30 或 45」不會與靜止位置混淆。
    let rows = Array(0..<60)

    var body: some View {
        // ONE reader over BOTH scroll views. Two readers would each get their
        // own registry and the containers could not collide, which is the
        // opposite of what this app is for.
        // **一個** reader 涵蓋**兩個**捲動視圖。兩個 reader 會各自拿到自己的 registry,兩個容器
        // 便不可能相撞,而那與這支 app 的目的正好相反。
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                Text("P58: two scroll views, one reader")
                    .font(.system(size: 20))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text("asked to scroll to: \(asked)")

                HStack(spacing: 8) {
                    Button("left to L30") {
                        asked = "L30"
                        proxy.scrollTo("L30")
                        P58Diagnostics.write("scrollTo L30 -- right column must stay at R0")
                    }
                    Button("right to R45") {
                        asked = "R45"
                        proxy.scrollTo("R45")
                        P58Diagnostics.write("scrollTo R45 -- left column must not move")
                    }
                    Button("both home") {
                        asked = "L0 then R0"
                        proxy.scrollTo("L0")
                        proxy.scrollTo("R0")
                        P58Diagnostics.write("scrollTo L0 then R0")
                    }
                }

                Text(
                    "Expected: one press moves ONE column. The column that stays put is half "
                        + "the evidence -- with a single shared closure the other column is the "
                        + "one that moves, and a capture of just one column reads the same either "
                        + "way."
                )
                Text(
                    "預期:一次按下只會移動**一欄**。停著不動的那一欄是證據的另一半——在只有一個共用 "
                        + "closure 的情況下,會動的是另一欄,而一張只拍其中一欄的截圖,兩種情況讀起來相同。"
                )

                HStack(spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rows) { index in
                                // Widened for the same reason P56 widens its
                                // rows: AppKit's overlay scroll bar sits on the
                                // digits at natural width, and the digits are
                                // the entire evidence.
                                // 加寬的理由與 P56 相同:在自然寬度下,AppKit 的覆蓋式捲軸會壓在
                                // 數字上,而那些數字正是全部的證據。
                                Text("L\(index)")
                                    .frame(width: 300, alignment: .leading)
                                    .id("L\(index)")
                            }
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rows) { index in
                                Text("R\(index)")
                                    .frame(width: 300, alignment: .leading)
                                    .id("R\(index)")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P58Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P58Diagnostics.renderComplete()
        }
    }
}
