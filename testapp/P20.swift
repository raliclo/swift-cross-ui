import DefaultBackend
import Foundation
import SwiftCrossUI

// P20 nested menus, for comparing WinUIBackend against GtkBackend.
//
// Separated from P19 on purpose. P19 keeps to one flat level so that a
// difference there is unambiguously about item rendering. Nesting is the part
// where the two mechanisms have the most room to diverge:
//
//   AttachedMenus / menuButton      the platform builds the whole tree from a
//                                   menu object handed to a button.
//   PopoverMenus / dynamicPopover   each level is a widget the backend creates
//                                   and positions itself.
//
// So submenu depth, how a submenu opens, and where it lands relative to its
// parent are all things one side gets from the platform and the other has to
// construct. If nesting breaks while P19 passes, that is the answer.
//
// P20 巢狀選單，用於比較 WinUIBackend 與 GtkBackend。
//
// 刻意與 P19 分開。P19 只保留單一平面層級，使該處的差異明確歸屬於項目的呈現方式。巢狀
// 則是兩種機制最有分歧空間之處：
//
//   AttachedMenus / menuButton      由平台依據交給按鈕的選單物件建構整棵樹。
//   PopoverMenus / dynamicPopover   每一層都是 backend 自行建立並定位的 widget。
//
// 因此子選單的深度、開啟方式，以及相對於父層的落點，一邊是由平台提供、另一邊必須自行
// 建構。若 P19 通過而巢狀失敗，答案就在這裡。
//
// Build this file as a standalone app target.

enum P20Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P20] \(message)")

        guard let data = "P20 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p20-debug-events.log")
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
        write("RENDER COMPLETE -- P20 ready for nested menu checks")
    }
}

@main
@HotReloadable
struct P20NestedMenusApp: App {
    var body: some Scene {
        WindowGroup("P20 nested menus") {
            #hotReloadable {
                P20RootView()
            }
        }
        .defaultSize(width: 660, height: 460)
        // An application menu bar, added 2026-08-27, and the reason is not the
        // menu.
        //
        // No Pn declared `.commands` at all before this, so `showMenuBar` was
        // false in every test app and `menubarHeight(ofWindow:)` returned 0
        // without ever running its body. It had hardcoded 25 points with a TODO
        // beside it saying a theme could change that, and nothing could have
        // caught it either way -- the window would simply have been a few points
        // out, which reads as a layout bug anywhere but there.
        //
        // P20 gets it rather than a new app because it is already the menus one.
        // The items do nothing on purpose: what is under test is the bar's
        // existence and its measured height, not what the entries do, and that
        // is P20's popover section's job.
        //
        // 一列應用程式選單列，於 2026-08-27 加入，而理由並不是選單本身。
        //
        // 在此之前沒有任何 Pn 宣告過 `.commands`，因此每個測試 app 的 `showMenuBar` 都是 false，
        // `menubarHeight(ofWindow:)` 回傳 0 而其主體從未執行過。該函式當時寫死 25 點，旁邊還有一則
        // TODO 說主題可能會改變它——而無論對錯都不可能被抓到：視窗只會差個幾點，那在任何其他地方看
        // 起來都像版面 bug，唯獨不像出在那裡。
        //
        // 由 P20 承接而非另開新 app，因為它本來就是「選單」那一支。其中的項目刻意什麼都不做：此處
        // 受測的是選單列的存在與其被量測到的高度，而非各項目的行為——後者是 P20 popover 段落的職責。
        .commands {
            CommandMenu("P20") {
                Button("Does nothing") {}

                Divider()

                Menu("Submenu") {
                    Button("Also nothing") {}
                }
            }
        }
    }
}

struct P20RootView: View {
    @State var lastAction = "nothing yet"
    @State var deepToggle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P20: nested menus")
                .font(.system(size: 20))

            Text(
                "Three levels deep, with an item at every level so each one can "
                    + "be confirmed to open and respond."
            )

            // An item at each level rather than only at the leaf: if level two
            // opens but its own button does nothing, that is a different fault
            // from level three never appearing.
            // 每一層都放一個項目，而非只在最末層：若第二層打得開、但它自己的按鈕沒有反應，
            // 那與「第三層根本不出現」是不同的缺陷。
            Menu("Open the menu") {
                Button("Level 1 item") {
                    lastAction = "level 1"
                    P20Diagnostics.write("clicked: level 1")
                }
                Divider()
                Menu("Level 2 submenu") {
                    Button("Level 2 item") {
                        lastAction = "level 2"
                        P20Diagnostics.write("clicked: level 2")
                    }
                    Menu("Level 3 submenu") {
                        Button("Level 3 item") {
                            lastAction = "level 3"
                            P20Diagnostics.write("clicked: level 3")
                        }
                        Toggle("Level 3 toggle", isOn: $deepToggle)
                    }
                }
            }

            Text("last action -> \(lastAction)")
            Text("level 3 toggle -> \(deepToggle)")

            Text(
                "Worth comparing: whether level 3 opens at all, whether a "
                    + "submenu opens on hover or only on click, and whether "
                    + "state from a nested toggle reaches the app."
            )
        }
        .padding(18)
        .onAppear {
            P20Diagnostics.renderComplete()
        }
    }
}
