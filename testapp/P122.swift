import DefaultBackend
import Foundation
import SwiftCrossUI

// P122 Text decorations and spacing: underline(_:), strikethrough(_:), kerning(_:),
// tracking(_:), baselineOffset(_:) and lineSpacing(_:).
//
// Each spacing modifier is shown twice, plain and modified, and both are measured
// with a GeometryReader. A second after the window appears the app checks that
// tracking and kerning made the text wider, and that lineSpacing and baselineOffset
// made it taller -- which shows the backend's measurement includes them, not only
// its drawing -- and logs "P122 PASS" or "P122 FAIL (...)" to p122-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout. Underline and strikethrough do not change a
// size, so the screenshot is their check: solid, dotted and dashed lines, and a
// red one. Only AppKit and UIKit draw the patterns and the colour so far; GTK,
// WinUI and Android draw every line solid in the text's colour.
//
// P122 文字裝飾與間距:underline(_:)、strikethrough(_:)、kerning(_:)、tracking(_:)、baselineOffset(_:) 與
// lineSpacing(_:)。每個間距 modifier 都顯示兩次(原樣與套用後),並以 GeometryReader 量測。視窗出現一秒後,
// app 檢查 tracking 與 kerning 讓文字變寬、lineSpacing 與 baselineOffset 讓文字變高——這表示 backend 的量測
// 包含了它們，而不只是繪製——並在 p122-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下
// 「P122 PASS」或「P122 FAIL (...)」。底線與刪除線不改變尺寸，因此由截圖檢查：實線、點線、虛線與一條紅線。
// 目前只有 AppKit 與 UIKit 會畫出樣式與顏色;GTK、WinUI 與 Android 都以文字顏色畫實線。
//
// Build this file as a standalone app target.

enum P122 {
    static let title = "P122 Text decorations"

    @MainActor static var sizes: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p122-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    /// The checks: which pair, which axis, and that the modified one must be larger.
    /// 檢查項目：哪一對、哪一軸，以及套用後的那個必須比較大。
    @MainActor static func verdict() -> String {
        let checks: [(String, KeyPath<ViewSize, Double>, String)] = [
            ("tracking", \.width, "width"),
            ("kerning", \.width, "width"),
            ("lineSpacing", \.height, "height"),
            ("baselineOffset", \.height, "height"),
        ]
        var failures: [String] = []
        for (name, axis, axisName) in checks {
            guard let plain = sizes["\(name) plain"], let modified = sizes["\(name) modified"] else {
                failures.append("\(name) not measured")
                continue
            }
            let before = plain[keyPath: axis]
            let after = modified[keyPath: axis]
            log("P122 \(name) \(axisName): \(before) -> \(after)")
            if !(after > before) {
                failures.append("\(name) \(axisName) \(before) -> \(after)")
            }
        }
        return failures.isEmpty ? "P122 PASS" : "P122 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P122App: App {
    var body: some Scene {
        WindowGroup(P122.title) {
            P122View()
        }
        .defaultSize(width: 560, height: 640)
    }
}

/// `content`, with its size recorded under `name`. / 記錄尺寸於 `name` 之下的 `content`。
struct P122Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P122Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P122Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P122.sizes[name] = size
        return Color.clear
    }
}

struct P122View: View {
    @State var verdict = "Measuring"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(P122.title)
            Text(verdict)
            Text("Underline").underline()
            Text("Dotted underline").underline(pattern: .dot)
            Text("Red dashed underline").underline(pattern: .dash, color: .red)
            Text("Strikethrough").strikethrough()
            HStack(spacing: 12) {
                P122Measured(name: "tracking plain", content: Text("Tracking"))
                P122Measured(name: "tracking modified", content: Text("Tracking").tracking(4))
            }
            HStack(spacing: 12) {
                P122Measured(name: "kerning plain", content: Text("Kerning"))
                P122Measured(name: "kerning modified", content: Text("Kerning").kerning(4))
            }
            HStack(alignment: .top, spacing: 12) {
                P122Measured(name: "lineSpacing plain", content: Text("Line\nspacing"))
                P122Measured(name: "lineSpacing modified", content: Text("Line\nspacing").lineSpacing(12))
            }
            HStack(alignment: .top, spacing: 12) {
                P122Measured(name: "baselineOffset plain", content: Text("Baseline"))
                P122Measured(name: "baselineOffset modified", content: Text("Baseline").baselineOffset(8))
            }
        }
        .padding(12)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P122.verdict()
                P122.log(result)
                verdict = result
            }
        }
    }
}
