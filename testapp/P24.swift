import DefaultBackend
import Foundation
import SwiftCrossUI

// P24 navigation stack, for comparing WinUIBackend against GtkBackend.
//
// NavigationStack and NavigationLink appear in no other test app. This gap was
// previously dismissed on the grounds that P7 and P16 cover navigation, which
// was wrong: those exercise NavigationSplitView, a different type with a
// different layout model. A sidebar-and-detail split is not a push-and-pop
// stack.
//
// What a stack has that a split view does not is history. Pushing three levels
// and then going back should return through them in order, and the path should
// still be consistent afterwards. Backends that rebuild rather than pop, or
// that lose the path on a state change, show it here and nowhere else.
//
// P24 導覽堆疊，用於比較 WinUIBackend 與 GtkBackend。
//
// NavigationStack 與 NavigationLink 未出現在任何其他測試 app 中。此缺口先前被以「P7 與 P16
// 已涵蓋導覽」為由劃掉，那是錯的：那兩支測的是 NavigationSplitView，屬於不同型別、不同的
// 版面模型。側邊欄加詳細內容的分割，並不等同於推入與彈出的堆疊。
//
// 堆疊有而分割檢視沒有的東西是「歷史」。推入三層之後返回，應依序退回，且之後路徑仍須保持
// 一致。若某個 backend 是重建而非彈出、或在狀態變更時遺失路徑，只有在此處才會顯現。
//
// Build this file as a standalone app target.

enum P24Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P24] \(message)")

        guard let data = "P24 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p24-debug-events.log")
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
        write("RENDER COMPLETE -- P24 ready for navigation stack checks")
    }
}

@main
@HotReloadable
struct P24NavigationStackApp: App {
    var body: some Scene {
        WindowGroup("P24 navigation stack") {
            #hotReloadable {
                P24RootView()
            }
        }
        .defaultSize(width: 720, height: 560)
    }
}

struct P24RootView: View {
    @State var path = NavigationPath()
    @State var counter = 0
    @State var pushCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P24: navigation stack")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            // Depth is tracked separately rather than read from the path.
            // NavigationPath.count is internal, so an app cannot ask how deep it
            // is; this counter is updated alongside every push and pop instead.
            // Keeping it outside the stack is the point: if the screen shows
            // level 2 while this says 3, that disagreement is the finding, and
            // it would be invisible if the only indicator lived inside.
            // 深度另行追蹤，而非從路徑讀取。NavigationPath.count 是 internal，app 無法查詢
            // 目前深度；因此改為在每次推入與彈出時同步更新此計數器。將它放在堆疊之外正是重點：
            // 若畫面顯示第 2 層而此處顯示 3，該不一致就是發現；若唯一的指示位於堆疊內部，
            // 便無從察覺。
            Text("pushes recorded (outside the stack) -> \(pushCount)")
            Text("counter -> \(counter)")

            HStack(spacing: 8) {
                Button("Increment counter") {
                    counter += 1
                    P24Diagnostics.write("counter \(counter), pushes \(pushCount)")
                }
                Button("Pop to root") {
                    path = NavigationPath()
                    pushCount = 0
                    P24Diagnostics.write("popped to root")
                }
            }

            // Destinations are attached with `navigationDestination(for:)`
            // rather than a trailing closure on the initialiser; the init takes
            // only a path and a root.
            // 目的地以 `navigationDestination(for:)` 附加，而非在建構式上使用尾隨閉包；
            // 該建構式只接受路徑與根視圖。
            NavigationStack(path: $path) {
                P24Level(level: 0, path: $path, onPush: { pushCount += 1 })
            }
            .navigationDestination(for: Int.self) { level in
                P24Level(level: level, path: $path, onPush: { pushCount += 1 })
            }
        }
        .padding(18)
        .onAppear {
            P24Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P24Diagnostics.renderComplete()
        }
    }
}

struct P24Level: View {
    var level: Int
    // NavigationLink needs the path binding itself, so every level is handed
    // one rather than the stack routing pushes on its behalf.
    // NavigationLink 需要路徑綁定本身，因此每一層都直接取得該綁定，而非由堆疊代為處理推入。
    var path: Binding<NavigationPath>
    var onPush: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Level \(level)")
                .font(.system(size: 17))

            Text(
                level == 0
                    ? "Root. Push to go deeper."
                    : "Pushed to level \(level)."
            )

            NavigationLink("Push level \(level + 1)", value: level + 1, path: path)

            // Recorded from a plain button as well as the link, so the count
            // stays honest if a backend routes link activation differently.
            // 除了連結之外，也以一般按鈕記錄，如此即使某個 backend 以不同方式處理連結的
            // 啟動，計數仍然可信。
            Button("Record a push") {
                onPush()
                P24Diagnostics.write("push recorded at level \(level)")
            }
        }
        .padding(12)
    }
}
