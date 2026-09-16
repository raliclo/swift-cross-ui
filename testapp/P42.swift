import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
    import GtkCHelpers

    /// Asks GTK itself what scale it thinks the window is at, by two different
    /// calls (#80).
    ///
    /// **The two disagree, and which one the framework reads is the whole
    /// question.** `gtk_widget_get_scale_factor` is an INTEGER by design -- the
    /// buffer scale GTK rendered at -- so at 125% on Windows it can only say 1,
    /// and that is the number `computeWindowEnvironment` currently puts into
    /// `windowScaleFactor`. `gdk_surface_get_scale` arrived in GTK 4.12 and
    /// returns a DOUBLE. GTK here is 4.22, so it exists; what it returns on
    /// Windows at a fractional scale is the thing nobody has measured.
    ///
    /// Measured before changing anything, because the two possible answers need
    /// opposite work: 1.25 means the framework is reading the wrong call, and
    /// 1.0 means GDK does not carry the display scale on this platform at all
    /// and the answer is a Win32 one.
    ///
    /// 用兩個不同的呼叫,去問 GTK 自己認為這個視窗的比例是多少(#80)。
    ///
    /// **兩者並不一致,而框架讀的是哪一個,正是整個問題所在。**
    /// `gtk_widget_get_scale_factor` 依設計是**整數**——那是 GTK 實際繪製所用的 buffer scale——
    /// 因此在 Windows 的 125% 下它只能回答 1,而那正是 `computeWindowEnvironment` 目前放進
    /// `windowScaleFactor` 的數字。`gdk_surface_get_scale` 是 GTK 4.12 才有的,回傳**倍精度小數**;
    /// 此處的 GTK 是 4.22,所以它存在——**而它在 Windows 的小數縮放下回傳什麼,沒有人量過。**
    ///
    /// 在動任何程式碼之前先量,因為兩種可能的答案需要相反的工作:1.25 代表框架讀錯了呼叫;
    /// 1.0 則代表 GDK 在這個平台上根本不攜帶顯示縮放,答案得走 Win32。
    enum P42GtkProbe {
        nonisolated(unsafe) static var didStart = false

        static func start() {
            guard CommandLine.arguments.contains("--scale-probe"), !didStart else { return }
            didStart = true
            // On a timer rather than once: the point of #80 is what happens
            // when the scale CHANGES, so a single reading at startup would
            // answer only half of it.
            // 用計時器而非只讀一次:#80 問的是**縮放改變時**會發生什麼,因此只在啟動時讀一次,
            // 只回答得了一半。
            _ = g_timeout_add(
                2000,
                { _ in
                    P42GtkProbe.report()
                    return 1
                },
                nil
            )
        }

        static func report() {
            let toplevels = gtk_window_get_toplevels()
            for index in 0..<g_list_model_get_n_items(toplevels) {
                guard let object = g_list_model_get_item(toplevels, index) else { continue }
                let widget = object.assumingMemoryBound(to: GtkWidget.self)
                let widgetScale = gtk_widget_get_scale_factor(widget)
                var surfaceScale = -1.0
                var surfaceScaleFactor = -1
                // gtk_widget_get_native rather than a cast: GtkNative is an
                // interface, and GtkWindow implements it, but only the getter
                // states that in a way Swift can type-check.
                // 用 gtk_widget_get_native 而非強制轉型:GtkNative 是 interface,GtkWindow 有實作它,
                // 但只有這個 getter 以 Swift 能做型別檢查的方式陳述此事。
                if let native = gtk_widget_get_native(widget),
                    let surface = gtk_native_get_surface(native)
                {
                    surfaceScale = gdk_surface_get_scale(surface)
                    surfaceScaleFactor = Int(gdk_surface_get_scale_factor(surface))
                }
                P42Diagnostics.write(
                    "GTK widget_scale_factor=\(widgetScale) "
                        + "surface_scale=\(surfaceScale) "
                        + "surface_scale_factor=\(surfaceScaleFactor) "
                        + "display_scale=\(scui_window_display_scale(widget))"
                )
                if let diagnostics = scui_window_scale_diagnostics(widget) {
                    P42Diagnostics.write("WIN32 \(String(cString: diagnostics))")
                    g_free(diagnostics)
                }
                g_object_unref(object)
            }
        }
    }
#endif

