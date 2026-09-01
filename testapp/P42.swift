import DefaultBackend
import Foundation
import SwiftCrossUI

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
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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
        }
    }
}
