import DefaultBackend
import Foundation
import SwiftCrossUI

// P16 Windows (WinUIBackend) repro app: NavigationSplitView initial layout.
//
// - #160 Split views are laid out very incorrectly on the initial load, then
//   snap to a correct layout as soon as any state changes or the window is
//   resized. Upstream's suspicion, stated as unverified, is that WinUI cannot
//   produce a correct size before the first render and hands back a dud value.
//   Upstream reproduces it by running SplitExample on Windows.
//
// This mirrors SplitExample's structure -- two-column and three-column, a List
// in the sidebar, padding of 10 -- so that a difference in behaviour is a
// difference in the backend rather than in the view tree. What it adds is
// measurement: each pane reports the size it was given, so "very incorrectly"
// becomes a number that can be written down and compared after the snap.
//
// Read the numbers before touching anything. The bug is defined by the first
// render, and resizing the window is one of the two things that fixes it, so
// any interaction destroys the evidence. `Force update` exists to trigger the
// snap deliberately, without changing the structure being measured.
//
// The sizes are displayed live rather than captured into state at first
// render. Writing state from inside a layout pass would feed back into the
// layout it is measuring, and GeometryReader's own documentation warns that
// content may be evaluated several times with different sizes before the
// layout settles.
//
// Build this file as a standalone app target.

enum P16Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P16] \(message)")

        guard let data = "P16 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p16-debug-events.log")
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

    static func recordPane(label: String, size: ViewSize) {
        guard isEnabled else { return }
        let line = "\(label): \(Int(size.width)) x \(Int(size.height))"
        guard lastReported[label] != line else { return }
        lastReported[label] = line
        write(line)
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P16 ready for #160 initial-layout checks")
    }
}

@main
@HotReloadable
struct P16SplitLayoutApp: App {
    var body: some Scene {
        WindowGroup("P16 split view initial layout") {
            #hotReloadable {
                P16RootView()
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}

enum P16Area: String, CaseIterable, Identifiable {
    var id: Self { self }

    case science = "Science"
    case humanities = "Humanities"
}

enum P16Columns {
    case two
    case three
}

struct P16RootView: View {
    @State var selectedArea: P16Area?
    @State var columns = P16Columns.two

    // Deliberately unrelated to the split view's structure. Changing it is a
    // state change and nothing else, which is exactly what #160 says is enough
    // to make the layout correct itself.
    @State var updateCount = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("P16: split view initial layout (#160)")
                .font(.system(size: 18))

            Text("Read the pane sizes below before clicking anything.")

            HStack(spacing: 10) {
                Button("Force update (\(updateCount))") {
                    updateCount += 1
                }

                Button(columns == .two ? "Switch to 3 column" : "Switch to 2 column") {
                    columns = columns == .two ? .three : .two
                }
            }

            switch columns {
                case .two:
                    doubleColumn
                case .three:
                    tripleColumn
            }
        }
        .padding(10)
        .onAppear {
            P16Diagnostics.write("arguments \(CommandLine.arguments.joined(separator: " | "))")
            P16Diagnostics.renderComplete()
        }
    }

    var doubleColumn: some View {
        NavigationSplitView {
            VStack {
                P16PaneSize(label: "sidebar")
                List(P16Area.allCases, selection: $selectedArea) { area in
                    HStack {
                        Color.purple.frame(width: 40, height: 40).cornerRadius(4)
                        Text(area.rawValue)
                    }
                }
                Spacer()
            }
            .padding(10)
        } detail: {
            VStack {
                P16PaneSize(label: "detail")
                Text(selectedArea?.rawValue ?? "Select an area")
                Spacer()
            }
            .padding(10)
        }
    }

    var tripleColumn: some View {
        NavigationSplitView {
            VStack {
                P16PaneSize(label: "sidebar")
                List(P16Area.allCases, selection: $selectedArea) { area in
                    Text(area.rawValue)
                }
                Spacer()
            }
            .padding(10)
        } content: {
            VStack {
                P16PaneSize(label: "middle")
                Text(selectedArea?.rawValue ?? "Select an area")
                Spacer()
            }
            .padding(10)
        } detail: {
            VStack {
                P16PaneSize(label: "detail")
                Text("Detail for \(selectedArea?.rawValue ?? "nothing")")
                Spacer()
            }
            .padding(10)
        }
    }
}

