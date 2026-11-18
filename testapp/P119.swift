import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
#endif
#if os(Android)
    import Android
#endif

// P119 Root widget teardown: a regression guard for 77be6665.
//
// GtkCustomRootWidget had no dispose, so it was freed with its child still
// attached. GTK printed "Finalizing GtkCustomRootWidget ..., but it still has
// children left" and the child kept a parent pointer into freed memory;
// SoftPCB-UI later died in gtk_widget_get_ancestor (2026-11-18).
//
// The app needs no input. It opens and closes a sheet, adds and removes a split
// view (two root widgets), and changes a picker's colour, which reloads a
// display-wide CSS provider. A GLib log writer counts the warning. The verdict
// goes to p119-debug-events.log (SCUI_DEBUG_EVENTS_DIR), stdout and the window.
// With P119_SEQUENCE=1, or the launch argument --sequence for iOS and Android, whose
// apps get no environment variables, the app exits 0 on PASS or SKIP and 1 on FAIL.
//
// The guard watches the warning, not the crash: the access violation depends on
// what reuses the freed memory, and it did not reproduce in 6 runs of the unfixed
// code, while the warning appeared on every removal of a split view.
//
// Only GTK has this widget. Other backends run the same steps and report SKIP.
//
// P119 Root widget 拆除：77be6665 的回歸防護。
//
// GtkCustomRootWidget 沒有 dispose，因此釋放時子元件仍掛在上面。GTK 印出「Finalizing GtkCustomRootWidget ...,
// but it still has children left」，子元件的 parent 指標指向已釋放的記憶體；SoftPCB-UI 後來在 gtk_widget_get_ancestor
// 當機(2026-11-18)。
//
// 這支 app 不需要任何輸入。它開關 sheet、加入並移除分割視圖(兩個 root widget)、改變 picker 的顏色(會重新載入 display
// 範圍的 CSS provider)，並以 GLib log writer 計算這則警告。結果寫到 p119-debug-events.log(SCUI_DEBUG_EVENTS_DIR)、
// stdout 與視窗。設 P119_SEQUENCE=1，或使用給 iOS 與 Android 的啟動參數 --sequence(它們的 app 收不到環境變數)時，
// PASS 或 SKIP 以 0 結束、FAIL 以 1 結束。
//
// 防護看的是警告而不是當機：存取違規取決於誰重複使用了那塊已釋放的記憶體，未修正的程式碼跑 6 次都沒有重現，而警告在每次移除
// 分割視圖時都會出現。
//
// 只有 GTK 有這個 widget。其他 backend 跑同樣的步驟，回報 SKIP。
//
// Build this file as a standalone app target.

enum P119 {
    static let title = "P119 Root widget teardown"
    static let cycles = 20
    static let runsSequence =
        ProcessInfo.processInfo.environment["P119_SEQUENCE"] == "1" || CommandLine.arguments.contains("--sequence")

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p119-debug-events.log")
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

#if canImport(CGtk)
    /// Counts GLib log messages on their way to the default writer.
    /// 在 GLib 訊息送往預設 writer 的途中計數。
    enum P119Log {
        static let probeText = "P119 log writer probe"
        nonisolated(unsafe) static var leftChildren = 0
        nonisolated(unsafe) static var probes = 0

        /// Installed before the backend starts, because GLib allows one writer per
        /// process and it has to see every teardown.
        /// 在 backend 啟動前安裝：GLib 每個行程只允許一個 writer，而它必須看到每一次拆除。
        static func install() {
            g_log_set_writer_func(
                { level, fields, count, data in
                    if let fields {
                        for index in 0..<Int(count) {
                            let field = fields[index]
                            guard let key = field.key, String(cString: key) == "MESSAGE",
                                let value = field.value
                            else { continue }
                            let text = String(cString: value.assumingMemoryBound(to: CChar.self))
                            if text.contains("GtkCustomRootWidget"), text.contains("still has children left") {
                                P119Log.leftChildren += 1
                            }
                            if text == P119Log.probeText {
                                P119Log.probes += 1
                            }
                        }
                    }
                    return g_log_writer_default(level, fields, count, data)
                },
                nil,
                nil
            )
        }

