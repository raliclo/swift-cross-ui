// P92: CommandGroup -- commands placed in the system's own menu groups, as in SwiftUI (2026-10-13).
//
// All twenty placements, each with one item. SCUI_P92_MODE chooses where the items go:
//   after      (default) "AFTER-<placement>" at the end of every group
//   before     "BEFORE-<placement>" at the start of every group
//   replacing  "REPLACING-<placement>" in place of every group's own items
//   base       no groups: the menus as the system has them
//   dupfile    CommandMenu("File") and CommandMenu("Custom"): two more menus, nothing merged
// SCUI_P92_MENU=1 also calls .enableMenu(), which is what turns the standard menus on where the
// platform has none of its own (GTK, WinUI, Android, iPhone); macOS has them regardless.
//
// The reference is a real SwiftUI app with the same groups, testapp/reference/swiftui-commands/,
// dumped on macOS in the same five modes.
//
// Pass:
//   1 the menu bar holds the same menus, in the same order, with the same items in the same
//     places as the reference dump for the mode (macOS: compared line by line from the dump this
//     app writes under --debug; system-added Edit items such as Writing Tools are not the app's)
//   2 choosing an item shows its name on the "last command" line
//   3 the window's "layout" lines are what the framework handed the backend
// Fail: an item in the wrong menu or group, a default item left in after `replacing`, a menu
// named like a system menu merged into it, or an item that does nothing.
//
// P92:CommandGroup——把指令放進系統自有的選單群組，與 SwiftUI 相同(2026-10-13)。二十個位置各放一個項目;
// SCUI_P92_MODE 決定放在哪:after(預設)、before、replacing、base(不加群組)、dupfile(同名選單不合併)。
// SCUI_P92_MENU=1 會另外呼叫 .enableMenu(),在平台沒有自己選單的地方(GTK、WinUI、Android、iPhone)打開標準選單。
// 基準是有相同群組的真正 SwiftUI app(testapp/reference/swiftui-commands/)。通過:選單列的選單、順序、項目位置與該模式的
// 基準傾印相同;選擇項目後「last command」顯示它的名稱;視窗裡的 layout 各行就是框架交給 backend 的內容。
// 失敗:項目在錯的選單或群組、replacing 之後預設項目還在、與系統選單同名的選單被併進去，或項目沒有作用。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
final class P92Model: SwiftCrossUI.ObservableObject {
    static let shared = P92Model()
    @SwiftCrossUI.Published var last = "none"
    @SwiftCrossUI.Published var presses = 0

    static let mode = ProcessInfo.processInfo.environment["SCUI_P92_MODE"] ?? "after"
    static let menuEnabled = ProcessInfo.processInfo.environment["SCUI_P92_MENU"] == "1"

    func pressed(_ name: String) {
        last = name
        presses += 1
        print("[P92] command \(name)")
    }

    @CommandsBuilder
    static var commands: Commands {
        if mode == "dupfile" {
            CommandMenu("File") {
                Button("DUP-ITEM") { shared.pressed("DUP-ITEM") }
            }
            CommandMenu("Custom") {
                Button("CUSTOM-ITEM") { shared.pressed("CUSTOM-ITEM") }
            }
        }
        if mode == "after" || mode == "before" || mode == "replacing" {
            for placement in CommandGroupPlacement.all {
                group(placement)
            }
        }
    }

    static func group(_ placement: CommandGroupPlacement) -> CommandGroup {
        let name = "\(mode.uppercased())-\(placement.name)"
        switch mode {
            case "before":
                return CommandGroup(before: placement) { Button(name) { shared.pressed(name) } }
            case "replacing":
                return CommandGroup(replacing: placement) { Button(name) { shared.pressed(name) } }
            default:
                return CommandGroup(after: placement) { Button(name) { shared.pressed(name) } }
        }
    }

    /// The layout the framework makes of the commands, as text.
    /// 框架替這些指令排出的版面，以文字表示。
    static var layoutText: String {
        commands.layout(
            appName: ProcessInfo.processInfo.processName,
            defaults: { _ in true }
        ).textDescription
    }

    #if canImport(AppKit)
        /// The real menu bar, in the form the reference dumps are in.
        /// 真正的選單列，格式與基準傾印相同。
        static func dumpMenuBar() {
            var lines: [String] = []
            func dump(_ menu: NSMenu, _ depth: Int) {
                for item in menu.items {
                    let pad = String(repeating: "  ", count: depth)
                    if item.isSeparatorItem {
                        lines.append("\(pad)---")
                        continue
                    }
                    var mods = ""
                    let mask = item.keyEquivalentModifierMask
                    if mask.contains(.control) { mods += "^" }
                    if mask.contains(.option) { mods += "~" }
                    if mask.contains(.shift) { mods += "$" }
                    if mask.contains(.command) { mods += "@" }
                    let key = item.keyEquivalent.isEmpty ? "" : "  [\(mods)\(item.keyEquivalent)]"
                    // The entries AppKit keeps in the Window menu for the open windows are its own.
                    // AppKit 在 Window 選單裡替開著的視窗維護的項目是它自己的。
                    if item.action == #selector(NSWindow.makeKeyAndOrderFront(_:)) { continue }
                    lines.append("\(pad)\(item.title)\(key)\(item.isHidden ? "  (hidden)" : "")")
                    if let submenu = item.submenu { dump(submenu, depth + 1) }
                }
            }
            if let menu = NSApp.mainMenu { dump(menu, 0) }
            let directory =
                ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
            let url = URL(fileURLWithPath: directory).appendingPathComponent("p92-menu-\(mode).txt")
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            print("[P92] menu bar written to \(url.path)")
        }
    #endif
}

@main
struct P92App: App {
    var body: some Scene {
        WindowGroup("P92 command groups") {
            #hotReloadable {
                P92View()
            }
        }
        .defaultSize(width: 460, height: 620)
        .commands { P92Model.commands }
        .enableMenu(P92Model.menuEnabled)
    }
}

struct P92View: View {
    @ObservedObject var model = P92Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P92: CommandGroup (mode: \(P92Model.mode))")
            Text("enableMenu: \(P92Model.menuEnabled ? "on" : "off")")
            Text("last command: \(model.last)")
            Text("commands chosen: \(model.presses)")
            Text("layout the framework made (standard menus on):")
            ScrollView {
                Text(P92Model.layoutText)
                    .font(.system(size: 11))
            }
            .frame(height: 440)
        }
        .padding(16)
        .onAppear {
            #if canImport(AppKit)
                if CommandLine.arguments.contains("--debug") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        P92Model.dumpMenuBar()
                    }
                }
            #endif
        }
    }
}
