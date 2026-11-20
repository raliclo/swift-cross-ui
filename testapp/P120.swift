import DefaultBackend
import Foundation
import SwiftCrossUI

// P120 NavigationSplitView in a compact window: one column at a time, as SwiftUI.
//
// A two-column NavigationSplitView of three fruits. "Compact" and "Regular" force the
// size class, so a desktop window shows the phone behaviour too; "Window" lets the
// window's width decide (compact below 600 points). It starts compact.
//
// Compact: choosing a row in the sidebar List shows the detail column with a
// "‹ Back" bar; Back returns to the sidebar and clears the row. The app watches the
// column it is given and logs each move; once it has seen a row take it to the
// detail column and Back bring it to the sidebar with no row chosen, it logs
// "P120 PASS" to p120-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout and shows
// it in the window. Regular: both columns side by side and no back bar.
//
// P120 compact 視窗中的 NavigationSplitView:與 SwiftUI 相同，一次一欄。
//
// 三種水果的兩欄 NavigationSplitView。「Compact」與「Regular」強制尺寸類別，讓桌面視窗也能呈現手機的行為;
// 「Window」則由視窗寬度決定(低於 600 點為 compact)。啟動時為 compact。
//
// Compact:在側邊欄的 List 選一列會顯示詳細欄並帶有「‹ Back」列;Back 回到側邊欄並清除那一列。app 監看
// 交給它的欄並記錄每次移動；一旦看到「選列帶到詳細欄」以及「Back 回到側邊欄且沒有選中的列」,就在
// p120-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P120 PASS」,並顯示在視窗中。
// Regular:兩欄並排，沒有返回列。
//
// Build this file as a standalone app target.

enum P120 {
    static let title = "P120 NavigationSplitView compact"
    static let fruits = ["Apple", "Banana", "Cherry"]

    static func name(of column: NavigationSplitViewColumn) -> String {
        switch column {
            case .sidebar: "sidebar"
            case .content: "content"
            default: "detail"
        }
    }

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p120-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }
}

@main
struct P120App: App {
    var body: some Scene {
        WindowGroup(P120.title) {
            P120View()
        }
        .defaultSize(width: 520, height: 480)
    }
}

/// Which size class the split view is given. / 交給 split view 的尺寸類別。
enum P120Mode {
    case compact
    case regular
    case window
}

struct P120View: View {
    @State var mode = P120Mode.compact
    @State var selected: String? = nil
    @State var column = NavigationSplitViewColumn.sidebar
    /// 0: nothing yet. 1: a row reached the detail column. 2: Back returned with
    /// no row chosen, which is the pass.
    /// 0:尚無。1:選列已到達詳細欄。2:Back 回來且沒有選中的列，即通過。
    @State var stage = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(P120.title)
            Text("Column: \(P120.name(of: column)) · Selected: \(selected ?? "none")")
            Text(stage == 2 ? "P120 PASS" : "Waiting: step \(stage + 1) of 2")
            HStack(spacing: 8) {
                Button("Compact") { mode = .compact }
                Button("Regular") { mode = .regular }
                Button("Window") { mode = .window }
            }
            split
                .frame(height: 300)
        }
        .padding(8)
    }

    @ViewBuilder
    var split: some View {
        let view = NavigationSplitView(preferredCompactColumn: watchedColumn) {
            List(P120.fruits, id: \.self, selection: $selected) { fruit in
                Text(fruit)
            }
        } detail: {
            Text(selected.map { "Detail: \($0)" } ?? "Choose a fruit")
        }
        switch mode {
            case .compact: view.environment(\.horizontalSizeClass, .compact)
            case .regular: view.environment(\.horizontalSizeClass, .regular)
            case .window: view
        }
    }

    /// The column binding, logging every move the split view makes.
    /// 欄的綁定，記錄 split view 的每一次移動。
    var watchedColumn: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { column },
            set: { newColumn in
                column = newColumn
                let chosen = selected
                P120.log("P120 column \(P120.name(of: newColumn)), selected \(chosen ?? "none")")
                if stage == 0, newColumn == .detail, chosen != nil {
                    stage = 1
                } else if stage == 1, newColumn == .sidebar, chosen == nil {
                    stage = 2
                    P120.log("P120 PASS")
                }
            }
        )
    }
}
