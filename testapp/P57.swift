import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
    import GtkCHelpers

    enum P57GtkProbe {
        nonisolated(unsafe) static var phase = 0
        nonisolated(unsafe) static var didStart = false

        static func start() {
            guard CommandLine.arguments.contains("--gtk-list-probe"), !didStart else { return }
            didStart = true
            _ = g_timeout_add(2000, { _ in
                let windows = gtk_window_get_toplevels()
                for index in 0..<g_list_model_get_n_items(windows) {
                    guard let object = g_list_model_get_item(windows, index) else { continue }
                    let root = object.assumingMemoryBound(to: GtkWidget.self)
                    P57GtkProbe.inspect(root)
                    let commands = [2: "Clear", 3: "Update rows", 4: "Toggle count", 5: "Toggle count"]
                    if let command = commands[P57GtkProbe.phase] {
                        P57Diagnostics.write("GTK activate \(command)=\(P57GtkProbe.activate(command, in: root))")
                    }
                    g_object_unref(object)
                }
                P57GtkProbe.phase += 1
                return P57GtkProbe.phase < 7 ? 1 : 0
            }, nil)
        }

        static func inspect(_ widget: UnsafeMutablePointer<GtkWidget>) {
            if String(cString: gtk_widget_get_css_name(widget)) == "listview",
                let model = gtk_list_view_get_model(OpaquePointer(widget))
            {
                var realized = 0
                var row = gtk_widget_get_first_child(widget)
                while let current = row {
                    realized += 1
                    row = gtk_widget_get_next_sibling(current)
                }
                let count = g_list_model_get_n_items(model)
                let selected = gtk_single_selection_get_selected(model)
                P57Diagnostics.write(
                    "GTK phase=\(phase) modelRows=\(count) realizedContainers=\(realized) "
                    + "selected=\(selected == GTK_INVALID_LIST_POSITION ? "none" : String(selected)) "
                    + "allocated=\(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget)) "
                    + "residentMB=\(P57Memory.residentMegabytes)"
                )
                let labels = texts(in: widget)
                P57Diagnostics.write("GTK phase=\(phase) first=\(labels.first ?? "none") last=\(labels.last ?? "none")")
                if phase == 0, count > 0 {
                    gtk_single_selection_set_selected(model, count - 1)
                }
                if phase == 1 {
                    var ancestor = gtk_widget_get_parent(widget)
                    while let parent = ancestor {
                        if String(cString: gtk_widget_get_css_name(parent)) == "scrolledwindow" {
                            let adjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(parent))
                            gtk_adjustment_set_value(
                                adjustment,
                                gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment)
                            )
                            break
                        }
                        ancestor = gtk_widget_get_parent(parent)
                    }
                }
                return
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                inspect(current)
                child = gtk_widget_get_next_sibling(current)
            }
        }

        static func texts(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
            if String(cString: gtk_widget_get_css_name(widget)) == "label" {
                return [String(cString: gtk_label_get_text(wrapped_gtk_widget_as_label(widget)))]
            }
            var result: [String] = []
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                result += texts(in: current)
                child = gtk_widget_get_next_sibling(current)
            }
            return result
        }

        static func activate(_ label: String, in widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
            if String(cString: gtk_widget_get_css_name(widget)) == "button",
                texts(in: widget).contains(label)
            {
                return gtk_widget_activate(widget) != 0
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                if activate(label, in: current) { return true }
                child = gtk_widget_get_next_sibling(current)
            }
            return false
        }
    }
#endif

#if os(Windows)
    import WinSDK
#endif

