import DefaultBackend
import Foundation
import SwiftCrossUI

// P130 badge(_:): a count, a text, and a count of zero, on tabs and on list rows.
//
// A tab strip shows Inbox with 3, News with "New" and Archive with 0, which
// hides the badge. A list below shows the same three rows plus one without any
// badge. The screenshot is the check for the look: a red pill after the Inbox
// and News tab buttons, a grey pill at the trailing edge of the Inbox and News
// rows, and nothing beside Archive in either place.
//
// The app also measures, a second after it appears, and logs "P130 PASS" or
// "P130 FAIL (...)" to p130-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout:
// - a fixed-size strip with badges is wider than the same strip without them,
//   and a strip whose badges are all 0 is exactly as wide as the plain one;
// - the 3 and "New" rows are as wide as each other (the badge pushes them to
//   the row's trailing edge), wider than the 0 row, and the 0 row is exactly
//   as wide as the plain row.
//
// P130 badge(_:):數字、文字與數字零，分別用於分頁與清單列。
//
// 分頁列顯示 Inbox 帶 3、News 帶「New」、Archive 帶 0(即隱藏徽章)。下方的清單顯示相同的三列，
// 再加上一列沒有徽章的。截圖用來檢查外觀:Inbox 與 News 分頁按鈕後面各有一顆紅色膠囊，Inbox 與
// News 列的尾端各有一顆灰色膠囊，Archive 在兩處旁邊都沒有任何東西。
//
// app 也在出現一秒後量測，並在 p130-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下
// 「P130 PASS」或「P130 FAIL (...)」:
// - 帶徽章的固定尺寸分頁列比同一個不帶徽章的分頁列寬，而徽章全為 0 的分頁列與無徽章者完全等寬；
// - 3 與「New」兩列彼此等寬(徽章把它們推到列尾端)、比 0 那列寬，而 0 那列與無徽章那列完全等寬。
//
// Build this file as a standalone app target.

enum P130 {
    static let title = "P130 Badge"

    @MainActor static var sizes: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p130-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    @MainActor static func verdict() -> String {
        var failures: [String] = []
        func width(_ name: String) -> Double? {
            guard let size = sizes[name] else {
                failures.append("\(name) not measured")
                return nil
            }
            log("P130 \(name): \(size.width)x\(size.height)")
            return size.width
        }
        if let badged = width("tabs badged"), let plain = width("tabs plain"),
            let zero = width("tabs zero")
        {
            if !(badged > plain) { failures.append("tab badges add no width") }
            if zero != plain { failures.append("badge(0) changed the tab strip") }
        }
        if let three = width("row Inbox"), let new = width("row News"),
            let zero = width("row Archive"), let plain = width("row Plain")
        {
            if three != new { failures.append("badged rows differ in width") }
            if !(three > zero) { failures.append("row badge adds no width") }
            if zero != plain { failures.append("badge(0) changed the row") }
        }
        return failures.isEmpty ? "P130 PASS" : "P130 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P130App: App {
    var body: some Scene {
        WindowGroup(P130.title) {
            P130View()
        }
        .defaultSize(width: 520, height: 560)
    }
}

struct P130Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P130Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P130Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P130.sizes[name] = size
        return Color.clear
    }
}

/// What badge a row or tab carries. / 一列或一個分頁所帶的徽章。
enum P130Badge {
    case count(Int)
    case text(String)
    case none
}

struct P130Row {
    var name: String
    var badge: P130Badge
}

/// One list row: a label in a fixed-width frame, so every row is the same width
/// without a badge and only a badge can change it.
/// 一個清單列：標籤放在固定寬度的 frame 中，因此沒有徽章時每列等寬，只有徽章能改變寬度。
struct P130RowLabel: View {
    var row: P130Row

    var label: some View {
        Text("Item \(row.name)").frame(width: 120, alignment: .leading)
    }

    var body: some View {
        switch row.badge {
            case .count(let count):
                label.badge(count)
            case .text(let text):
                label.badge(text)
            case .none:
                label
        }
    }
}

/// Builds a tab with the given badge. / 以指定的徽章建立分頁。
@MainActor
func p130Tab(_ title: String, _ badge: P130Badge) -> Tab {
    let tab = Tab(title) { Text("\(title) page") }
    switch badge {
        case .count(let count): return tab.badge(count)
        case .text(let text): return tab.badge(text)
        case .none: return tab
    }
}

struct P130View: View {
    @State var verdict = "Measuring"
    @State var selectedRow: String? = nil

    static let rows = [
        P130Row(name: "Inbox", badge: .count(3)),
        P130Row(name: "News", badge: .text("New")),
        P130Row(name: "Archive", badge: .count(0)),
        P130Row(name: "Plain", badge: .none),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(P130.title)
            Text(verdict)

            Text("Tabs: Inbox 3, News \"New\", Archive 0 (hidden)")
            P130Measured(
                name: "tabs badged",
                content: TabView {
                    p130Tab("Inbox", .count(3))
                    p130Tab("News", .text("New"))
                    p130Tab("Archive", .count(0))
                }
                .fixedSize()
            )
            Text("The same tabs without badges, and with every badge 0")
            P130Measured(
                name: "tabs plain",
                content: TabView {
                    p130Tab("Inbox", .none)
                    p130Tab("News", .none)
                    p130Tab("Archive", .none)
                }
                .fixedSize()
            )
            P130Measured(
                name: "tabs zero",
                content: TabView {
                    p130Tab("Inbox", .count(0))
                    p130Tab("News", .count(0))
                    p130Tab("Archive", .count(0))
                }
                .fixedSize()
            )

            Text("List rows: 3, \"New\", 0 (hidden), no badge")
            List(Self.rows, id: \.name, selection: $selectedRow) { row in
                P130Measured(name: "row \(row.name)", content: P130RowLabel(row: row))
            }
            .frame(width: 360, height: 180)
        }
        .padding(16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P130.verdict()
                P130.log(result)
                verdict = result
            }
        }
    }
}
