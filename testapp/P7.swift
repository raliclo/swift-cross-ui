import DefaultBackend
import Foundation
import SwiftCrossUI

// P7 Linux (GtkBackend) repro app: lists and split views.
//
// - #476 The List control starts with the first item already selected on the
//   GTK backend, even though no selection was set.
// - #556 Gtk List NavigationSplitView makes weird size decisions.
//
// Both are about a List reporting or occupying something other than what it
// was asked to. The selection binding starts as nil here on purpose, so any
// selection visible at launch came from the backend rather than from the app.
//
// Build this file as a standalone app target.
//
// Run with `--debug` to print the split view's measured geometry. Without it
// the app stays quiet, so a normal UI run is not buried in log lines.

/// Geometry logging for #556, behind `--debug`.
///
/// `GeometryProxy` exposes `size` and no origin, so there is no way to ask a
/// view where it sits. The divider's x position is therefore derived: it is the
/// sidebar's width, measured from the sidebar itself. That is the number #556
/// is actually about, so the missing origin costs nothing here.
///
/// Measurements are taken through `.overlay`, which lays the content out
/// against the original proposal and then proposes exactly that size to the
/// overlay, so reading them does not change what is being measured.
/// 以 `--debug` 控制的 #556 幾何量測。`GeometryProxy` 只提供 `size` 而沒有原點，
/// 因此分隔線的 x 座標是由 sidebar 寬度推導——那正好就是 #556 要問的數字。量測
/// 透過 `.overlay` 取得，它會以內容自身的尺寸被提案，因此不會改變受測的版面。
enum P7Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    /// Layout runs many times per interaction and a geometry reader may be
    /// evaluated several times before the layout settles, so only changes are
    /// printed. Keyed by label, and never read off the main thread.
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    /// Appends to `p7-debug-events.log` beside the executable's working
    /// directory, following P6Diagnostics.
    ///
    /// Writing to a file rather than stdout is not a preference. A WinUI app is
    /// a GUI-subsystem process with no console attached, so `print` goes
    /// nowhere there: the first version of this printed fine under GTK and
    /// produced zero lines on Windows, which is useless for an issue whose
    /// whole point is comparing the two backends.
    /// 寫檔而非 stdout 並非偏好問題：WinUI 應用程式是 GUI 子系統程序、沒有主控台，
    /// `print` 在該處毫無輸出。而 #556 的重點正是跨 backend 比對。
    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P7] \(message)")

        guard let data = "P7 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p7-debug-events.log")
        if FileManager.default.fileExists(atPath: logURL.path),
            let handle = try? FileHandle(forWritingTo: logURL)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    /// Reports a measured *content* size. The probes sit on the pane contents,
    /// not on the panes, so these are what the content occupies -- labelled
    /// `content` to keep them apart from the pane widths in the split line
    /// below, which are derived from the total. The two genuinely differ: the
    /// detail content can be far narrower than the pane holding it.
    /// 回報量測到的「內容」尺寸。探針掛在 pane 的內容上而非 pane 本身，因此標示為
    /// `content`，以免與下方 split 行的 pane 寬度混淆——兩者確實不同。
    static func report(_ label: String, width: Double, height: Double) {
        guard isEnabled else { return }
        let line = String(format: "%.0fx%.0f", width, height)
        guard lastReported[label] != line else { return }
        lastReported[label] = line
        write("\(label) content: \(line)")
    }

    nonisolated(unsafe) private static var sidebarWidth: Double?
    nonisolated(unsafe) private static var totalWidth: Double?
    nonisolated(unsafe) private static var hasMeasuredDetail = false
    nonisolated(unsafe) private static var hasAnnouncedRender = false

    static func record(role: P7SplitProbe.Role, size: ViewSize) {
        guard isEnabled else { return }
        report(role.rawValue, width: size.width, height: size.height)

        switch role {
            case .sidebar: sidebarWidth = size.width
            case .total: totalWidth = size.width
            case .detail: hasMeasuredDetail = true
        }

        if let sidebarWidth, let totalWidth {
            reportSplit(total: totalWidth, sidebar: sidebarWidth)

            // Emitted once, when every pane has been measured at least once.
            // A screenshot taken before this is a picture of a half-built
            // window; waiting a fixed number of seconds instead is a guess that
            // is either wrong or wasteful. Poll the log for this line.
            /// 三個探針都回報過之後只印一次。在此之前截圖拍到的是尚未組完的視窗，
            /// 而固定等待秒數只是猜測——不是拍太早就是白等。改為輪詢這一行。
            if hasMeasuredDetail, !hasAnnouncedRender {
                hasAnnouncedRender = true
                write("RENDER COMPLETE -- all panes measured, safe to capture")
            }
        }
    }

    /// How much of the split view the sidebar's *content* occupies.
    ///
    /// This is not the divider position and must not be read as one. The probes
    /// measure content, and a list does not necessarily fill the pane it sits
    /// in: with the sidebar pane at 200, this reported 87 on WinUI and 31 on
    /// Gtk. Reading those as pane widths produced two confident and completely
    /// wrong diagnoses. The divider itself is only visible from inside
    /// SplitView.commit -- run with SCUI_DEBUG_SPLIT for that.
    /// 這是 sidebar「內容」佔的比例，**不是分隔線位置**。探針量的是內容，而清單未必
    /// 填滿它所在的 pane：pane 為 200 時，此處在 WinUI 回報 87、Gtk 回報 31。
    static func reportSplit(total: Double, sidebar: Double) {
        guard isEnabled, total > 0 else { return }
        let ratio = sidebar / total * 100
        let line = String(
            format: "sidebar content=%.0f  remaining=%.0f  total=%.0f  content fills %.1f%%",
            sidebar, total - sidebar, total, ratio
        )
        guard lastReported["split"] != line else { return }
        lastReported["split"] = line
        write(line)
    }
}

