import DefaultBackend
import Foundation
import SwiftCrossUI

// P123 shadow(color:radius:x:y:): a drop shadow that follows the content's shape.
//
// Text, a circle and a rectangle each cast a hard red shadow (radius 0) 6 points
// right and 6 down, and a soft grey one; the screenshot is the check that the
// shadow sits beneath the content, follows the glyphs and the circle's edge rather
// than a box, and falls down and to the right on every backend. The app also
// measures each shadowed view against the same view without a shadow and logs
// "P123 PASS" when every pair is the same size -- a shadow never changes layout --
// or "P123 FAIL (...)", to p123-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P123 shadow(color:radius:x:y:):跟著內容形狀的投影。文字、圓形與矩形各投出一個向右 6 點、向下 6 點的
// 紅色硬陰影(半徑 0),以及一個灰色柔和陰影；截圖用來檢查陰影位於內容下方、跟著字形與圓形邊緣而不是
// 方框，且在每個 backend 上都往右下落。app 也把每個有陰影的 view 與同一個沒有陰影的 view 比較尺寸，全部
// 相同時(陰影從不改變版面)在 p123-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P123 PASS」,
// 否則記下「P123 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P123 {
    static let title = "P123 Shadow"

    @MainActor static var sizes: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p123-debug-events.log")
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
        var failures: [String] = []
        for name in ["text", "circle", "rectangle"] {
            guard let plain = sizes["\(name) plain"], let shadowed = sizes["\(name) shadowed"] else {
                failures.append("\(name) not measured")
                continue
            }
            log("P123 \(name): \(plain.width)x\(plain.height) -> \(shadowed.width)x\(shadowed.height)")
            if plain.width != shadowed.width || plain.height != shadowed.height {
                failures.append("\(name) changed size")
            }
        }
        return failures.isEmpty ? "P123 PASS" : "P123 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P123App: App {
    var body: some Scene {
        WindowGroup(P123.title) {
            P123View()
        }
        .defaultSize(width: 520, height: 520)
    }
}

struct P123Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P123Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P123Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P123.sizes[name] = size
        return Color.clear
    }
}

struct P123View: View {
    @State var verdict = "Measuring"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(P123.title)
            Text(verdict)
            HStack(spacing: 32) {
                P123Measured(name: "text plain", content: Text("Shadow").font(.title))
                P123Measured(
                    name: "text shadowed",
                    content: Text("Shadow").font(.title).shadow(color: .red, radius: 0, x: 6, y: 6)
                )
            }
            HStack(spacing: 32) {
                P123Measured(name: "circle plain", content: Circle().fill(Color.blue).frame(width: 60, height: 60))
                P123Measured(
                    name: "circle shadowed",
                    content: Circle().fill(Color.blue).frame(width: 60, height: 60)
                        .shadow(color: .red, radius: 0, x: 6, y: 6)
                )
                Circle().fill(Color.blue).frame(width: 60, height: 60).shadow(radius: 8)
            }
            HStack(spacing: 32) {
                P123Measured(name: "rectangle plain", content: Rectangle().fill(Color.green).frame(width: 80, height: 40))
                P123Measured(
                    name: "rectangle shadowed",
                    content: Rectangle().fill(Color.green).frame(width: 80, height: 40)
                        .shadow(color: .red, radius: 0, x: 6, y: 6)
                )
                Rectangle().fill(Color.green).frame(width: 80, height: 40).shadow(radius: 8, x: 0, y: 4)
            }
        }
        .padding(24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P123.verdict()
                P123.log(result)
                verdict = result
            }
        }
    }
}
