import DefaultBackend
import Foundation
// `@_spi(Backends)` for `BackendFeatures`, which the #125 conformance readout
// asks about. P57 imports it the same way for the same reason.
// 需要 `@_spi(Backends)` 才能取得 `BackendFeatures`——#125 的 conformance 讀數要問它。
// P57 也是以同樣方式、同樣理由引入。
@_spi(Backends) import SwiftCrossUI

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
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
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
    /// Asked of the backend for the conformance readout below, the same way P57
    /// asks about lazy rows.
    /// 用於下方那行 conformance 讀數,問的是 backend——與 P57 詢問 lazy rows 的方式相同。
    @Environment(\.backend) var backend
    @State var rowCount = 8
    @State var isSelectable = false
    /// #125 row selection. Separate from `isSelectable`, which is TEXT
    /// selection -- two different features that would otherwise be read as one.
    /// #125 的列選取。與 `isSelectable`(那是**文字**選取)分開:兩個不同的功能,不分開會被讀成同一個。
    @State var selectedRow: Int?

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

            // #125 row selection, and BOTH DIRECTIONS are on screen because they
            // fail separately. The readout is what a click writes into the
            // binding; the two buttons are the framework writing into the
            // backend. A backend that highlights on click but ignores
            // `setSelectedRow` passes a screenshot of one and fails the other.
            //
            // The conformance line is asked of the backend rather than inferred
            // from which files exist -- the same shape P57 uses for lazy rows,
            // and for the same reason: Android compiled a conformance and took
            // the other path anyway.
            //
            // #125 的列選取,而**兩個方向**都放在畫面上,因為它們會各自失敗。那行讀數是「點擊寫進
            // binding 的東西」;兩個按鈕則是「框架寫進 backend 的東西」。一個「點了會高亮、卻忽略
            // `setSelectedRow`」的 backend,會通過其中一張截圖而在另一張上失敗。
            //
            // conformance 那一行是**去問 backend** 的,不是從「有哪些檔案存在」推論——與 P57 對
            // lazy rows 所用的形狀相同,理由也相同:Android 曾經把一個 conformance 編了進去,
            // 然後照樣走了另一條路。
            HStack(spacing: 8) {
                Button("Select row 2") { selectedRow = 2 }
                Button("Clear selection") { selectedRow = nil }
                Text("selected row: \(selectedRow.map(String.init) ?? "none")")
            }
            Text(
                "row selection supported: "
                    + "\(backend is any BackendFeatures.TableSelection ? "yes" : "NO")"
            )

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
                Table(Array(p23Rows.prefix(rowCount)), selection: $selectedRow) {
                    // #125, added 2026-09-10. `.width(200)` on ID -- the column
                    // with the NARROWEST content -- and nothing on the other
                    // three.
                    //
                    // WIDE, NOT NARROW, AND THE FIRST VERSION OF THIS TEST WAS
                    // WORTHLESS. It used `.width(60)`, reasoning that ID holds
                    // one or two digits so an even quarter of the table is
                    // absurd for it. The capture showed ID at about 58 px and I
                    // nearly recorded that as a pass -- but ID would be the
                    // narrowest column anyway, because GTK sizes a Grid column
                    // from its widest child and ID's widest child is the word
                    // "ID". A working `.width(60)` and an IGNORED `.width(60)`
                    // produce the same picture.
                    //
                    // 200 cannot be faked. Nothing in this column is 200 px
                    // wide, so if ID is the WIDEST of the four, the only thing
                    // that can have done it is the width being honoured.
                    //
                    // THE HEADER IS HALF OF THE ASSERTION. On GTK a column's
                    // width comes from its widest child, so headers and cells
                    // are sized separately and a fix reaching only one leaves
                    // "ID" over a column it does not match. That is why
                    // `Gtk.Table` stores the widths rather than applying them
                    // once -- see its `columnWidths`.
                    //
                    // WHAT THIS DOES NOT ASSERT: that the other three end up
                    // equal. They do not, and should not -- GTK gives each
                    // hexpanding column its natural width first and shares only
                    // the surplus, which is why this app's own intro line says
                    // column 2 is wider than its header and column 3 narrower.
                    // An earlier draft of this comment demanded they be equal;
                    // that was a claim about a layout model this backend does
                    // not use.
                    //
                    // #125,2026-09-10 加入。`.width(200)` 加在**內容最窄**的 ID 欄上,其餘三欄不給。
                    //
                    // **用寬的、不是窄的——而本測試的第一版毫無價值。** 它用的是 `.width(60)`,理由是
                    // ID 只裝一兩位數字,平分表格的四分之一對它而言荒謬。擷圖顯示 ID 約 58 px,
                    // 而我差一點就把它記成通過——但**ID 本來就會是最窄的一欄**,因為 GTK 依「該欄最寬的
                    // 子元件」決定欄寬,而 ID 最寬的子元件就是「ID」這個詞。**一個生效的 `.width(60)`
                    // 與一個被忽略的 `.width(60)`,產生同一張圖。**
                    //
                    // 200 偽造不了。這一欄裡沒有任何東西有 200 px 寬,因此若 ID 成為四欄中**最寬**的,
                    // 唯一可能造成它的就是寬度確實被遵守了。
                    //
                    // **標題是斷言的一半。** 在 GTK 上欄寬取決於該欄最寬的子元件,因此標題與儲存格
                    // 分開決定尺寸,只顧到其中一邊的修正會讓「ID」壓在一個與它不相符的欄位上方。
                    // 那正是 `Gtk.Table` 要**儲存**寬度而非套用一次就算了的原因——見其 `columnWidths`。
                    //
                    // **本項不斷言的事**:另外三欄會相等。它們不相等,也不應該相等——GTK 先給每個
                    // hexpand 的欄它的自然寬度,只把**剩餘**的部分拿去分配,而這正是本 app 自己的
                    // 開場白說「第 2 欄比它的標題寬、第 3 欄比較窄」的原因。本註解的較早草稿要求它們
                    // 相等;那是一項關於「本 backend 並未採用之版面模型」的主張。
                    TableColumn("ID") { (row: P23Row) in Text("\(row.id)") }
                        .width(200)
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
            P23Diagnostics.write(
                "row selection supported: "
                    + "\(backend is any BackendFeatures.TableSelection ? "yes" : "NO")"
            )
            P23Diagnostics.renderComplete()
            driveSelectionIfAsked()
        }
        // **The log line says which direction produced it**, because the two
        // fail separately and a bare "SELECTION now 2" cannot tell them apart:
        // a backend that highlights on click but ignores `setSelectedRow`
        // writes the same line as one that does both.
        //
        // `onChange` prints TRANSITIONS. The verdict is the last value, and the
        // screen carries it -- read as a failure once already, mistakes.md
        // entry 14.
        //
        // **這行 log 會說出它是由哪個方向產生的**,因為兩個方向會各自失敗,而單獨一行
        // 「SELECTION now 2」分不出它們:一個「點了會高亮、卻忽略 `setSelectedRow`」的 backend,
        // 寫出來的是同一行。
        //
        // `onChange` 印的是**轉換**。判決是最終值,而那個值在畫面上——這一點曾經被讀成失敗一次,
        // 見 mistakes.md 第 14 條。
        .onChange(of: selectedRow) {
            P23Diagnostics.write(
                "SELECTION now \(selectedRow.map(String.init) ?? "none")"
            )
        }
    }

    /// `--select-probe`: moves the selection on a timer, with no mouse.
    ///
    /// **It drives the half that does not need a pointer, and only that half.**
    /// Writing the binding exercises the whole framework-to-backend path --
    /// `@State` -> commit -> `setSelectedRow(ofTable:to:)` -> the highlight on
    /// screen -- which is the direction a backend can implement and still fail
    /// at, independently of hit-testing. The other direction, a click becoming
    /// a binding write, cannot be faked from inside the process and is left to
    /// an action file.
    ///
    /// `DispatchQueue.main.asyncAfter` on both backends, not `g_timeout_add`:
    /// P70 drives its focus moves this way and has been replayed on GtkBackend
    /// and WinUIBackend alike, so the mechanism is already known to work on
    /// both. Three steps, spaced so the log is legible.
    ///
    /// `--select-probe`:以計時器移動選取,完全不用滑鼠。
    ///
    /// **它驅動的是「不需要指標」的那一半,而且只有那一半。** 寫入 binding 會走完整條
    /// 框架→backend 的路徑——`@State` → commit → `setSelectedRow(ofTable:to:)` → 畫面上的高亮
    /// ——而那正是一個 backend 可能實作了卻仍然失敗、且與命中測試互相獨立的方向。另一個方向
    /// (點擊變成 binding 的寫入)無法在行程內偽造,留給動作檔。
    ///
    /// 兩個 backend 都用 `DispatchQueue.main.asyncAfter`,而非 `g_timeout_add`:P70 就是這樣驅動
    /// 它的焦點移動,並且在 GtkBackend 與 WinUIBackend 上都重放過,因此這個機制在兩邊都已知可用。
    /// 三個步驟,間隔拉開好讓 log 讀得清楚。
    func driveSelectionIfAsked() {
        guard CommandLine.arguments.contains("--select-probe") else { return }
        P23Diagnostics.write("SELECT PROBE starting")
        let steps: [(Double, () -> Void)] = [
            (1.5, { selectedRow = 2 }),
            (3.0, { selectedRow = 5 }),
            (4.5, { selectedRow = nil }),
            (6.0, { P23Diagnostics.write("SELECT PROBE done") }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated(step)
            }
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