// P57: how expensive is an eager List, and at what size does it stop being
// usable?
//
// The number was checked, not guessed. `ls testapp` gives P50..P56, `git ls-files`
// has no P57, and nothing under matrix_coverage or testapp/plan mentions the name.
//
// **This is the baseline for #117, and it exists before the work rather than
// after it.** `List` builds every row up front -- `Views/List.swift:170` is
// `(0..<rowCount).map(rowContent)`, one `AnyViewGraphNode` per row, one layout
// pass per row, and `setItems(ofSelectableListView:to:withRowHeights:)` hands the
// backend an array of all of them. Virtualising it means changing that contract,
// and "it is faster now" is not a claim anyone can check without a number from
// before.
//
// WHAT IT MEASURES, and it is not the clock. **The window's own height**, which
// on this framework is a direct reading of how eager the list is:
//
//     rows=10    window 1280 x 1958 px
//     rows=50    window 1280 x 9306 px
//     rows=100   window  640 x 9253 px
//     rows=200   window capture FAILED, fell back to the whole screen
//     rows=400   window capture FAILED
//
// `List` does not scroll itself. `AppKitBackend.createSelectableListView` builds
// an `NSDisabledScrollView` with `hasVerticalScroller = false`, and the
// framework lays the table out at its full content height -- so N rows produce a
// window proportional to N, and somewhere past a hundred it exceeds the display
// and can no longer even be photographed.
//
// That is the baseline #117 has to change, and it is one number rather than a
// timing curve. A wall-clock measurement here would have been one sample of one
// path, which is what mistakes_prevention says not to conclude from; the window
// height is deterministic.
//
// 它量的是什麼,而那不是時間。**視窗自身的高度**——在這個框架上,那是「這個清單有多 eager」的直接讀數:
//
//     rows=10    視窗 1280 x 1958 像素
//     rows=50    視窗 1280 x 9306 像素
//     rows=100   視窗  640 x 9253 像素
//     rows=200   視窗擷取**失敗**,退回抓整個螢幕
//     rows=400   視窗擷取失敗
//
// `List` 自己不捲動。`AppKitBackend.createSelectableListView` 建立的是一個
// `hasVerticalScroller = false` 的 `NSDisabledScrollView`,而框架把那個 table 排版成它的完整內容高度
// ——因此 N 列會產出一個與 N 成正比的視窗,而在超過一百列的某處,它會大過顯示器、連拍都拍不到。
//
// 那正是 #117 必須改變的基準線,而它是**一個數字**,不是一條計時曲線。此處的實際時間量測會是單一路徑的
// 單一樣本,而那正是 mistakes_prevention 明說不可據以下結論的東西;視窗高度則是確定的。
//
// The row count is a launch argument, so the same binary produces every point on
// that curve and the build is not a variable.
//
//     zsh testapp/test.zsh P57 --no-build -- -rows 5000
//
// P57:一個 eager 的 List 有多貴,而在什麼規模下它會變得不堪用?
//
// 這個編號是查過的,不是猜的。`ls testapp` 給出 P50..P56,`git ls-files` 中沒有 P57,而
// matrix_coverage 與 testapp/plan 底下都沒有提到這個名字。
//
// **這是 #117 的基準線,而它存在於那項工作之前、而不是之後。** `List` 會事先建好每一列——
// `Views/List.swift:170` 就是 `(0..<rowCount).map(rowContent)`,每列一個 `AnyViewGraphNode`、
// 每列一次版面計算,而 `setItems(ofSelectableListView:to:withRowHeights:)` 交給 backend 的是它們
// 全部的陣列。虛擬化它意味著改變那個契約,而「現在比較快了」若沒有一個「之前」的數字,沒有人檢查得了。
//
// 它量的是什麼。從這支 app 決定建構它的 body,到第一次算繪完成為止的實際時間,對應命令列上給定的列數。
// 這不是對該 toolkit 的效能評測:它是單一路徑的單一樣本,而「單一樣本」正是 mistakes_prevention 明說
// 不可據以下結論的東西。它真正有用的地方在於**形狀**——同一台機器、同一分鐘之內,100 列對 5,000 列
// 對 20,000 列;五十倍的差距不會是雜訊。
//
// 列數是啟動引數,因此同一個二進位檔就能產出那條曲線上的每一個點,建置本身不會成為變數。

