import DebugFeatures
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

#if canImport(WinUI)
    import WinUI
    import WinUIBackend

    /// `--winui-list-probe`: scrolls the list with no mouse, and reports what
    /// the backend realizes and releases.
    ///
    /// **It exists because the mouse is the unreliable part of this machine,
    /// not because reaching the tree is hard.** The GTK half of this app has had
    /// `--gtk-list-probe` since #117 -- it selects, scrolls the adjustment and
    /// counts realized containers from inside the process -- and the WinUI half
    /// had nothing, so every WinUI recycling question needed synthesised input
    /// that has been intermittent all day. Recycling cannot be observed at all
    /// without scrolling, so "no input" meant "no measurement".
    ///
    /// Counts are read with `VisualTreeHelper` against the items panel, which is
    /// the same thing `realizedContainers` means on the GTK side: how many row
    /// containers exist right now, not how many rows the model has.
    ///
    /// `--winui-list-probe`:不用滑鼠就把清單捲起來,並回報 backend 實體化與釋放了什麼。
    ///
    /// **它存在的理由是這台機器上「滑鼠」才是不可靠的那一環,而不是「取得那棵樹」很難。**
    /// 這支 app 的 GTK 那一半自 #117 起就有 `--gtk-list-probe`——它會選取、捲動 adjustment、
    /// 並從行程內部數出已實體化的容器——而 WinUI 那一半什麼都沒有,於是每一個 WinUI 的回收問題
    /// 都得靠合成輸入,而合成輸入整天都時好時壞。**沒有捲動就根本觀察不到回收**,因此「沒有輸入」
    /// 等於「沒有量測」。
    ///
    /// 數量以 `VisualTreeHelper` 對著 items panel 讀取,與 GTK 那側的 `realizedContainers`
    /// 意義相同:此刻存在多少個列容器,而不是 model 有多少列。
    struct P57WinUIProbe: WinUIElementRepresentable {
        typealias WinUIElementType = WinUI.Canvas

        func makeWinUIElement(context: Context) -> WinUI.Canvas {
            let canvas = WinUI.Canvas()
            guard CommandLine.arguments.contains("--winui-list-probe") else { return canvas }
            // 1.2s rather than P69's 0.6s: this one has to wait for the list to
            // have laid out its first screenful of containers, not just for
            // properties to be attached.
            // 用 1.2 秒而非 P69 的 0.6 秒:這一個必須等到清單已經把第一屏的容器排好版,
            // 而不只是等屬性被掛上。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated { P57WinUIProbe.step(0, from: canvas) }
            }
            return canvas
        }

        func updateWinUIElement(_ element: WinUI.Canvas, context: Context) {}

        @MainActor
        static func step(_ phase: Int, from element: WinUI.FrameworkElement) {
            var root: WinUI.DependencyObject = element
            while let parent = VisualTreeHelper.getParent(root) {
                root = parent
            }
            guard let list = findListView(root) else {
                P57Diagnostics.write("WINUI phase=\(phase) listView=NOT FOUND")
                return
            }

            let modelRows = list.items?.count ?? 0
            var realized = 0
            if let panel = list.itemsPanelRoot {
                realized = Int(VisualTreeHelper.getChildrenCount(panel))
            }
            P57Diagnostics.write(
                "WINUI phase=\(phase) modelRows=\(modelRows) realizedContainers=\(realized) "
                    + "selected=\(list.selectedIndex < 0 ? "none" : String(list.selectedIndex)) "
                    + "residentMB=\(P57Memory.residentMegabytes)"
            )

            // **A sweep, not two jumps, and the difference is the whole
            // measurement.** `scrollIntoView(9999)` realizes one screenful at
            // the destination: about a dozen rows are ever prepared, so a
            // release path that frees nothing and one that frees everything
            // both end the run holding a dozen nodes. Walking the list in small
            // steps prepares thousands of rows instead, which is the only
            // arrangement where "released" and "kept" have different costs --
            // at roughly 31 KB a node, `lazyLifetimeBackstopLimit` rows of
            // difference is over a hundred megabytes.
            //
            // **是逐段掃過,而不是跳兩次;而這個差別就是整個量測的關鍵。**
            // `scrollIntoView(9999)` 只會在目的地實體化一屏:全程被準備的列大約十幾個,於是
            // 「完全沒釋放」與「全部釋放」兩種情況,在執行結束時都握著十幾個節點。改以小步走過清單,
            // 會準備數以千計的列——那是唯一一種「有釋放」與「沒釋放」代價不同的安排:以每個節點
            // 約 31 KB 計,`lazyLifetimeBackstopLimit` 列的差距超過一百 MB。
            let target = phase * P57WinUIProbe.step
            if phase > 0, target < modelRows, phase <= P57WinUIProbe.steps {
                scroll(list, to: min(target, modelRows - 1))
            } else if phase > P57WinUIProbe.steps {
                // Back to the top, then one last reading: a release path that
                // only works while scrolling down would pass everything above.
                // 回到頂端,再讀最後一次:一條只在向下捲時有效的釋放路徑,會通過上面所有的檢查。
                if phase == P57WinUIProbe.steps + 1 {
                    scroll(list, to: 0)
                } else {
                    P57Diagnostics.write("WINUI LIST PROBE DONE")
                    return
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                MainActor.assumeIsolated { P57WinUIProbe.step(phase + 1, from: element) }
            }
        }

        /// How far each step moves, and how many steps. 20 x 250 walks 5,000
        /// rows -- past the 4,000-row backstop, so a run that releases nothing
        /// hits the cap and a run that releases correctly never approaches it.
        /// 每一步移動多遠、共走幾步。20 x 250 會走過 5,000 列——超過 4,000 列的兜底上限,
        /// 因此「完全不釋放」的執行會撞到那個上限,而「正確釋放」的執行永遠不會接近它。
        static let step = 20
        static let steps = 250

        @MainActor
        static func scroll(_ list: WinUI.ListView, to index: Int) {
            guard let items = list.items, index >= 0, index < items.count else { return }
            do {
                try list.scrollIntoView(items[index])
                P57Diagnostics.write("WINUI scrollIntoView index=\(index)")
            } catch {
                P57Diagnostics.write("WINUI scrollIntoView index=\(index) FAILED \(error)")
            }
        }

        @MainActor
        static func findListView(_ node: WinUI.DependencyObject) -> WinUI.ListView? {
            if let list = node as? WinUI.ListView { return list }
            let count = VisualTreeHelper.getChildrenCount(node)
            for index in 0..<count {
                guard let child = VisualTreeHelper.getChild(node, index) else { continue }
                if let found = findListView(child) { return found }
            }
            return nil
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
// The two in-process probes, which need no mouse and no action file. Both walk
// the list and report what the backend realized; neither renders anything.
//
//     ... -- -rows 10000 --gtk-list-probe --debug      GTK (since #117)
//     ... -- -rows 10000 --winui-list-probe --debug    WinUI (since #117 row
//                                                      lifetimes, 2026-09-16)
//
// `SCUI_WINUI_LAZY_TRACE=1` adds one stdout line per row prepared or recycled,
// and `SCUI_WINUI_NO_LAZY_RELEASE=1` is the control group: the conformance stays
// and the release callback is withheld. See `WinUIBackend+LazyListRows.swift`.
//
// 兩支行程內探針,不需要滑鼠、也不需要動作檔。兩者都會走過清單並回報 backend 實體化了什麼;
// 兩者都不算繪任何東西。
//
//     ... -- -rows 10000 --gtk-list-probe --debug      GTK(自 #117 起)
//     ... -- -rows 10000 --winui-list-probe --debug    WinUI(自 2026-09-16 的列生命週期起)
//
// `SCUI_WINUI_LAZY_TRACE=1` 會為每一列的準備或回收在 stdout 加一行;
// `SCUI_WINUI_NO_LAZY_RELEASE=1` 則是對照組:保留 conformance、扣住釋放回呼。
// 見 `WinUIBackend+LazyListRows.swift`。
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

    /// Bumped twice a second under `--debug`, purely so the readouts below are
    /// LIVE.
    ///
    /// **A `Text` shows whatever the last render put there, and scrolling
    /// changes no state.** So "rows built / held" would sit at its launch value
    /// through an entire traversal and a capture of it would be a capture of
    /// nothing -- indistinguishable from a backend that built one row and
    /// stopped. The first attempt at this was a click on "Select last" at the
    /// end of the action file to force a render; on Android that click did not
    /// land, and the stale readout then read as "the list was never scrolled".
    /// A ticker removes the dependency on any input arriving at all.
    ///
    /// Only under `--debug`: a release build never starts the timer.
    ///
    /// 在 `--debug` 下每秒遞增兩次,純粹是為了讓下方那些讀數是**活的**。
    ///
    /// **一個 `Text` 顯示的是最後一次算繪所放進去的東西,而捲動不改變任何狀態。** 因此
    /// 「rows built / held」會在整趟走訪期間停在它的啟動值,而它的擷圖等於什麼都沒拍到
    /// ——與「一個只建了一列就停住的 backend」無從分辨。第一次的做法是在動作檔結尾點一下
    /// 「Select last」來強迫重繪;而在 Android 上那次點擊沒有落下,於是那個過期讀數讀起來就成了
    /// 「這份清單從未被捲動過」。一個計時器把「必須有輸入抵達」這個依賴整個移除。
    ///
    /// 只在 `--debug` 下:release 建置永遠不會啟動這個計時器。
    @State var tick = 0

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
            // The OTHER half of #117, and it is a separate question from the
            // line above. `LazyListRows` asks whether rows arrive one at a time;
            // this asks whether the backend says so when one LEAVES. A backend
            // answering yes above and NO here builds rows on demand and never
            // drops them, which is bounded only by `List.swift`'s backstop cache
            // and looks identical on screen.
            //
            // #117 的**另一半**,而它與上面那一行是不同的問題。`LazyListRows` 問的是「列是不是一次
            // 來一個」;這一行問的是「列**離場**時 backend 有沒有說」。上面答 yes、這裡答 NO 的
            // backend,會按需建列而從不丟棄,其上限只有 `List.swift` 的兜底快取——而它在畫面上
            // 看起來一模一樣。
            Text(
                "row release reported: "
                    + "\(backend is any BackendFeatures.LazyListRowLifetimes ? "yes" : "NO")"
            )
            // **The conformance above is a claim about a TYPE; this is the
            // callback arriving.** Android has compiled a conformance and taken
            // the other path before, which is why the line above asks the
            // backend rather than the file list -- and the same gap exists one
            // level further in: a backend can conform and never call the
            // handler, and the list looks and scrolls identically.
            //
            // Visit four hundred rows and read this. A backend that reports
            // releases settles near the size of the visible window; one that
            // does not climbs towards `lazyLifetimeBackstopLimit`, which is
            // 4000, and the only symptom before that is memory.
            //
            // **上面那行 conformance 是關於一個「型別」的主張;這一行是「那個回呼真的抵達了」。**
            // Android 曾經把一個 conformance 編了進去、然後走了另一條路,而那正是上面那行要去問
            // backend、而不是去看有哪些檔案的理由——同樣的缺口在再往裡一層仍然存在:一個 backend
            // 可以 conform 卻從不呼叫那個 handler,而那個清單看起來與捲起來都一模一樣。
            //
            // 走過四百列再讀這一行。會回報釋放的 backend 會穩定在可見視窗大小附近;不會回報的則會
            // 朝 `lazyLifetimeBackstopLimit`(4000)爬上去,而在那之前唯一的症狀是記憶體。
            Text(
                "rows built / held by the framework: "
                    + "\(DebugFeatures.builtLazyListRows) / \(DebugFeatures.liveLazyListRows)"
                    // The tick is READ here, not just bumped. A body that never
                    // mentions it would not re-render when it changes, and the
                    // ticker would run with nothing to show for it.
                    // 這裡是**讀**那個 tick,不只是遞增它。一個從不提到它的 body 不會因為它改變而重繪,
                    // 而那個計時器就會白跑。
                    + (tick >= 0 ? "" : "?")
            )
            // Zero-sized, present only so the WinUI probe has a real element to
            // walk the tree from. It reads and scrolls; it does not render.
            // 尺寸為零,存在的唯一目的是讓 WinUI 探針有一個真正的元素可據以走訪那棵樹。
            // 它只負責讀取與捲動,不負責算繪。
            #if canImport(WinUI)
                P57WinUIProbe()
                    .frame(width: 0, height: 0)
            #endif

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
        .onAppear {
            guard P57Diagnostics.isEnabled else { return }
            func step() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated {
                        tick += 1
                        step()
                    }
                }
            }
            step()
        }
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
