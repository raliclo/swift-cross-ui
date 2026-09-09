import DefaultBackend
import Foundation
import SwiftCrossUI

// P56: does ScrollViewReader actually scroll?
//
// The number was checked, not guessed. `ls testapp` gives P50..P55, `git ls-files`
// has no P56, and nothing under matrix_coverage or testapp/plan mentions the name.
// A free filename and a free NAME are different questions -- see P46's header.
//
// **ScrollViewReader, ScrollViewProxy and `.id(_:)` landed on all five backends
// in 33856017 and have never been run.** That commit says so. This app is the
// running half.
//
// HOW A FAILURE LOOKS. A scroll that does nothing leaves row 0 at the top, which
// is also what the app looks like before any button is pressed -- so the picture
// alone cannot separate "scrolled" from "did not scroll" unless the rows are
// distinguishable and the destination is far from the start. Sixty rows, each
// numbered, and the jumps are to 30 and 59.
//
// The status line is the second half of that. `scrollTo` is silent when the id
// is unknown or no ScrollView installed a closure, which is right -- both are
// application mistakes and warning on every frame would be worse -- but it means
// a mistyped id and a broken backend produce the same still picture. The line
// records what was ASKED for, so "asked for 30" beside a view still showing row
// 0 is a different failure from a line that never changed.
//
// P56:ScrollViewReader 真的會捲動嗎?
//
// 這個編號是查過的,不是猜的。`ls testapp` 給出 P50..P55,`git ls-files` 中沒有 P56,而 matrix_coverage
// 與 testapp/plan 底下都沒有提到這個名字。「檔名是空的」與「名字是空的」是兩個不同的問題——見 P46 的檔頭。
//
// **ScrollViewReader、ScrollViewProxy 與 `.id(_:)` 於 33856017 在五個 backend 上落地,而且從未被執行過。**
// 那個 commit 自己就這麼寫。這支 app 就是「執行」的那一半。
//
// 失敗長什麼樣。一次什麼都沒做的捲動,會讓第 0 列留在頂端——而那也正是「還沒有人按過任何按鈕」時這支
// app 的樣子——因此單憑畫面無法分辨「捲了」與「沒捲」,除非那些列彼此可辨、而且目的地離起點很遠。
// 六十列、每一列都有編號,而跳躍的目標是 30 與 59。
//
// 狀態列是那件事的另一半。`scrollTo` 在 id 未知、或沒有任何 ScrollView 安裝過 closure 時是靜默的,
// 而那是對的——兩者都是應用程式的錯誤,而逐幀警告會更糟——但那也意味著「打錯的 id」與「壞掉的 backend」
// 會產出同一張靜止的畫面。這一行記錄的是「被要求了什麼」,因此「asked for 30」旁邊配上一個仍然停在第 0 列
// 的畫面,與「這一行從未改變」是兩種不同的失敗。

enum P56Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P56] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P56 ready for scroll checks")
    }
}

@main
@HotReloadable
struct P56ScrollViewReaderApp: App {
    var body: some Scene {
        WindowGroup("P56 scroll view reader") {
            #hotReloadable {
                P56RootView()
            }
        }
        .defaultSize(width: 620, height: 520)
    }
}

struct P56RootView: View {
    @State var asked = "(nothing yet)"

    /// Sixty, so a jump to 30 or 59 cannot be confused with the resting
    /// position, and so the destination is well past one screenful on every
    /// device this runs on -- a phone shows about a dozen.
    /// 六十列,好讓「跳到 30 或 59」不會與靜止位置混淆,也讓目的地在本 app 會執行的每一種裝置上都遠
    /// 超過一個畫面——手機大約顯示十來列。
    let rows = Array(0..<60)

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                Text("P56: ScrollViewReader")
                    .font(.system(size: 20))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text("asked to scroll to: \(asked)")

                // Outside the ScrollView, which is the whole point of the
                // reader: a button that scrolled away with the content could
                // not be pressed a second time.
                // 位於 ScrollView 之外,而那正是這個 reader 的全部意義:一顆會隨著內容一起捲走的按鈕,
                // 沒有辦法被按第二次。
                HStack(spacing: 8) {
                    Button("Jump to 30") {
                        asked = "30"
                        proxy.scrollTo(30)
                        P56Diagnostics.write("scrollTo 30")
                    }
                    Button("Jump to 59") {
                        asked = "59"
                        proxy.scrollTo(59)
                        P56Diagnostics.write("scrollTo 59")
                    }
                    Button("Back to 0") {
                        asked = "0"
                        proxy.scrollTo(0)
                        P56Diagnostics.write("scrollTo 0")
                    }
                }

                Text(
                    "Expected: the list jumps so the named row is visible. The row numbers are "
                        + "the evidence -- a scroll that did nothing leaves row 0 at the top, "
                        + "which is also how this app starts."
                )
                Text(
                    "預期:清單會跳動,使被指名的那一列可見。列的編號就是證據——一次什麼都沒做的捲動"
                        + "會讓第 0 列留在頂端,而那也正是這支 app 一開始的樣子。"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { index in
                            // Widened so the scroll bar does not sit on the
                            // digits. Measured first: at natural width the
                            // content is as wide as "row 0" and AppKit's
                            // overlay scroll bar covered the number, so the
                            // capture read "row (" -- and the number is the
                            // entire evidence this app produces.
                            // 加寬,好讓捲軸不會壓在數字上。這是先量過的:在自然寬度下,內容就只有
                            // 「row 0」那麼寬,而 AppKit 的覆蓋式捲軸蓋住了那個數字,於是擷圖讀起來
                            // 是「row (」——而那個數字正是這支 app 所產出的全部證據。
                            Text("row \(index)")
                                .frame(width: 360, alignment: .leading)
                                .id(index)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P56Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P56Diagnostics.renderComplete()
        }
    }
}
