import SwiftUI
import UIKit

let mode = ProcessInfo.processInfo.environment["REF_MODE"] ?? "base"
let placements: [(String, CommandGroupPlacement)] = [
    ("appInfo", .appInfo), ("appSettings", .appSettings), ("systemServices", .systemServices),
    ("appVisibility", .appVisibility), ("appTermination", .appTermination),
    ("newItem", .newItem), ("saveItem", .saveItem), ("importExport", .importExport),
    ("printItem", .printItem), ("undoRedo", .undoRedo), ("pasteboard", .pasteboard),
    ("textEditing", .textEditing), ("textFormatting", .textFormatting), ("toolbar", .toolbar),
    ("sidebar", .sidebar), ("windowSize", .windowSize), 
     ("windowArrangement", .windowArrangement),
    ("help", .help),
]

func describe(_ element: UIMenuElement, _ depth: Int, _ lines: inout [String]) {
    let pad = String(repeating: "  ", count: depth)
    if let menu = element as? UIMenu {
        let inline = menu.options.contains(.displayInline)
        lines.append("\(pad)\(inline ? "(inline)" : "MENU") '\(menu.title)' id=\(menu.identifier.rawValue)")
        for child in menu.children { describe(child, depth + 1, &lines) }
    } else if let command = element as? UIKeyCommand {
        lines.append("\(pad)\(command.title)  [key \(command.input ?? "") mods \(command.modifierFlags.rawValue)]")
    } else if let command = element as? UICommand {
        lines.append("\(pad)\(command.title)  <\(NSStringFromSelector(command.action))>")
    } else if let action = element as? UIAction {
        lines.append("\(pad)\(action.title)  (action)")
    } else {
        lines.append("\(pad)? \(type(of: element)) \(element.title)")
    }
}

struct Groups: Commands {
    var body: some Commands {
        // 20 groups do not fit one builder; two halves.
        Half(range: 0..<9)
        Half(range: 9..<18)
    }
}
struct Half: Commands {
    let range: Range<Int>
    var body: some Commands {
        One(i: range.lowerBound); One(i: range.lowerBound + 1); One(i: range.lowerBound + 2)
        One(i: range.lowerBound + 3); One(i: range.lowerBound + 4); One(i: range.lowerBound + 5)
        One(i: range.lowerBound + 6); One(i: range.lowerBound + 7); One(i: range.lowerBound + 8)
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

final class Delegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        var lines: [String] = ["=== \(mode) buildMenu idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)"]
        if let root = builder.menu(for: .root) { describe(root, 0, &lines) }
        print(lines.joined(separator: "\n"))
        print("=== end")
        fflush(stdout)
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("=== launched \(mode)"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // SwiftUI's own app delegate builds the menu; wrap its buildMenu(with:) to read the result.
            guard let real = UIApplication.shared.delegate else { print("no delegate"); return }
            let cls: AnyClass = type(of: real)
            print("=== delegate class \(cls)")
            let selector = #selector(UIResponder.buildMenu(with:))
            guard let method = class_getInstanceMethod(cls, selector) else { print("no method"); return }
            typealias Original = @convention(c) (AnyObject, Selector, any UIMenuBuilder) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, any UIMenuBuilder) -> Void = { object, builder in
                original(object, selector, builder)
                guard builder.system == .main else { return }
                var lines: [String] = ["=== \(mode) buildMenu idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)"]
                if let root = builder.menu(for: .root) { describe(root, 0, &lines) }
                print(lines.joined(separator: "\n")); print("=== end"); fflush(stdout)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
            UIMenuSystem.main.setNeedsRebuild()
            fflush(stdout)
        }
        return true
    }
}

@main
struct RefApp: App {
    @UIApplicationDelegateAdaptor(Delegate.self) var delegate
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