/// Writes a trace line to a file, unconditionally, from the earliest points the
/// app reaches.
///
/// Needed because nothing else survives. P7 starts on Windows/GtkBackend and is
/// gone within seconds, and none of the usual evidence exists: stdout and stderr
/// reach nobody, `P7Diagnostics` only writes when `--debug` is passed *and*
/// `onAppear` runs, and the Windows event log records no application error.
/// Running it from a shell looks like an instant clean exit, but that is only
/// how cmd launches a GUI-subsystem binary -- P18, which works, reports exit 0
/// the same way.
///
/// So the trace is unconditional, goes straight to a file, and is placed at
/// three points. Which of them appears says where it died: none means before
/// Swift ran at all, and the last one present is the last thing that worked.
///
/// 在 app 所能抵達的最早幾個時點，無條件將追蹤訊息寫入檔案。
///
/// 之所以必要，是因為其他證據全都留不下來。P7 在 Windows/GtkBackend 上啟動後數秒內即消失，而
/// 平常可用的線索一項都不存在：stdout 與 stderr 無人收到；`P7Diagnostics` 只有在同時傳入
/// `--debug` *且* `onAppear` 執行時才會寫入；Windows 事件記錄中也沒有任何應用程式錯誤。從
/// shell 執行看起來像是立即乾淨結束，但那只是 cmd 啟動 GUI subsystem 執行檔的方式——能正常運作
/// 的 P18 也同樣回報 exit 0。
///
/// 因此這個追蹤是無條件的、直接寫入檔案，並放置於三個時點。哪幾個出現即說明它死在何處：一個都
/// 沒有代表 Swift 根本尚未執行，而最後出現的那一個就是最後一件成功的事。
enum P7Startup {
    static func trace(_ stage: String) {
        let line = "P7 \(Date()) startup: \(stage)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p7-startup.log")
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
}

@main
@HotReloadable
struct P7ListsApp: App {
    // In `init`, which runs before `body` is ever asked for. If this line is
    // missing the app never got as far as constructing its App type.
    // 置於 `init`，它先於任何對 `body` 的求值執行。若此行缺席，代表 app 從未進行到建構其 App
    // 型別的階段。
    init() {
        P7Startup.trace("App.init")
    }