/// This process's resident memory, in megabytes.
///
/// **In the app, because on iOS there is no `ps`.** The macOS numbers for #117
/// came from `ps -o rss=`, and the simulator gives no equivalent for the app
/// inside it -- so the claim "ten thousand rows costs what an empty list costs"
/// would have been unverifiable on the platform that cares most about it.
///
/// `MACH_TASK_BASIC_INFO.resident_size` is what `ps` reads, so the two agree.
///
/// 這個行程的常駐記憶體，單位為 MB。
///
/// **放在 app 裡面，因為 iOS 上沒有 `ps`。** #117 的 macOS 數字來自 `ps -o rss=`，而模擬器對它裡面的
/// app 並不提供對應物——因此「一萬列的成本等於一份空清單」這個主張，在最在意它的那個平台上會變成
/// 無法驗證。
///
/// `MACH_TASK_BASIC_INFO.resident_size` 正是 `ps` 所讀的東西，因此兩者一致。
enum P57Memory {
    static var residentMegabytes: Int {
        #if canImport(Darwin)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
                }
            }
            guard result == KERN_SUCCESS else { return -1 }
            return Int(info.resident_size) / 1_048_576
        #elseif os(Windows)
            // The Windows equivalent of the mach reading: `WorkingSetSize` from
            // `GetProcessMemoryInfo` is the resident set -- the pages actually
            // in physical memory -- which is what
            // `MACH_TASK_BASIC_INFO.resident_size` is on macOS and what the
            // second field of `/proc/self/statm` is below. All three branches
            // therefore mean the same thing, which is what lets #117's
            // cross-platform table compare like with like.
            //
            // Task Manager's "Memory" column is this same working set, so a run
            // can be sanity-checked against it by eye.
            //
            // mach 讀數在 Windows 上的對應物:`GetProcessMemoryInfo` 的 `WorkingSetSize` 就是
            // resident set——實際位於實體記憶體中的分頁——而那正是 macOS 上的
            // `MACH_TASK_BASIC_INFO.resident_size`,也正是下方 `/proc/self/statm` 的第二個欄位。
            // 因此三個分支意義相同,而那正是 #117 的跨平台表格得以「比較同一種東西」的前提。
            //
            // 工作管理員的「記憶體」欄就是這同一個工作集,因此一次執行可以用肉眼對著它做合理性檢查。
            //
            // `K32GetProcessMemoryInfo`, not `GetProcessMemoryInfo`. The latter
            // is a psapi.h macro (`#define GetProcessMemoryInfo
            // K32GetProcessMemoryInfo` at PSAPI_VERSION >= 2), and Swift's
            // WinSDK overlay exposes the real kernel32-exported symbol but not
            // the macro alias -- "cannot find 'GetProcessMemoryInfo' in scope",
            // while the `PROCESS_MEMORY_COUNTERS` struct beside it resolves
            // fine. Checked by building rather than assumed.
            // 用 `K32GetProcessMemoryInfo`,不是 `GetProcessMemoryInfo`。後者是 psapi.h 的巨集
            // (在 PSAPI_VERSION >= 2 時 `#define GetProcessMemoryInfo K32GetProcessMemoryInfo`),
            // 而 Swift 的 WinSDK overlay 曝露的是 kernel32 真正匯出的那個符號、而非巨集別名——
            // 「cannot find 'GetProcessMemoryInfo' in scope」,而它旁邊的 `PROCESS_MEMORY_COUNTERS`
            // struct 則正常解析。以建置查證,非臆測。
            var counters = PROCESS_MEMORY_COUNTERS()
            counters.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
            guard
                K32GetProcessMemoryInfo(
                    GetCurrentProcess(),
                    &counters,
                    counters.cb
                )
            else { return -1 }
            return Int(counters.WorkingSetSize) / 1_048_576
        #else
            // `/proc/self/statm`: total and resident, in PAGES.
            //
            // The second field, not the first. The first is virtual size, which
            // on a 64-bit Android process is tens of gigabytes of address space
            // and has nothing to do with what the device is holding -- a number
            // that looks alarming and means nothing.
            //
            // `/proc/self/statm`:總量與常駐量，單位是**頁**。
            //
            // 取第二個欄位，不是第一個。第一個是虛擬大小，在一個 64 位元的 Android 行程上那是數十 GB
            // 的位址空間，與「這台裝置實際持有多少」毫無關係——一個看起來嚇人、而毫無意義的數字。
            guard let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
                let residentPages = statm.split(separator: " ").dropFirst().first,
                let pages = Int(residentPages)
            else { return -1 }
            return pages * 4096 / 1_048_576
        #endif
    }
}