        /// Sends one message through GLib. If the writer never sees it, a count of
        /// zero warnings would mean nothing, so the run fails instead of passing.
        /// 經由 GLib 送出一則訊息。writer 若沒看到它，「零則警告」就毫無意義，因此這次執行判為失敗，而不是通過。
        static func sendProbe() {
            "MESSAGE".withCString { key in
                probeText.withCString { value in
                    var field = GLogField(key: key, value: UnsafeRawPointer(value), length: -1)
                    g_log_structured_array(GLogLevelFlags(rawValue: 1 << 5), &field, 1)
                }
            }
        }
    }
#endif

@main
struct P119App: App {
    init() {
        #if canImport(CGtk)
            P119Log.install()
        #endif
    }

    var body: some Scene {
        WindowGroup(P119.title) {
            P119View()
        }
        .defaultSize(width: 520, height: 420)
    }
}

struct P119View: View {
    @State var cycle = 0
    @State var sheetShown = false
    @State var splitShown = true
    @State var selection: String? = "a"
    @State var verdict = "running"

    var body: some View {
        VStack(spacing: 8) {
            Text(P119.title)
            Text("Cycle \(cycle) of \(P119.cycles): \(verdict)")
            Picker(of: ["a", "b"], selection: $selection)
                .foregroundColor(cycle % 2 == 0 ? Color.red : Color.blue)
            if splitShown {
                NavigationSplitView {
                    Text("Sidebar \(cycle)")
                } detail: {
                    Text("Detail \(cycle)")
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .sheet(isPresented: $sheetShown) {
            Text("Sheet \(cycle)")
                .padding(40)
        }
        .task {
            await run()
        }
    }

    func run() async {
        for step in 1...P119.cycles {
            try? await Task.sleep(nanoseconds: 150_000_000)
            sheetShown.toggle()
            try? await Task.sleep(nanoseconds: 150_000_000)
            splitShown.toggle()
            try? await Task.sleep(nanoseconds: 150_000_000)
            cycle = step
        }

        // A root is freed after the update that removed it, so let the last ones go.
        // root 在移除它的那次更新之後才釋放，所以等最後幾個釋放完。
        sheetShown = false
        splitShown = false
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        var passed = true
        #if canImport(CGtk)
            P119Log.sendProbe()
            let warnings = P119Log.leftChildren
            passed = warnings == 0 && P119Log.probes == 1
            verdict = passed ? "PASS" : "FAIL"
            P119.log(
                "P119 \(verdict): \(warnings) root widgets freed with children left, "
                    + "log writer probes seen \(P119Log.probes) of 1, cycles \(cycle)"
            )
        #else
            verdict = "SKIP"
            P119.log("P119 SKIP: this backend has no GtkCustomRootWidget, cycles \(cycle)")
        #endif

        if P119.runsSequence {
            #if os(Android)
                // exit() runs the static destructors while the HWUI render threads are
                // still using them: SIGABRT, "pthread_mutex_lock called on a destroyed
                // mutex", on every run (2026-11-19). _exit() skips them. stdout reaches
                // logcat through a pipe another thread reads, so give the verdict time.
                // exit() 會執行靜態解構，而 HWUI 繪圖執行緒還在使用它們：每次都 SIGABRT,
                //「pthread_mutex_lock called on a destroyed mutex」(2026-11-19)。_exit() 不執行解構。
                // stdout 經由另一條執行緒讀取的 pipe 才到 logcat，所以留時間讓判定送達。
                try? await Task.sleep(nanoseconds: 500_000_000)
                _exit(passed ? 0 : 1)
            #else
                exit(passed ? 0 : 1)
            #endif
        }
    }
}