    var body: some Scene {
        P7Startup.trace("App.body evaluated")
        return WindowGroup("P7 lists and split views") {
            #hotReloadable {
                P7RootView()
            }
        }
        .defaultSize(width: 720, height: 480)
    }
}

struct P7Fruit: Identifiable, Hashable {
    var id: String { name }
    var name: String
}

/// Reports the size it was given and draws nothing.
///
/// The measurement happens in `init` rather than in `body` so it is a plain
/// side effect of building the view value, not something that could be mistaken
/// for state. Nothing here writes `@State`: doing that from inside a layout
/// pass would feed back into the layout being measured.
/// 回報自身被賦予的尺寸，不繪製任何東西。量測放在 `init` 而非 `body`，且不寫入
/// 任何 `@State`——在 layout 過程中寫 state 會回饋到它正在量測的 layout。
struct P7SplitProbe: View {
    enum Role: String {
        case sidebar
        case detail
        case total
    }

    init(role: Role, size: ViewSize) {
        P7Diagnostics.record(role: role, size: size)
    }

    var body: some View {
        EmptyView()
    }
}

struct P7RootView: View {
    // Deliberately nil: at launch nothing should appear selected. #476 is that
    // the first row appears selected anyway.
    @State var selection: String?
    @State var sidebarSelection: String?
    @State var eventLog = "Ready. Nothing should be selected yet."

    let fruits = [
        P7Fruit(name: "Apple"),
        P7Fruit(name: "Banana"),
        P7Fruit(name: "Cherry"),
        P7Fruit(name: "Date"),
        P7Fruit(name: "Elderberry"),
    ]

    var body: some View {
        // Third trace point. Reaching this means the App type built, the scene
        // built, and the root view is being asked to describe itself -- so a
        // failure after it is in the view tree or the backend, not in startup.
        // 第三個追蹤點。抵達此處代表 App 型別已建構、scene 已建構，且根視圖正被要求描述自身
        // ——因此在此之後的失敗屬於視圖樹或 backend，而非啟動階段。
        P7Startup.trace("RootView.body evaluated")
        return VStack(spacing: 12) {
            Text("P7: lists and split views")
                .font(.system(size: 20))

            Text("Selection: \(selection ?? "none")")
            Text(eventLog)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plain List (#476)")
                    List(fruits, selection: $selection) { fruit in
                        Text(fruit.name)
                    }
                    .frame(width: 200, height: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NavigationSplitView with a List (#556)")
                        .frame(width: 420, height: 24, alignment: .leading)
                    NavigationSplitView {
                        List(fruits, selection: $sidebarSelection) { fruit in
                            Text(fruit.name)
                        }
                        .overlay(alignment: .topLeading) {
                            GeometryReader { proxy in
                                P7SplitProbe(role: .sidebar, size: proxy.size)
                            }
                        }
                    } detail: {
                        VStack {
                            Text(sidebarSelection ?? "No sidebar selection")
                            // Experiment for #556: the split view asks this pane
                            // what it needs when proposed a width of 0, and the
                            // answer drives the sidebar's maximum. Without
                            // fixedSize the text answers with its full unwrapped
                            // width, which leaves the sidebar no room at all.
                            Text("This detail pane should keep its share of the width.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .overlay(alignment: .topLeading) {
                            GeometryReader { proxy in
                                P7SplitProbe(role: .detail, size: proxy.size)
                            }
                        }
                    }
                    .frame(width: 420, height: 180)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { proxy in
                            P7SplitProbe(role: .total, size: proxy.size)
                        }
                    }
                }
                .padding(.leading, 32)
            }

            HStack(spacing: 8) {
                Button("Clear selection") {
                    selection = nil
                    sidebarSelection = nil
                    eventLog = "Cleared. Both lists should show nothing selected."
                }
                Button("Select Cherry") {
                    selection = "Cherry"
                    eventLog = "Set selection to Cherry from code."
                }
                Button("Add a fruit's worth of text") {
                    eventLog =
                        "A longer message, to see whether the split view "
                        + "re-lays out when the text around it grows."
                }
            }
        }
        .padding(12)
    }
}