enum P57Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P57] \(message)")

        // **This app used to print and nothing else, and that cost a finding.**
        // A threshold sweep was written against `p57-debug-events.log`, which
        // P57 never created; every scenario came back RENDERED because the
        // absence of the file was read as the absence of a problem. The file is
        // written now, following the same `SCUI_DEBUG_EVENTS_DIR` contract as
        // P10 and the rest -- documented in testapp/test_support/test_common.zsh.
        //
        // Printing alone is also unreadable on macOS in practice: the process
        // is a GUI app that does not exit, so a pipe's buffer is never flushed
        // and `./P57 --debug | grep` returns nothing at all.
        //
        // **這支 app 過去只有 print、沒有別的,而那讓一次量測付出了代價。** 有一份門檻掃描是對著
        // `p57-debug-events.log` 寫的,而 P57 從來不曾建立那個檔案;於是每一個情境都回報 RENDERED
        // ——「檔案不存在」被讀成了「沒有問題」。現在它會寫出該檔案,沿用與 P10 及其餘各支相同的
        // `SCUI_DEBUG_EVENTS_DIR` 約定,該約定記載於 testapp/test_support/test_common.zsh。
        //
        // 只靠 print 在 macOS 上實務上也讀不到:這個行程是一支不會結束的 GUI app,因此管線的緩衝區
        // 永遠不會被沖出,`./P57 --debug | grep` 什麼也拿不到。
        guard let data = "P57 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p57-debug-events.log")
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
        write("RENDER COMPLETE -- P57 ready")
    }
}

/// The row count, from `-rows N`, defaulting to something a phone survives.
///
/// 500 rather than 5,000 by default. This app is run by the sweep as well as by
/// hand, and a default that takes a minute to start would make every unrelated
/// run slower for a measurement nobody asked for on that pass.
///
/// 列數,來自 `-rows N`,預設為一個手機撐得住的數字。
///
/// 預設 500 而非 5,000。這支 app 除了手動執行之外也會被 sweep 掃到,而一個「啟動要花一分鐘」的預設值
/// 會讓每一次無關的執行都變慢,只為了那一輪根本沒有人要求的量測。
enum P57Configuration {
    static let rowCount: Int = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-rows"),
            index + 1 < arguments.count,
            let value = Int(arguments[index + 1]),
            value > 0
        else { return 500 }
        return value
    }()
}

@main
@HotReloadable
struct P57ListCostApp: App {
    var body: some Scene {
        WindowGroup("P57 list cost") {
            #hotReloadable {
                P57RootView()
            }
        }
        .defaultSize(width: 640, height: 700)
    }
}

struct P57RootView: View {
    @Environment(\.backend) var backend

    /// Stamped when the first body runs, read when the first render completes.
    ///
    /// A `let` on the view would be re-stamped every time the view is
    /// reconstructed, which for a view that rebuilds on state change is not
    /// "when the app started". A static, assigned once, is the thing that keeps
    /// meaning what it says.
    ///
    /// 在第一次執行 body 時蓋下,在第一次算繪完成時讀取。
    ///
    /// 若寫成 view 上的 `let`,它會在每次該 view 被重新建構時重新蓋一次,而對一個「狀態改變就重建」的
    /// view 來說,那並不是「app 啟動的時刻」。使用一個只被指派一次的 static,才是那個「說什麼就一直是
    /// 什麼」的東西。
    nonisolated(unsafe) static var startedAt: Date?

    @State var renderedIn = "(measuring)"