// Reports the size its pane was given. Kept to a fixed frame so the reader
// itself does not influence the pane's height while measuring it.
//
// **What this actually reports is not the pane.** `.frame(height: 22)`
// constrains the `GeometryReader`, so `proxy.size.height` can only ever be 22,
// and that 22 is what every run on every backend has recorded as the pane's
// height. The width is not trustworthy either: the reader sits inside the
// pane's `VStack`, so it measures the content column rather than the pane.
//
// Moving the reader into `.overlay(alignment: .topLeading)` on the padded
// `VStack` -- the shape `P7SplitProbe` uses successfully -- was tried on
// 2026-09-01 and **broke the app**: the window never became visible, wincap
// found no window to capture at one second or at the end, the action file never
// replayed, and the panes reported 200x142 and 20x46. Reverted.
//
// **`overlay` here is not SwiftUI's.** `OverlayModifier.computeLayout` returns
// `max(contentSize, overlaySize)` on both axes, so the overlay can grow its
// host; SwiftUI's never does. `NavigationSplitView` probes its panes at a
// proposed width of 0 to find their minimums, which the comment beside P7's
// detail pane records, so anything that changes what a pane answers changes the
// whole layout.
//
// What differs from P7 is not `List` versus `VStack` -- P7's detail overlay
// wraps a padded `VStack` too. It is that P7's panes contain no `Spacer` and
// its whole split view sits inside `.frame(width: 420, height: 180)`, so
// nothing there is free to grow. Each pane here ends with a `Spacer`, which is
// greedy and answers with whatever it is offered, and the split view has no
// fixed frame.
//
// The exact step from there to "no window at all" is not established; what is
// established is that `overlay` takes part in sizing, and that this pane's size
// is not its own to give.
//
// So the numbers below are a floor, not a measurement. The pane sizes come
// from `SplitView.commit` instead, which reports them when `SCUI_DEBUG_SPLIT`
// is set -- outside the view tree, so nothing it reports is affected by the
// reporting. Run `SCUI_DEBUG_SPLIT=1 ./P16.exe --debug` and read
// `splitview-debug.log`; the panes are 200x486 and 680x486, and they are the
// same before and after a state change, which is what settles #160.
//
// 回報其窗格所獲得的尺寸。保持固定框架，使 reader 本身不影響所量測的窗格高度。
//
// **但它實際回報的並不是窗格。** `.frame(height: 22)` 限制了 `GeometryReader`，因此
// `proxy.size.height` 只可能是 22——而那個 22 就是每一次執行、每一個 backend 所記錄的「窗格高度」。
// 寬度同樣不可信：reader 位於窗格的 `VStack` 之內，量到的是內容欄，而非窗格。
//
// 2026-09-01 曾嘗試把 reader 移入 padded `VStack` 的 `.overlay(alignment: .topLeading)`
// ——那是 `P7SplitProbe` 成功採用的形狀——結果**弄壞了這個 app**：視窗從未出現，wincap 在第一秒
// 與結束時都找不到可擷取的視窗，動作檔從未重放，而窗格回報 200x142 與 20x46。已還原。
//
// **此處的 `overlay` 不是 SwiftUI 的那一個。** `OverlayModifier.computeLayout` 在兩個軸向上都回傳
// `max(contentSize, overlaySize)`，因此 overlay 有可能撐大它的宿主；SwiftUI 的則絕不會。而
// `NavigationSplitView` 會以「提議寬度 0」探詢各窗格以求出其最小值（此事記於 P7 detail 窗格旁的
// 註解），因此任何改變窗格回答的東西，都會改變整個版面。
//
// 與 P7 的差別不在於 `List` 或 `VStack`——P7 的 detail overlay 包的同樣是加了 padding 的 `VStack`。
// 差別在於：P7 的窗格中**沒有 `Spacer`**，而且它整個 split view 位於
// `.frame(width: 420, height: 180)` 之內，沒有東西能自由長大。而這裡每個窗格都以 `Spacer` 結尾
// ——`Spacer` 是貪婪的，被提議多少就回答多少——且該 split view 沒有固定框架。
//
// 從那一步到「完全沒有視窗」之間的確切機制尚未確立；已確立的是：`overlay` 會參與尺寸決定，
// 而這個窗格的尺寸並不由它自己決定。
//
// 因此下方的數字是一個下限，而非量測值。窗格尺寸改由 `SplitView.commit` 提供——設定
// `SCUI_DEBUG_SPLIT` 時它會印出來，位置在 view tree 之外，因此它所回報的一切都不受回報行為影響。
// 執行 `SCUI_DEBUG_SPLIT=1 ./P16.exe --debug` 並讀取 `splitview-debug.log`：窗格為 200x486 與
// 680x486，且狀態改變前後相同——#160 即由此定案。
struct P16PaneSize: View {
    var label: String

    var body: some View {
        GeometryReader { proxy in
            let _ = P16Diagnostics.recordPane(label: label, size: proxy.size)
            Text("\(label): \(Int(proxy.size.width)) x \(Int(proxy.size.height))")
        }
        .frame(height: 22)
    }
}
