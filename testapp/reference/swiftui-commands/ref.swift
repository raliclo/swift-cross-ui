import SwiftUI
import AppKit

let mode = CommandLine.arguments.dropFirst().first ?? "base"
let placements: [(String, CommandGroupPlacement)] = [
    ("appInfo", .appInfo),
    ("appSettings", .appSettings),
    ("systemServices", .systemServices),
    ("appVisibility", .appVisibility),
    ("appTermination", .appTermination),
    ("newItem", .newItem),
    ("saveItem", .saveItem),
    ("importExport", .importExport),
    ("printItem", .printItem),
    ("undoRedo", .undoRedo),
    ("pasteboard", .pasteboard),
    ("textEditing", .textEditing),
    ("textFormatting", .textFormatting),
    ("toolbar", .toolbar),
    ("sidebar", .sidebar),
    ("windowSize", .windowSize),
    ("windowList", .windowList),
    ("singleWindowList", .singleWindowList),
    ("windowArrangement", .windowArrangement),
    ("help", .help),
]

func dump(_ menu: NSMenu, _ depth: Int) {
    for item in menu.items {
        let pad = String(repeating: "  ", count: depth)
        if item.isSeparatorItem { print("\(pad)---")
            continue }
        var mods = ""
        let m = item.keyEquivalentModifierMask
        if m.contains(.control) { mods += "^" }
        if m.contains(.option) { mods += "~" }
        if m.contains(.shift) { mods += "$" }
        if m.contains(.command) { mods += "@" }
        let key = item.keyEquivalent.isEmpty ? "" : "  [\(mods)\(item.keyEquivalent)]"
        print("\(pad)\(item.title)\(key)\(item.isHidden ? "  (hidden)" : "")")
        if let sub = item.submenu { dump(sub, depth + 1) }
    }
}

struct Groups: Commands {
    var body: some Commands {
        // 20 groups do not fit one builder; two halves.
        Half(range: 0..<10)
        Half(range: 10..<20)
    }
}
struct Half: Commands {
    let range: Range<Int>
    var body: some Commands {
        One(i: range.lowerBound)
        One(i: range.lowerBound + 1)
        One(i: range.lowerBound + 2)
        One(i: range.lowerBound + 3)
        One(i: range.lowerBound + 4)
        One(i: range.lowerBound + 5)
        One(i: range.lowerBound + 6)
        One(i: range.lowerBound + 7)
        One(i: range.lowerBound + 8)
        One(i: range.lowerBound + 9)
    }
}
struct One: Commands {
    let i: Int
    var body: some Commands {
        let (name, p) = placements[i]
        switch mode {
            case "before": CommandGroup(before: p) { Button("BEFORE-\(name)") {} }
            case "after": CommandGroup(after: p) { Button("AFTER-\(name)") {} }
            case "replacing": CommandGroup(replacing: p) { Button("REPLACING-\(name)") {} }
            default: CommandGroup(after: p) { EmptyView() }
        }
    }
}

struct Content: View {
    var body: some View {
        Group {
            if mode == "rich" {
                NavigationSplitView { Text("side") } detail: { TextEditor(text: .constant("x")) }
                    .toolbar { Button("T") {} }
            } else {
                Text("ref \(mode)")
            }
        }
        .frame(width: 300, height: 200)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            print("=== \(mode) windows=\(NSApp.windows.count)")
            if let menu = NSApp.mainMenu { dump(menu, 0) }
            fflush(stdout)
            exit(0)
        }
    }
}

@main
struct RefApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup { Content() }
            .commands {
                if mode == "dupfile" {
                    CommandMenu("File") { Button("DUP-ITEM") {} }
                    CommandMenu("Custom") { Button("CUSTOM-ITEM") {} }
                }
                if mode == "before" || mode == "after" || mode == "replacing" { Groups() }
            }
    }
}