    /// Every `List` initialiser here requires a selection binding; there is no
    /// selection-free spelling. Held rather than ignored, because a `.constant`
    /// would make the list unselectable and this app is measuring the ordinary
    /// path, not a special case of it.
    /// 此處 `List` 的每一個初始化式都要求一個 selection binding;沒有「不含選取」的寫法。
    /// 選擇持有它而非忽略,因為 `.constant` 會讓這個清單無法被選取,而這支 app 量的是**尋常**的路徑,
    /// 不是它的某個特例。
    @State var selection: Int?
    @State var rowCount = P57Configuration.rowCount
    @State var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P57: List cost, lazy where the backend takes rows one at a time")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("rows: \(rowCount)")
            Text("selection: \(selection.map(String.init) ?? "none")")
            HStack {
                Button("Clear") { selection = nil }
                Button("Select last") { selection = rowCount > 0 ? rowCount - 1 : nil }
                Button("Update rows") { revision += 1 }
                Button("Toggle count") {
                    rowCount = rowCount == P57Configuration.rowCount ? 1 : P57Configuration.rowCount
                    selection = nil
                }
            }
            // Kept, but the window's height is the measurement. This line is a
            // sanity check that the app got as far as onAppear at all.
            // 保留,但真正的量測是視窗的高度。這一行只是用來確認這支 app 至少走到了 onAppear。
            Text("first render: \(renderedIn)")
            Text("resident memory: \(P57Memory.residentMegabytes) MB")
            // Whether the backend takes rows one at a time, asked of the
            // backend rather than assumed from which files exist.
            //
            // Android compiled `BackendFeatures.LazyListRows` and then took the
            // eager path anyway, and the only reason that was caught is that the
            // memory did not move. A line on screen makes the question visible
            // on every platform at once.
            //
            // 這個 backend 是不是「一次收一列」——去問 backend，而不是從「有哪些檔案存在」去假設。
            //
            // Android 把 `BackendFeatures.LazyListRows` 編了進去，然後照樣走了 eager 路徑;而那件事
            // 之所以被抓到，唯一的原因是記憶體沒有動。畫面上的一行，讓這個問題在每個平台上同時可見。
            Text("lazy rows: \(backend is any BackendFeatures.LazyListRows ? "yes" : "NO")")
            // A control. `ScrollingLists` landed on all five backends weeks ago
            // and is checked the same way in the same file, so if it also reads
            // NO here the problem is the runtime cast, not this conformance.
            // 一個對照組。`ScrollingLists` 幾週前就在五個 backend 上落地，而它在同一個檔案裡以同樣的
            // 方式被檢查;因此若它在此處也讀作 NO，那問題出在執行期的轉型，而不在這個 conformance。
            Text("control -- scrolling lists: \(backend is any BackendFeatures.ScrollingLists ? "yes" : "NO")")

            // ~~"Baseline for #117. List builds every row up front"~~ -- it did,
            // until 2026-09-11. Struck through rather than replaced, for the
            // reason P34 records: a stale claim RENDERED ON SCREEN is believed
            // over the source by anyone who does not go and check.
            // ~~「這是 #117 的基準線。List 會事先建好每一列」~~——它確實如此，直到 2026-09-11。
            // 此處保留刪除線而非直接取代，理由與 P34 所記載的相同:一個**被算繪到畫面上的**過期主張，
            // 在不去查證的人眼中會勝過原始碼。
            Text(
                "#117 phase 3: on a backend that takes rows one at a time, List builds only the "
                    + "rows that are shown. Run the same binary at several row counts -- the "
                    + "shape matters, one sample does not."
            )
            Text(
                "#117 phase 3:在「一次收一列」的 backend 上,List 只會建出被顯示的那些列。以不同的列數"
                    + "執行同一個二進位檔——重要的是形狀,單一樣本不算數。"
            )
            Text(
                "Measured on AppKit: 10,000 rows was 423 MB and is 104 MB, against a 102 MB "
                    + "one-row baseline. Scrolling the whole list settles at 134 MB rather than "
                    + "climbing: the row views are recycled now."
            )

            List(Array(0..<rowCount), id: \.self, selection: $selection) {
                index in
                Text("row \(index) revision \(revision)")
            }
        }
        .padding(16)
        .onChange(of: selection) {
            P57Diagnostics.write("selection=\(selection.map(String.init) ?? "none") rows=\(rowCount) revision=\(revision)")
        }
        .onChange(of: rowCount) {
            P57Diagnostics.write("rows=\(rowCount) revision=\(revision)")
        }
        .onChange(of: revision) {
            P57Diagnostics.write("revision=\(revision) rows=\(rowCount)")
        }
        .onAppear {
            // `onAppear` fires after the first render, which is exactly the
            // point being measured -- the eager build has already happened by
            // the time this runs.
            // `onAppear` 在第一次算繪之後觸發,而那正是此處要量的那一點——當它執行時,那次 eager 的
            // 建構已經發生過了。
            let started = Self.startedAt ?? Date()
            let seconds = Date().timeIntervalSince(started)
            renderedIn = String(format: "%.3f s", seconds)
            P57Diagnostics.write(
                "rows=\(rowCount) firstRender=\(String(format: "%.3f", seconds))s residentMB=\(P57Memory.residentMegabytes)"
            )
            P57Diagnostics.renderComplete()
            #if canImport(CGtk)
                P57GtkProbe.start()
            #endif
        }
    }

    init() {
        if Self.startedAt == nil {
            Self.startedAt = Date()
        }
    }
}
