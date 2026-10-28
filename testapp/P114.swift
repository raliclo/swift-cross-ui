// P114: NavigationStack's back control is labelled with the title of the screen
// it returns to, and says "Back" when that screen has no title -- as SwiftUI
// labels it.
//
// The stack: Home (root, .navigationTitle("Home")) -> Fruits (titled "Fruits")
// -> Untitled (no navigationTitle) -> Leaf (titled "Leaf"). Expected back
// labels: "‹ Home" on Fruits, "‹ Fruits" on Untitled, "‹ Back" on Leaf.
//
// The action files press every control by its text (`taplabel`), so a back
// control with any other label is not found and the replay fails there:
// pushing Open Fruits, Open Untitled, Open Leaf, then back through "‹ Back",
// "‹ Fruits" and "‹ Home", then Open Fruits and Open Untitled again so the
// final capture shows "‹ Fruits". Every path change is logged as
// `[P114] path -> depth N: ...`.
//
// Pass: the replay reports `replayed`, the log shows depths 1 2 3 2 1 0 1 2 in
// that order, and the final capture shows the Untitled screen under a
// "‹ Fruits" back control.
//
// P114:NavigationStack 的返回控制項以它所要返回之畫面的標題命名，該畫面沒有標題時顯示「Back」——與 SwiftUI 相同。
// 堆疊為 Home(根)→ Fruits → Untitled(沒有 navigationTitle)→ Leaf;預期的返回標籤:Fruits 上是「‹ Home」、
// Untitled 上是「‹ Fruits」、Leaf 上是「‹ Back」。動作檔以文字點擊每個控制項(`taplabel`),因此標籤不對的返回控制項
// 找不到，重放就在那裡失敗。通過條件見上方英文說明。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P114Log {
    /// Appends a line to p114-debug-events.log and stdout.
    /// 在 p114-debug-events.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P114] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p114-debug-events.log")
        guard let data = "P114 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

@main
@HotReloadable
struct P114App: App {
    var body: some Scene {
        WindowGroup("P114 back button label") {
            #hotReloadable {
                P114RootView()
            }
        }
        .defaultSize(width: 480, height: 420)
    }
}

struct P114RootView: View {
    @State var path = NavigationPath()
    @State var depths: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                Text("P114: back button label")
                    .font(.system(size: 16))
                Text("Screen: Home (root)")
                NavigationLink("Open Fruits", value: "Fruits", path: $path)
                Text("depths so far: \(depths.map(String.init).joined(separator: " "))")
            }
            .padding(16)
            .navigationTitle("Home")
            .onAppear {
                P114Log.write("RENDER COMPLETE -- P114 ready")
            }
        }
        .navigationDestination(for: String.self) { name in
            P114Screen(name: name, path: $path)
        }
        .onChange(of: depth) {
            depths.append(depth)
            P114Log.write(
                "path -> depth \(depth): \(depths.map(String.init).joined(separator: " "))"
            )
        }
    }

    /// The path's depth, counted from its `Codable` form, because
    /// `NavigationPath.count` is not public.
    /// 路徑的深度，從其 `Codable` 形式計數，因為 `NavigationPath.count` 不是公開的。
    var depth: Int {
        guard
            let data = try? JSONEncoder().encode(path),
            let entries = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return -1
        }
        return entries.count
    }
}

/// One pushed screen. "Untitled" deliberately sets no navigation title.
/// 一個被推入的畫面。「Untitled」刻意不設定導覽標題。
struct P114Screen: View {
    var name: String
    var path: Binding<NavigationPath>

    var body: some View {
        if name == "Untitled" {
            content
        } else {
            content.navigationTitle(name)
        }
    }

    var content: some View {
        VStack(spacing: 12) {
            Text("Screen: \(name)")
                .font(.system(size: 16))
            switch name {
                case "Fruits":
                    Text("Expected back control: ‹ Home")
                    NavigationLink("Open Untitled", value: "Untitled", path: path)
                case "Untitled":
                    Text("This screen has no navigationTitle.")
                    Text("Expected back control: ‹ Fruits")
                    NavigationLink("Open Leaf", value: "Leaf", path: path)
                default:
                    Text("Expected back control: ‹ Back")
            }
        }
        .padding(16)
    }
}
