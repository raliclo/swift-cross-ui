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
// replayed, and the panes reported 200x142 and 20x46. Reverted. Whatever
// `overlay` does to layout in this framework is not what it does in SwiftUI,
// and `.overlay` already has history here -- it used to swallow pointer events.
//
// So the numbers below are a floor, not a measurement, and #160 cannot be
// settled from them. Fixing this needs the overlay difference understood first.
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
// `overlay` 在本框架中對版面所做的事，與它在 SwiftUI 中所做的並不相同，而 `.overlay` 在此本就有
// 前科——它曾吞掉指標事件。
//
// 因此下方的數字是一個下限，而非量測值，#160 無法據此定案。要修好這件事，必須先弄懂 overlay 的差異。
//
// 回報一個被傳入的尺寸。它自己不量測任何東西：呼叫端把 `GeometryReader` 放在窗格的
// **overlay** 中，再把 `proxy.size` 傳進來——與 `P7SplitProbe` 的形狀相同。
//
// 先前的版本是窗格 `VStack` 內的一個子元件，其 `GeometryReader` 位於 `.frame(height: 22)` 之下。
// 該框架限制了 reader，因此 `proxy.size.height` 永遠只能是 22——而那個 22 隨後就被當成「窗格的
// 高度」在每一次執行、每一個 backend 上被回報。寬度是真的，因為沒有東西限制它，而這正是讓這一對
// 數字看起來像「修好一半的版面缺陷」、而非「量測方式有誤」的原因。
//
// 使用 overlay 才能讓它誠實：overlay 不參與宿主的版面計算，因此 reader 得到的是窗格自身的尺寸，
// 而不是探針自己要求的尺寸。
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