// P42: does the window scale factor follow a display-scale change while the app
// is running?
//
// The value itself has been correct at window creation on both desktop backends
// since #40. What was never implemented was the *notification*, so a window that
// moved to a display of a different scale -- or whose display scale changed
// under it -- kept whatever it started with. `Image` re-renders on this value,
// so it stayed rendered for the old scale until something else forced a
// recompute.
//
// The point of this app is that a wrong answer here is invisible. A window
// showing "2.0" tells you nothing about whether it would still say 2.0 after a
// change, so the current value alone cannot be the test. What it shows instead
// is the **sequence**: every distinct value seen, in order, with a count. One
// entry after a scale change means the notification did not fire. Two means it
// did.
//
// How to drive it, on Windows:
//   1. launch, note the first value
//   2. Settings > System > Display > Scale, pick a different percentage
//   3. read the line again without touching the window
//
// P42：app 執行期間，視窗的 scale factor 會不會跟隨顯示器縮放的改變？
//
// 自 #40 起，該值本身在兩個桌面 backend 上於視窗建立時都是正確的。從未實作的是**通知**，因此
// 一個移動到不同縮放顯示器上的視窗——或其顯示器縮放在它底下被改變的視窗——會一直保留最初的值。
// `Image` 會依此值重新算繪，所以它會維持為舊縮放的樣子，直到有其他事件強迫重算為止。
//
// 本 app 的重點在於：此處的錯誤答案是看不見的。一個顯示「2.0」的視窗，並不能告訴你它在縮放改變
// 之後是否仍會顯示 2.0，因此「當前值」本身無法作為測試。它改為顯示**序列**：所有看過的相異值，
// 依序排列並附上次數。縮放改變後仍只有一項，代表通知沒有觸發；有兩項，代表觸發了。
//
// Windows 上的操作方式：
//   1. 啟動，記下第一個值
//   2. 設定 > 系統 > 顯示器 > 縮放，選一個不同的百分比
//   3. 不要碰視窗，再讀一次那一行
//
// Build this file as a standalone app target.

enum P42Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P42] \(message)")

        guard let data = "P42 \(Date()) \(message)\n".data(using: .utf8) else { return }
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p42-debug-events.log")
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
        write("RENDER COMPLETE -- P42 ready for scale-factor change checks")
    }
}

/// Every distinct scale factor seen, in the order they arrived.
///
/// Deliberately not `@State`. This is recorded from inside `body`, and writing
/// state during a layout pass feeds back into the layout that is producing it --
/// the mistake P16's probe comment records at length. A plain type keeps the
/// record without joining the view graph.
///
/// 所有看過的相異 scale factor，依抵達順序排列。
///
/// 刻意不使用 `@State`。此處是在 `body` 之內記錄的，而在版面計算過程中寫入 state 會回饋到正在
/// 產生它的那次版面計算——那正是 P16 探針註解中詳述過的錯誤。使用普通型別即可保留紀錄，而不必
/// 加入 view graph。
enum P42History {
    nonisolated(unsafe) private static var seen: [(value: Double, count: Int)] = []

    static func record(_ value: Double) {
        if let last = seen.last, last.value == value {
            seen[seen.count - 1].count += 1
            return
        }
        seen.append((value, 1))
        P42Diagnostics.write("scale factor -> \(value) (change \(seen.count))")
    }

    static var summary: String {
        guard !seen.isEmpty else { return "nothing recorded yet" }
        return seen.map { "\($0.value) x\($0.count)" }.joined(separator: "  ->  ")
    }

    static var changeCount: Int {
        max(0, seen.count - 1)
    }
}

@main
@HotReloadable
struct P42ScaleFactorApp: App {
    var body: some Scene {
        WindowGroup("P42 window scale factor") {
            #hotReloadable {
                P42RootView()
            }
        }
        .defaultSize(width: 720, height: 360)
    }
}

struct P42RootView: View {
    @Environment(\.windowScaleFactor) var scaleFactor

    var body: some View {
        // Inside the builder, not before an explicit `return`. Written the other
        // way -- `let _ = record(...)` then `return VStack { ... }` -- the body
        // stops being a result-builder context, and the measured consequence was
        // that `.onAppear` never fired: the scale factor was recorded but
        // `RENDER COMPLETE` was not, on runs of 8 and 14 seconds. That marker is
        // what `test_common.zsh` waits for, so the app would have looked hung.
        //
        // 置於 builder 之內，而非顯式 `return` 之前。寫成另一種形式——先 `let _ = record(...)`
        // 再 `return VStack { ... }`——body 就不再是 result-builder 內容，而實測的後果是
        // `.onAppear` 從未觸發：scale factor 有被記錄，`RENDER COMPLETE` 卻沒有，8 秒與 14 秒的
        // 執行皆然。那個標記正是 `test_common.zsh` 等待的對象，因此該 app 會看起來像卡住了。
        VStack(spacing: 10) {
            let _ = P42History.record(scaleFactor)

            Text("P42: window scale factor")
                .font(.system(size: 18))

            Text("current: \(scaleFactor)")
                .font(.system(size: 24))

            Text("changes observed: \(P42History.changeCount)")

            // The line that answers the question. One entry after changing the
            // display scale means the notification never fired.
            // 回答問題的那一行。改變顯示器縮放後仍只有一項，代表通知從未觸發。
            Text(P42History.summary)

            Text(
                "Change the display scale in Settings without touching this "
                    + "window, then read the line above."
            )
            Text("在設定中改變顯示器縮放，不要碰這個視窗，然後讀上面那一行。")
        }
        .padding(20)
        .onAppear {
            P42Diagnostics.write(
                "arguments \(CommandLine.arguments.joined(separator: " | "))"
            )
            P42Diagnostics.renderComplete()
            #if canImport(CGtk)
                P42GtkProbe.start()
            #endif
        }
    }
}
