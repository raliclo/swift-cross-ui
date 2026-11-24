import DefaultBackend
import Foundation
import SwiftCrossUI

// P126 colorInvert(): red, green and blue each become one minus themselves.
//
// Each row shows a view plain, inverted, and inverted twice. The screenshot is the
// check for the colours: red becomes cyan, mid grey (128) stays near mid grey,
// black text on white becomes white text on black, and inverting twice gives the
// original back. The app also measures each inverted view against the same view
// plain and logs "P126 PASS" when every pair is the same size -- inversion never
// changes layout -- or "P126 FAIL (...)", to p126-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P126 colorInvert():紅、綠、藍各自變為 1 減去原值。每一列依序顯示原樣、反轉一次、反轉兩次的 view。
// 截圖用來檢查顏色：紅色變為青色，中灰(128)維持接近中灰，白底黑字變為黑底白字，反轉兩次回到原樣。
// app 也把每個反轉後的 view 與同一個原樣的 view 比較尺寸，全部相同時(反轉從不改變版面)在
// p126-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P126 PASS」,否則記下「P126 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P126 {
    static let title = "P126 Color invert"

    @MainActor static var sizes: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p126-debug-events.log")
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
        for name in ["red", "grey", "text"] {
            guard let plain = sizes["\(name) plain"], let inverted = sizes["\(name) inverted"] else {
                failures.append("\(name) not measured")
                continue
            }
            log("P126 \(name): \(plain.width)x\(plain.height) -> \(inverted.width)x\(inverted.height)")
            if plain.width != inverted.width || plain.height != inverted.height {
                failures.append("\(name) changed size")
            }
        }
        return failures.isEmpty ? "P126 PASS" : "P126 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P126App: App {
    var body: some Scene {
        WindowGroup(P126.title) {
            P126View()
        }
        .defaultSize(width: 520, height: 520)
    }
}

struct P126Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P126Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P126Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P126.sizes[name] = size
        return Color.clear
    }
}

/// One row: the view plain, inverted (measured against plain), and inverted twice.
/// 一列：原樣、反轉一次(與原樣比較尺寸)、反轉兩次。
struct P126Row<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        HStack(spacing: 24) {
            Text(name).frame(width: 60, alignment: .leading)
            P126Measured(name: "\(name) plain", content: content)
            P126Measured(name: "\(name) inverted", content: content.colorInvert())
            content.colorInvert().colorInvert()
        }
    }
}

struct P126View: View {
    @State var verdict = "Measuring"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(P126.title)
            Text(verdict)
            Text("plain, inverted, inverted twice")
            P126Row(name: "red", content: Color.red.frame(width: 80, height: 50))
            P126Row(
                name: "grey",
                content: Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255)
                    .frame(width: 80, height: 50)
            )
            P126Row(
                name: "text",
                content: Text("Invert").font(.title).foregroundColor(.black)
                    .padding(8).background(Color.white)
            )
        }
        .padding(24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P126.verdict()
                P126.log(result)
                verdict = result
            }
        }
    }
}
