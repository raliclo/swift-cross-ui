import DefaultBackend
import Foundation
import SwiftCrossUI

// P133 A ScrollView that grows keeps its top in view.
//
// A ScrollView of 61 rows starts 312 points tall and grows to 400 a second after it
// appears, as it does when its window is made taller. Its content must stay where it
// was: the scroll offset stays 0 and "Top row" stays visible. On AppKit the default
// NSClipView is not flipped and kept the document's distance from the bottom, so the
// content scrolled up by the 88 points of growth and hid the top (SoftPCB-UI,
// 2026-11-25). The app logs "P133 PASS" when the ScrollView grew by 80 points or more
// and its offset is 0, or "P133 FAIL (...)", to p133-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P133 變高的 ScrollView 讓頂端維持可見。
//
// 一個 61 列的 ScrollView 起初 312 點高，出現一秒後長到 400 點，與它的視窗被加高時相同。內容必須留在原處：捲動
// 位移維持 0,「Top row」維持可見。AppKit 預設的 NSClipView 沒有翻轉，維持的是文件與底部的距離，所以內容被往上
// 捲了增加的 88 點而藏住頂端(SoftPCB-UI,2026-11-25)。ScrollView 長高 80 點以上且位移為 0 時，app 在
// p133-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P133 PASS」,否則記下「P133 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P133 {
    static let title = "P133 Scroll growth"

    @MainActor static var heights: [Double] = []
    @MainActor static var offset = 0.0

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p133-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    @MainActor static func verdict() -> String {
        let grew = (heights.last ?? 0) - (heights.first ?? 0)
        log("P133 heights \(heights.first ?? 0) -> \(heights.last ?? 0), offset \(offset)")
        var failures: [String] = []
        if grew < 80 {
            failures.append("the ScrollView grew \(grew) points, not 88")
        }
        if abs(offset) > 0.5 {
            failures.append("content scrolled \(offset) points, top hidden")
        }
        return failures.isEmpty ? "P133 PASS" : "P133 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P133App: App {
    var body: some Scene {
        WindowGroup(P133.title) {
            P133View()
        }
        .defaultSize(width: 440, height: 560)
    }
}

struct P133Recorder: View {
    var height: Double

    var body: some View {
        if P133.heights.last != height {
            P133.heights.append(height)
        }
        return Color.clear
    }
}

struct P133View: View {
    @State var tall = false
    @State var verdict = "Measuring"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(P133.title)
            Text(verdict)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top row")
                    ForEach(1...60, id: \.self) { row in
                        Text("Row \(row)")
                    }
                }
                .padding(8)
            }
            .frame(width: 360, height: tall ? 400 : 312)
            .background(
                GeometryReader { proxy in
                    P133Recorder(height: proxy.size.height)
                }
            )
            .onScrollGeometryChange(for: Double.self, of: { $0.contentOffset.y }) { _, new in
                P133.offset = new
            }
        }
        .padding(24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                tall = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let result = P133.verdict()
                    P133.log(result)
                    verdict = result
                }
            }
        }
    }
}
