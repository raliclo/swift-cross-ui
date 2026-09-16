import DefaultBackend
import Foundation
import SwiftCrossUI

// P71: does a menu item's keyboard shortcut actually fire it? (#121)
//
// The number is checked: `ls testapp` gives P50..P70, and nothing under
// testapp/plan or matrix_coverage mentions P71.
//
// **A SHORTCUT THAT IS ONLY DRAWN IS NOT A SHORTCUT.** Every backend can put
// "⌘S" beside a menu item, and a screenshot of that looks exactly like a working
// one. So this app asserts on the COUNTER, not on the menu: the key is pressed
// with the menu CLOSED, and the number on screen has to move. A backend that
// renders the glyph and never fires the action leaves that number at zero.
//
// **THE MENU IS NEVER OPENED**, and that is deliberate. Opening it and clicking
// the item tests the item, which already worked; the whole of #121 is the part
// where the key works without the menu.
//
// Three items, because one would not separate the failures:
//   ⌘S   plain          -- does the key reach the action at all
//   ⇧⌘E  with Shift     -- does the modifier mask survive, or does an uppercase
//                          key equivalent ask for Shift twice
//   ⌘D   disabled       -- a disabled item must NOT fire; a backend that wires
//                          the key without checking `isEnabled` shows up here
//
// P71:選單項目的鍵盤快捷鍵,真的會觸發它嗎?(#121)
//
// 編號是查過的:`ls testapp` 給出 P50..P70,而 testapp/plan 與 matrix_coverage 底下都沒有提到 P71。
//
// **一個「只是被畫出來」的快捷鍵不是快捷鍵。** 每一個 backend 都能在選單項目旁邊放上「⌘S」,而那樣的
// 截圖看起來與一個能用的一模一樣。因此這支 app 斷言的是**計數器**,不是選單:按鍵是在選單**關著**的
// 狀態下送出的,而畫面上的數字必須改變。一個「畫出字形卻從不觸發動作」的 backend,會把那個數字留在零。
//
// **選單從頭到尾不會被開啟**,而那是刻意的。開啟它並點擊該項目,測到的是那個**項目**——而那本來就能用;
// #121 的全部,正是「按鍵在不開選單的情況下也能用」的那一半。
//
// 三個項目,因為只有一個分不開那些失敗:
//   ⌘S   單純        —— 那個按鍵究竟有沒有抵達那個動作
//   ⇧⌘E  帶 Shift    —— 那個 modifier mask 有沒有存活,或者大寫的 key equivalent 是否要了兩次 Shift
//   ⌘D   已停用      —— 一個被停用的項目**不得**被觸發;一個「接了按鍵卻沒檢查 `isEnabled`」的
//                       backend 會在這裡現形

enum P71Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P71] \(message)")

        guard let data = "P71 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p71-debug-events.log")
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
        write("RENDER COMPLETE -- P71 ready for shortcut presses")
    }
}

/// What the shortcuts have fired, shared so the menu closure and the view see
/// one object.
///
/// The menu is built from the Scene, outside any view, so the counters cannot
/// live in `@State` -- the closure would capture a value the view never reads.
/// A shared instance is the only place both halves can reach.
/// 那些快捷鍵觸發了什麼;共用一個物件,好讓選單 closure 與 view 看到的是同一個。
///
/// 選單是從 Scene 建出來的、位於任何 view 之外,因此那些計數器不能住在 `@State` 裡——那個 closure 會
/// 捕捉一個 view 永遠讀不到的值。共用實例是兩半唯一都抵達得了的地方。
final class P71Counts: SwiftCrossUI.ObservableObject {
    @MainActor static let shared = P71Counts()
    @SwiftCrossUI.Published var plain = 0
    @SwiftCrossUI.Published var shifted = 0
    @SwiftCrossUI.Published var disabled = 0
}

@main
@HotReloadable
struct P71App: App {
    var body: some Scene {
        WindowGroup("P71 menu shortcuts") {
            #hotReloadable {
                P71RootView()
            }
        }
        .defaultSize(width: 520, height: 360)
        .commands {
            CommandMenu("P71") {
                Button("Plain") {
                    P71Counts.shared.plain += 1
                    P71Diagnostics.write("PLAIN fired, now \(P71Counts.shared.plain)")
                }
                .keyboardShortcut("s")

                Button("Shifted") {
                    P71Counts.shared.shifted += 1
                    P71Diagnostics.write("SHIFTED fired, now \(P71Counts.shared.shifted)")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                // Disabled, and the shortcut is still declared. A backend that
                // registers the key without consulting `isEnabled` fires this
                // and the counter moves, which is the whole reason the item is
                // here rather than simply omitted.
                // 已停用,而快捷鍵仍然被宣告。一個「登記了按鍵卻沒有參考 `isEnabled`」的 backend 會
                // 觸發它、讓計數器移動——而那正是這個項目存在、而不是乾脆省略的全部理由。
                Button("Disabled") {
                    P71Counts.shared.disabled += 1
                    P71Diagnostics.write("DISABLED FIRED -- wrong")
                }
                .keyboardShortcut("d")
                .disabled(true)
            }
        }
    }
}

struct P71RootView: View {
    @ObservedObject var counts = P71Counts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P71: menu shortcuts (#121)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Plain    (Cmd-S)        fired: \(counts.plain)")
            Text("Shifted  (Cmd-Shift-E)  fired: \(counts.shifted)")
            Text("Disabled (Cmd-D)        fired: \(counts.disabled)")

            Text(
                "Expected after the replay: plain 1, shifted 1, disabled 0. "
                    + "The menu is never opened -- a count of 0 on the first two means the "
                    + "shortcut is drawn but not wired."
            )
            Text(
                "重放後的預期:plain 1、shifted 1、disabled 0。選單從頭到尾不會被開啟——前兩項若為 0,"
                    + "代表那個快捷鍵被畫出來了,但沒有接上。"
            )
        }
        .padding(20)
        .onAppear {
            P71Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P71Diagnostics.renderComplete()
        }
    }
}
