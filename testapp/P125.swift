import DefaultBackend
import Foundation
import SwiftCrossUI

// P125 zIndex(_:), checked by where taps land.
//
// Three squares share one frame in a ZStack: red declared first with zIndex 2,
// green, then blue declared last with zIndex -1. A label on top, which does not
// take hits, marks the centre. Red must be drawn on top, and so the first tap
// on the label must reach red -- what is drawn on top is what is hit, on every
// backend. "Drop zIndex" then sets every zIndex to 0, which must put
// declaration order back: the second tap must reach blue. The app logs each
// hit and "P125 PASS" once the hits are red then blue, or "P125 FAIL (...)", to
// p125-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P125 zIndex(_:),以點擊落在何處檢查。ZStack 中三個正方形共用同一個框：最先宣告、zIndex 2 的紅色，綠色，
// 以及最後宣告、zIndex -1 的藍色。最上層一個不接受點擊的標籤標出中心。紅色必須畫在最上面，因此對該標籤的第一
// 次點擊必須到達紅色——在每個 backend 上，畫在最上面的就是被點到的。接著「Drop zIndex」把每個 zIndex 設為 0,
// 這必須恢復宣告順序：第二次點擊必須到達藍色。app 在 p125-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout
// 記下每次命中，命中依序為紅、藍時記下「P125 PASS」,否則記下「P125 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P125 {
    static let title = "P125 zIndex"

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p125-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    static func verdict(_ hits: [String]) -> String? {
        if hits == ["red", "blue"] { return "P125 PASS" }
        if hits.count >= 2 { return "P125 FAIL (hits \(hits.joined(separator: ", ")), expected red, blue)" }
        if let first = hits.first, first != "red" { return "P125 FAIL (first hit \(first), expected red)" }
        return nil
    }
}

@main
struct P125App: App {
    var body: some Scene {
        WindowGroup(P125.title) {
            P125View()
        }
        .defaultSize(width: 420, height: 560)
    }
}

struct P125View: View {
    @State var ordered = true
    @State var hits: [String] = []
    @State var verdict = "Waiting for taps"

    func hit(_ name: String) {
        hits.append(name)
        P125.log("P125 hit: \(name) (zIndex \(ordered ? "on" : "off"))")
        if let result = P125.verdict(hits) {
            P125.log(result)
            verdict = result
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(P125.title)
            Text(verdict)
            Text("Hits: \(hits.isEmpty ? "none" : hits.joined(separator: ", "))")
            ZStack {
                Color.red.frame(width: 140, height: 90)
                    .onTapGesture { hit("red") }
                    .zIndex(ordered ? 2 : 0)
                Color.green.frame(width: 140, height: 90)
                    .onTapGesture { hit("green") }
                Color.blue.frame(width: 140, height: 90)
                    .onTapGesture { hit("blue") }
                    .zIndex(ordered ? -1 : 0)
                Text("Tap zIndex stack")
                    .foregroundColor(.white)
                    .allowsHitTesting(false)
            }
            // Kept ordered for the screenshot: red, declared first, must be drawn
            // over green and blue here, whatever the taps have done above.
            // 為了截圖而維持排序：在這裡，最先宣告的紅色必須畫在綠色與藍色之上，不論上方的點擊做了什麼。
            HStack(spacing: 8) {
                ZStack {
                    Color.red.frame(width: 60, height: 60).zIndex(1)
                    Color.green.frame(width: 60, height: 60).offset(x: 20, y: 20)
                    Color.blue.frame(width: 60, height: 60).offset(x: 40, y: 40).zIndex(-1)
                }
                .frame(width: 110, height: 110, alignment: .topLeading)
                Text("Static: red over green over blue")
            }
            Button(ordered ? "Drop zIndex" : "zIndex dropped") {
                ordered = false
                P125.log("P125 zIndex dropped")
            }
        }
        .padding(16)
    }
}
