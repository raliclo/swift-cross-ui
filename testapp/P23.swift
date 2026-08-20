import DefaultBackend
import Foundation
import SwiftCrossUI

// P23 tables, for comparing WinUIBackend against GtkBackend.
//
// Table and TableColumn appear in no other test app. The equivalent in
// gtk4-widget-factory is its column view, and the questions are the same ones:
// how are column widths decided, what happens when the content is wider than
// the column, and does the table scroll or clip when there are more rows than
// space.
//
// Column width is the interesting part. Nothing in the API states a width, so
// each backend picks: from the header, from the widest cell, from the first
// screenful of cells, or by dividing the available space. Those choices give
// visibly different tables from identical code, and the deliberately uneven
// column contents below are there to make which one is in use obvious.
//
// P23 表格，用於比較 WinUIBackend 與 GtkBackend。
//
// Table 與 TableColumn 未出現在任何其他測試 app 中。gtk4-widget-factory 的對應項目是它的
// column view，而要問的問題相同：欄寬如何決定、內容寬於欄位時會發生什麼、以及列數超過可用
// 空間時表格是捲動還是裁切。
//
// 欄寬是有趣之處。API 中並未指定寬度，因此各 backend 自行決定：依標題、依最寬的儲存格、依
// 第一屏的儲存格，或平分可用空間。這些選擇會讓相同的程式碼產生外觀明顯不同的表格，而下方
// 刻意設計成長短不一的欄位內容，正是為了讓當前採用哪一種變得顯而易見。
//
// Build this file as a standalone app target.

enum P23Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P23] \(message)")

        guard let data = "P23 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p23-debug-events.log")
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

    /// Formats a dimension that may not be finite.
    ///
    /// `Int(_:)` traps on infinity and NaN, and a GeometryReader over a table
    /// gets exactly that: the table proposes an unbounded size, so the width
    /// arrives as infinity. Once GtkBackend implemented Tables and this app got
    /// past its startup fatalError, that trap was the next thing it hit --
    /// reported as `Double value cannot be converted to Int`, in this file
    /// rather than in the backend that had just been fixed.
    ///
    /// 格式化一個可能非有限的尺寸值。
    ///
    /// `Int(_:)` 對無限大與 NaN 會 trap，而套在表格上的 GeometryReader 得到的正是這種值：
    /// 表格提出的是無上限的尺寸，因此寬度會以無限大的形式傳入。當 GtkBackend 實作了 Tables、
    /// 本 app 越過其啟動時的 fatalError 之後，這個 trap 就是它撞上的下一件事——回報為
    /// `Double value cannot be converted to Int`，且發生在本檔中，而非剛被修好的那個 backend。
    private static func describe(_ value: Double) -> String {
        value.isFinite ? "\(Int(value))" : "unbounded"
    }

    static func record(label: String, size: ViewSize) {
        guard isEnabled else { return }
        let line = "\(label): \(describe(size.width)) x \(describe(size.height))"
        guard lastReported[label] != line else { return }
        lastReported[label] = line
        write(line)
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P23 ready for table checks")
    }
}

struct P23Row {
    var id: Int
    var short: String
    var long: String
    var number: String
}

// Column two is deliberately far wider than its header and column three far
// narrower, so a backend sizing from the header looks different from one sizing
// from the cells at a glance.
// 第二欄刻意遠寬於其標題，第三欄則遠窄於標題，如此「依標題決定寬度」與「依儲存格決定寬度」
// 的 backend 一眼即可分辨。
let p23Rows: [P23Row] = (1...24).map { index in
    P23Row(
        id: index,
        short: "r\(index)",
        long: index == 3
            ? "a considerably longer cell than any header would suggest"
            : "row \(index) content",
        number: "\(index * 1117)"
    )
}

@main
@HotReloadable
struct P23TablesApp: App {
    var body: some Scene {
        WindowGroup("P23 tables") {
            #hotReloadable {
                P23RootView()
            }
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct P23RootView: View {
    @State var rowCount = 8
    @State var isSelectable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P23: tables")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text(
                "Column 2 is wider than its header and column 3 is narrower. "
                    + "Compare where the boundaries land and what happens as "
                    + "rows are added."
            )

            HStack(spacing: 8) {
                Button("Fewer rows") { rowCount = max(1, rowCount - 4) }
                Button("More rows") { rowCount = min(p23Rows.count, rowCount + 4) }
                Text("rows: \(rowCount)")
            }

            // Selection is opt-in and off by default, so the toggle is the only
            // way to see the difference -- and having both states in one run is
            // the point: a table that is selectable when nobody asked for it is
            // as much a defect as one that is not when somebody did.
            //
            // 選取功能為 opt-in 且預設關閉，因此此開關是唯一能看出差異的方式——而讓兩種狀態出現在
            // 同一次執行中正是重點：沒有人要求卻可選取的表格，與有人要求卻不可選取的表格，同樣是
            // 缺陷。
            HStack(spacing: 8) {
                Button(isSelectable ? "Selection on" : "Selection off") {
                    isSelectable.toggle()
                }
                Text("drag across a cell to check")
            }

            // Deliberately not wrapped in P23Measured. The measuring overlay sits
            // on top of what it measures, and a table under it never sees a
            // pointer event -- neither a header nor a cell could be selected
            // while it was there, even with `selectable` confirmed set on all 36
            // labels. Column widths are still readable from the screenshot,
            // which is what steps 1 and 2 actually compare.
            //
            // 刻意不使用 P23Measured 包裝。量測用的 overlay 位於其所量測對象的上方，位於其下的
            // 表格收不到任何指標事件——在 overlay 存在時，即使已確認全部 36 個 label 都設定了
            // `selectable`，標題與儲存格都無法被選取。欄寬仍可由截圖判讀，而那正是步驟 1 與 2
            // 實際要比較的內容。
            Group {
                Table(Array(p23Rows.prefix(rowCount))) {
                    TableColumn("ID") { (row: P23Row) in Text("\(row.id)") }
                    TableColumn("A much longer header than its cells") { (row: P23Row) in
                        Text(row.short)
                    }
                    TableColumn("Short") { (row: P23Row) in Text(row.long) }
                    TableColumn("Number") { (row: P23Row) in Text(row.number) }
                }
                .tableTextSelection(isSelectable)
            }

            Text(
                "Worth comparing: whether the long cell in row 3 widens its "
                    + "column or is truncated, and whether adding rows past the "
                    + "window height scrolls or clips."
            )
        }
        .padding(18)
        .onAppear {
            P23Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P23Diagnostics.renderComplete()
        }
    }
}

struct P23Measured<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                GeometryReader { proxy in
                    let _ = P23Diagnostics.record(label: label, size: proxy.size)
                    EmptyView()
                }
            }
    }
}
