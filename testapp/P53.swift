import DefaultBackend
import Foundation
import SwiftCrossUI

// P53 exercises .toolbar, the first of task #36's two remaining modifiers.
//
// A toolbar lives in the window's own chrome, which is the one place a
// screenshot of the content area cannot reach -- so this app puts a counter in
// the content and wires every toolbar item to it. If the bar is absent the
// counter never moves; if the bar is present but its actions are not connected,
// the bar shows and the counter still never moves. Those two are different
// failures and the app tells them apart, because "I can see buttons" is not the
// claim.
//
// P53 演練 `.toolbar`,即任務 #36 剩下兩個修飾詞中的第一個。
//
// 工具列位於視窗自身的外框上,而那正是「內容區的截圖」唯一構不到的地方——因此本 app 在內容中放了一個
// 計數器,並把每一個工具列項目都接到它身上。若那條列不存在,計數器永遠不會動;若列存在但它的動作沒有
// 接上,則列會出現而計數器仍然不動。這是兩種不同的失敗,而本 app 分得出來——因為要主張的並不是
// 「我看得到按鈕」。

enum P53Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P53] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P53 ready for toolbar checks")
    }
}

@main
@HotReloadable
struct P53ToolbarApp: App {
    var body: some Scene {
        WindowGroup("P53 toolbar") {
            #hotReloadable {
                P53RootView()
            }
        }
        .defaultSize(width: 720, height: 520)
    }
}

struct P53RootView: View {
    @State var addPresses = 0
    @State var trashPresses = 0
    @State var infoPresses = 0
    @State var lastPressed = "(none)"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P53: toolbar")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            // The counters are the claim. A toolbar that renders and does
            // nothing looks like a success in a screenshot of the chrome.
            // 這些計數器就是主張本身。一個「畫得出來卻沒有作用」的工具列,在一張外框的截圖裡看起來
            // 就是成功。
            Text("add: \(addPresses)   trash: \(trashPresses)   info: \(infoPresses)")
            Text("last pressed: \(lastPressed)")

            Text("Three items are declared: add (leading), trash (trailing), info (primary).")
            Text("Expected: they appear in the window's chrome, not in this content area,")
            Text("and pressing one moves exactly one counter.")
            Text("預期:它們出現在視窗外框上,而不是在這塊內容區裡;按下其中一個,恰好會有一個計數器改變。")

            Text(
                "If the bar is missing, no counter can ever move. If the bar is there but its "
                    + "actions are not wired, the bar shows and no counter moves. The two are "
                    + "different failures and this line is how they are told apart."
            )
        }
        .padding(16)
        .toolbar([
            ToolbarItem("Add", systemImage: "add", placement: .leading) {
                addPresses += 1
                lastPressed = "add"
                P53Diagnostics.write("add pressed, count=\(addPresses)")
            },
            ToolbarItem("Delete", systemImage: "delete", placement: .trailing) {
                trashPresses += 1
                lastPressed = "trash"
                P53Diagnostics.write("trash pressed, count=\(trashPresses)")
            },
            ToolbarItem("Info", systemImage: "info", placement: .primary) {
                infoPresses += 1
                lastPressed = "info"
                P53Diagnostics.write("info pressed, count=\(infoPresses)")
            },
        ])
        .onAppear {
            P53Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P53Diagnostics.write("toolbar items add/leading trash/trailing info/primary")
            P53Diagnostics.renderComplete()
        }
    }
}
