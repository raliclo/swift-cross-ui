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
//
// The same stacks answer the platform's own Back (BackendFeatures.BackNavigation):
// actions/*/P114-native-back*.actions pop with it, and on iOS
// P114-interactive-back.actions drives the edge swipe that follows the finger.
// Fruits also has "Open sheet": a sheet with a NavigationStack of its own
// (Sheet home -> Apples -> Pears), logged as `sheet path -> depth N` and
// `sheet shown: true|false`; P114-sheet-back.actions checks that Back pops the
// sheet's stack while the sheet is in front and never the window's under it.
//
// 同樣的堆疊也回應平台自己的返回(BackendFeatures.BackNavigation):actions/*/P114-native-back*.actions 用它彈出;iOS 上
// P114-interactive-back.actions 驅動跟著手指移動的邊緣滑動。Fruits 也有「Open sheet」:一個有自己 NavigationStack 的 sheet
// (Sheet home → Apples → Pears),記錄為 `sheet path -> depth N` 與 `sheet shown: true|false`;P114-sheet-back.actions 檢查
// sheet 在前景時返回彈出 sheet 的堆疊，而永遠不彈出它底下視窗的堆疊。

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
    @State var showSheet = false
    @State var sheetPath = NavigationPath()

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
            P114Screen(name: name, path: $path, showSheet: $showSheet)
        }
        .onChange(of: depth) {
            depths.append(depth)
            P114Log.write(
                "path -> depth \(depth): \(depths.map(String.init).joined(separator: " "))"
            )
        }
        .sheet(isPresented: $showSheet) {
            P114SheetView(path: $sheetPath, isPresented: $showSheet)
        }
        .onChange(of: Self.depth(of: sheetPath)) {
            P114Log.write("sheet path -> depth \(Self.depth(of: sheetPath))")
        }
        .onChange(of: showSheet) {
            P114Log.write("sheet shown: \(showSheet)")
        }
    }

    /// The path's depth, counted from its `Codable` form, because
    /// `NavigationPath.count` is not public.
    /// 路徑的深度，從其 `Codable` 形式計數，因為 `NavigationPath.count` 不是公開的。
    var depth: Int { Self.depth(of: path) }

    static func depth(of path: NavigationPath) -> Int {
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
    var showSheet: Binding<Bool>
    @State var note = "ab cd"

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
                    Button("Open sheet") { showSheet.wrappedValue = true }
                case "Untitled":
                    Text("This screen has no navigationTitle.")
                    Text("Expected back control: ‹ Fruits")
                    NavigationLink("Open Leaf", value: "Leaf", path: path)
                default:
                    Text("Expected back control: ‹ Back")
                    // Leaf's field. On macOS Option+Left inside it moves one word and is
                    // not Back; elsewhere no field uses Alt+Left, so it still goes Back.
                    // P114-textfield-alt-left.actions types into it.
                    // Leaf 的文字框。macOS 上在框內按 Option+Left 是往左一個字，不是返回；其他平台的文字框不用 Alt+Left,所以仍然返回。P114-textfield-alt-left.actions 在其中輸入。
                    TextField("Note", text: $note)
                        .onChange(of: note) { P114Log.write("note: \"\(note)\"") }
            }
        }
        .padding(16)
    }
}

/// The sheet, opened from Fruits: a NavigationStack of its own, so that the
/// platform's Back pops the sheet's stack while the sheet is in front and
/// never the window's stack under it. Its depth is logged as
/// `sheet path -> depth N`, and `sheet shown: true|false` when it opens and
/// closes.
/// 從 Fruits 開啟的 sheet:它有自己的 NavigationStack,讓 sheet 在前景時平台的返回彈出 sheet 的堆疊，而永遠不彈出它底下視窗
/// 的堆疊。深度記錄為 `sheet path -> depth N`,開啟與關閉時記錄 `sheet shown: true|false`。
struct P114SheetView: View {
    var path: Binding<NavigationPath>
    var isPresented: Binding<Bool>

    var body: some View {
        NavigationStack(path: path) {
            VStack(spacing: 12) {
                Text("Sheet screen: Sheet home")
                NavigationLink("Sheet: open Apples", value: "Apples", path: path)
                Button("Close sheet") { isPresented.wrappedValue = false }
            }
            .padding(16)
            .navigationTitle("Sheet home")
        }
        .navigationDestination(for: String.self) { name in
            VStack(spacing: 12) {
                Text("Sheet screen: \(name)")
                if name == "Apples" {
                    NavigationLink("Sheet: open Pears", value: "Pears", path: path)
                }
                Button("Close sheet") { isPresented.wrappedValue = false }
            }
            .padding(16)
            .navigationTitle(name)
        }
        .frame(width: 360, height: 300)
    }
}
