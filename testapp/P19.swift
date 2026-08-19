import DefaultBackend
import Foundation
import SwiftCrossUI

// P19 flat menus, for comparing WinUIBackend against GtkBackend.
//
// The two backends render the same `Menu` through different mechanisms. A
// backend conforms to one of two protocols and `menuImplementationStyle`
// selects between them:
//
//   AttachedMenus / menuButton      the menu is attached to a button widget and
//                                   arrives through updateButton. WinUIBackend.
//   PopoverMenus / dynamicPopover   a separate menu widget is created and shown
//                                   at a position relative to another widget.
//                                   GtkBackend.
//
// These are two implementations of one feature, not a capability one backend
// lacks. The app cannot pick: it declares a menu and the backend renders it its
// own way. So the comparison is what the same declaration looks like and how it
// behaves on each side, and this app keeps that to the simplest possible shape.
//
// P19 covers a flat menu only -- one level, every item kind. Nested submenus are
// P20, kept separate because they are where the two mechanisms are most likely
// to diverge, and mixing them here would make a failure ambiguous.
//
// P19 平面選單，用於比較 WinUIBackend 與 GtkBackend。
//
// 兩個 backend 以不同機制呈現同一個 `Menu`。backend 擇一實作下列兩個 protocol，並由
// `menuImplementationStyle` 決定採用哪一種：
//
//   AttachedMenus / menuButton      選單直接附加於按鈕 widget，經由 updateButton 傳入。
//                                   WinUIBackend 屬此。
//   PopoverMenus / dynamicPopover   另行建立選單 widget，再相對於其他 widget 顯示。
//                                   GtkBackend 屬此。
//
// 兩者是同一功能的兩種實作，而非其中一方缺少能力。App 端無法選擇：它只宣告選單，由
// backend 以自己的方式呈現。因此比較的對象是「同一份宣告在兩邊長成什麼樣、行為如何」，
// 而本 app 刻意把它維持在最簡單的形狀。
//
// P19 只涵蓋平面選單——單層、涵蓋所有項目種類。巢狀子選單屬於 P20，刻意分開，因為那是
// 兩種機制最可能分歧之處；混在一起會使失敗難以歸屬。
//
// Build this file as a standalone app target.

enum P19Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P19] \(message)")

        guard let data = "P19 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p19-debug-events.log")
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
        write("RENDER COMPLETE -- P19 ready for flat menu checks")
    }
}

@main
@HotReloadable
struct P19FlatMenusApp: App {
    var body: some Scene {
        WindowGroup("P19 flat menus") {
            #hotReloadable {
                P19RootView()
            }
        }
        .defaultSize(width: 660, height: 460)
    }
}

struct P19RootView: View {
    @State var lastAction = "nothing yet"
    @State var toggleItem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P19: flat menus")
                .font(.system(size: 20))

            Text(
                "One menu, one level, every item kind. Open it on both backends "
                    + "and compare what appears and where."
            )

            // Every MenuItem case except .submenu, which is P20. Kept in one
            // menu so a single open shows the whole set side by side.
            // 除了 .submenu（屬於 P20）以外的每一種 MenuItem。集中在同一個選單中，
            // 好讓單次開啟即可並列看到完整集合。
            Menu("Open the menu") {
                Button("Button item") {
                    lastAction = "button item"
                    P19Diagnostics.write("clicked: button item")
                }
                Text("Text item, not clickable")
                Divider()
                Toggle("Toggle item", isOn: $toggleItem)
                Button("Second button item") {
                    lastAction = "second button item"
                    P19Diagnostics.write("clicked: second button item")
                }
            }

            Text("last action -> \(lastAction)")
            Text("toggle item -> \(toggleItem)")
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text(
                "Worth comparing: whether the text item and separator render at "
                    + "all, whether the toggle shows its state, and where the "
                    + "menu appears relative to the button."
            )
        }
        .padding(18)
        .onAppear {
            P19Diagnostics.renderComplete()
        }
    }
}
