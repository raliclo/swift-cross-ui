import DefaultBackend
import Foundation
import SwiftCrossUI

// P37 window level: does `.topmost()` actually keep the window in front?
//
// The one thing a screenshot of this app alone cannot tell you. Every other Pn
// is judged by what its own window contains; this one is judged by what is
// *not* covering it. So the test is to put another window over it and look
// again -- and the interesting outcome is the boring one, where nothing
// changed.
//
// It also reports what the backend says it can do, because the two platforms
// genuinely differ and a tester who does not know that will file the Linux
// result as a bug. GTK 4 removed `gtk_window_set_keep_above` and has no
// replacement, so on Linux the answer comes from the window manager, and WSLg's
// does not implement `_NET_WM_STATE_ABOVE`. On Windows the same GTK window is
// an ordinary HWND and `SetWindowPos` works on it.
//
// P37 視窗層級：`.topmost()` 真的能讓視窗保持在最前嗎？
//
// 這是唯獨「只看此 app 自己的截圖」無法判斷的一件事。其他每個 Pn 都以其視窗「內含什麼」來判定；
// 這一個則以「什麼沒有蓋住它」來判定。因此測試方式是把另一個視窗擺到它上面再看一次——而值得注意的
// 結果，正是那個乏味的結果：什麼都沒變。
//
// 它同時回報 backend 自稱能做到什麼，因為兩個平台確實不同，而不知情的測試者會把 Linux 的結果當成
// bug 回報。GTK 4 移除了 `gtk_window_set_keep_above` 且無替代品，因此在 Linux 上答案取決於窗口
// 管理員，而 WSLg 的並未實作 `_NET_WM_STATE_ABOVE`。在 Windows 上，同一個 GTK 視窗就是普通的
// HWND，`SetWindowPos` 對它有效。
//
// Build this file as a standalone app target.

enum P37Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func report(_ message: String) {
        guard isEnabled else { return }
        print("[P37] \(message)")

        guard let data = "P37 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p37-debug-events.log")
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
        report("RENDER COMPLETE -- P37 ready for window-level challenge")
    }
}

@main
@HotReloadable
struct P37WindowLevelApp: App {
    var body: some Scene {
        WindowGroup("P37 window level") {
            #hotReloadable {
                P37RootView()
            }
        }
        // Wide enough for the longest instruction line and tall enough for all
        // of them. 520x340 was the first guess and GTK said so on stderr:
        // "Tried to allocate 520x301, but GtkPassthroughFixed needs at least
        // 520x336", with the right-hand end of the English text cut off.
        // 寬度足以容納最長的那行指示，高度足以容納全部指示。520x340 是第一次的猜測，GTK 直接在
        // stderr 說明了問題：「Tried to allocate 520x301, but GtkPassthroughFixed needs at least
        // 520x336」，且英文文字的右端被切掉。
        .defaultSize(width: 760, height: 540)
        // The whole point of the app. `.windowLevel(.floating)` is the same
        // thing under the name SwiftUI uses; this spelling reads better where a
        // scene is only ever pinned or not.
        // 此 app 的全部重點。`.windowLevel(.floating)` 是同一件事，只是採用 SwiftUI 的名稱；當一個
        // scene 只有「釘住」與「不釘住」兩種狀態時，此種寫法較易讀。
        .topmost()
    }
}

struct P37RootView: View {
    @Environment(\.supportedWindowLevels) var supportedWindowLevels

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P37: window level")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            // What the backend claims. On a backend without `.floating` the
            // window below is an ordinary one and the test below will fail --
            // which is the correct result there, not a defect.
            // backend 的宣稱。在沒有 `.floating` 的 backend 上，下方的視窗就是一般視窗，而下面的
            // 測試會失敗——在該平台上那是正確結果，並非缺陷。
            Text("supported levels -> \(supportedWindowLevels.map(String.init(describing:)).joined(separator: ", "))")

            Text(
                supportedWindowLevels.contains(.floating)
                    ? "floating is supported: this window should stay in front"
                    : "floating is NOT supported: this window will behave normally"
            )
            .font(.system(size: 15))

            Text("How to test / 測試方式")
                .font(.system(size: 15))

            // Deliberately an instruction rather than a button. Raising another
            // window is the test, and no button inside this window can do that
            // to itself.
            // 刻意寫成指示而非按鈕。「把另一個視窗抬起來」就是測試本身，而此視窗內的任何按鈕都無法
            // 對自己做這件事。
            Text(
                """
                1. Click another application's window so it takes focus.
                2. This window must remain visible on top of it.
                3. Where floating is unsupported, this window goes behind \
                instead -- expected, and the line above says so.

                1. 點擊另一個應用程式的視窗，使其取得焦點。
                2. 此視窗必須仍然可見，且位於該視窗之上。
                3. 在不支援 floating 之處，此視窗會改為跑到後方——此為預期行為，上方那行已說明。
                """
            )
        }
        .padding(18)
        .onAppear {
            P37Diagnostics.report(
                "supported levels -> \(supportedWindowLevels)"
            )
            P37Diagnostics.renderComplete()
        }
    }
}
