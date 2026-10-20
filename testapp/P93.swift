// P93: several window scenes and the menus -- File > New and the Window menu's list (2026-10-14).
//
// Two window groups, "Alpha" and "Beta", and a single window, "Solo". SwiftUI then replaces
// File > New Window by a New submenu naming each group, Command-N on the first, and lists the
// single window in the Window menu (testapp/reference/swiftui-commands/two-groups.txt).
//
// Pass:
//   1 File holds New > "New Alpha Window" (Cmd-N) and "New Beta Window", not "New Window"
//   2 choosing "New Beta Window" opens a window that reads "beta"
//   3 the Window menu lists "Solo" between Minimize/Zoom and Bring All to Front; choosing it
//     opens the window that reads "solo", and choosing it again opens no second one
//   4 at launch only the Alpha window is open: SwiftUI opens the first scene and no other
//     (measured, see SceneLaunch.swift); every WindowGroup used to open one here
// Fail: a plain New Window with two groups, a group missing from the submenu, Solo absent, or
// a Beta window open at launch.
// macOS writes the real menu bar to p93-menu.txt under --debug, in the reference's format.
//
// P93:多個視窗場景與選單——File > New 與 Window 選單的清單(2026-10-14)。兩個 window group(Alpha、Beta)與一個單一視窗
// (Solo)。SwiftUI 此時把 File > New Window 換成逐一列名的 New 子選單(第一項帶 Command-N),並把單一視窗列在 Window 選單。
// 通過:File 有 New > New Alpha Window(Cmd-N)與 New Beta Window,而不是 New Window;選 New Beta Window 會開出寫著
// beta 的視窗;Window 選單在 Minimize/Zoom 與 Bring All to Front 之間列出 Solo,選它會開出寫著 solo 的視窗，再選一次
// 不會開第二個;啟動時只開 Alpha 的視窗(SwiftUI 只開第一個場景)。失敗:兩個 group 卻只有 New Window、子選單少了某個 group、
// 沒有 Solo,或啟動時就開著 Beta 的視窗。

import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(AppKit)
    import AppKit
#endif

@main
struct P93App: App {
    var body: some Scene {
        WindowGroup("Alpha", id: "alpha") {
            #hotReloadable {
                P93View()
            }
        }
        .defaultSize(width: 420, height: 260)
        // From the environment, or from the arguments where a launch carries no environment
        // (Android): `--p93-menu`, as P92 does. / 取自環境變數;啟動時帶不了環境變數的平台(Android)則取自參數:`--p93-menu`,與 P92 相同。
        .enableMenu(
            ProcessInfo.processInfo.environment["SCUI_P93_MENU"] == "1"
                || CommandLine.arguments.contains("--p93-menu")
        )

        WindowGroup("Beta", id: "beta") {
            Text("beta").padding(30)
        }
        .defaultSize(width: 260, height: 160)

        Window("Solo", id: "solo") {
            Text("solo").padding(30)
        }
        .defaultSize(width: 260, height: 160)
    }
}

struct P93View: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P93: window scenes in the menus")
            Text("alpha -- this is the Alpha group's window")
            Text("File > New lists Alpha and Beta")
            Text("Window lists Solo")
        }
        .padding(16)
        .onAppear {
            #if canImport(AppKit)
                if CommandLine.arguments.contains("--debug") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { P93View.dumpMenuBar() }
                }
            #endif
        }
    }

    #if canImport(AppKit)
        static func dumpMenuBar() {
            var lines: [String] = []
            func dump(_ menu: NSMenu, _ depth: Int) {
                for item in menu.items {
                    let pad = String(repeating: "  ", count: depth)
                    if item.isSeparatorItem {
                        lines.append("\(pad)---")
                        continue
                    }
                    if item.action == #selector(NSWindow.makeKeyAndOrderFront(_:)) { continue }
                    var mods = ""
                    let mask = item.keyEquivalentModifierMask
                    if mask.contains(.control) { mods += "^" }
                    if mask.contains(.option) { mods += "~" }
                    if mask.contains(.shift) { mods += "$" }
                    if mask.contains(.command) { mods += "@" }
                    let key = item.keyEquivalent.isEmpty ? "" : "  [\(mods)\(item.keyEquivalent)]"
                    lines.append("\(pad)\(item.title)\(key)\(item.isHidden ? "  (hidden)" : "")")
                    if let submenu = item.submenu { dump(submenu, depth + 1) }
                }
            }
            if let menu = NSApp.mainMenu { dump(menu, 0) }
            let directory =
                ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                    ?? FileManager.default.currentDirectoryPath
            let url = URL(fileURLWithPath: directory).appendingPathComponent("p93-menu.txt")
            try? (lines.joined(separator: "\n") + "\n").write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        }
    #endif
}
