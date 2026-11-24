import DefaultBackend
import Foundation
import SwiftCrossUI

// P131 contentShape(_:eoFill:), checked by where taps land.
//
// (a) An HStack of two labels with a wide Spacer between them, given
// `.contentShape(Rectangle())` and a tap gesture: a tap in the empty gap must
// register as "gap". (b) A 120x120 square with `.contentShape(Circle())` and a
// tap gesture, drawn over a grey square of the same size that has its own tap
// gesture. A tap near the square's corner is outside the circle, so it must
// pass through to the grey square ("under"), not register on the circle; a tap
// at the centre must register on the circle. The app logs each hit and
// "P131 PASS" once the hits are gap, under, circle, or "P131 FAIL (...)", to
// p131-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P131 contentShape(_:eoFill:),以點擊落在何處檢查。
//
// (a) 兩個標籤之間夾著寬 Spacer 的 HStack,加上 `.contentShape(Rectangle())` 與點擊手勢：點在空隙中必須記為
// 「gap」。(b) 一個 120x120、加上 `.contentShape(Circle())` 與點擊手勢的正方形，畫在一個同尺寸、有自己點擊手勢
// 的灰色正方形之上。點在正方形角落附近位於圓外，所以必須穿透到灰色正方形(「under」),而不是記在圓上；點在中心必須
// 記在圓上。app 在 p131-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下每次命中，命中依序為
// gap、under、circle 時記下「P131 PASS」,否則記下「P131 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P131 {
    static let title = "P131 contentShape"

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p131-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    static let expected = ["gap", "under", "circle"]

    static func verdict(_ hits: [String]) -> String? {
        if hits == expected { return "P131 PASS" }
        for (index, hit) in hits.enumerated() where index >= expected.count || hit != expected[index] {
            return "P131 FAIL (hits \(hits.joined(separator: ", ")), expected \(expected.joined(separator: ", ")))"
        }
        return nil
    }
}

@main
struct P131App: App {
    var body: some Scene {
        WindowGroup(P131.title) {
            P131View()
        }
        .defaultSize(width: 420, height: 520)
    }
}

struct P131View: View {
    @State var hits: [String] = []
    @State var verdict = "Waiting for taps"

    func hit(_ name: String) {
        hits.append(name)
        P131.log("P131 hit: \(name)")
        if let result = P131.verdict(hits) {
            P131.log(result)
            verdict = result
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(P131.title)
            Text(verdict)
            Text("Hits: \(hits.isEmpty ? "none" : hits.joined(separator: ", "))")

            // (a) The gap between the labels draws nothing; the rectangle makes it tappable.
            // (a) 標籤之間的空隙什麼都沒畫；矩形讓它可被點擊。
            HStack(spacing: 0) {
                Text("Gap left")
                Spacer()
                Text("Gap right")
            }
            .frame(width: 300)
            .contentShape(Rectangle())
            .onTapGesture { hit("gap") }

            // (b) Only the circle takes taps; its corners pass through to grey.
            // (b) 只有圓形接受點擊；其角落穿透到灰色。
            ZStack {
                Color.gray.frame(width: 120, height: 120)
                    .onTapGesture { hit("under") }
                ZStack {
                    Color.blue
                    Text("Circle target")
                        .foregroundColor(.white)
                }
                .frame(width: 120, height: 120)
                .contentShape(Circle())
                .onTapGesture { hit("circle") }
            }
            Text("Blue square: only its inscribed circle is tappable")
        }
        .padding(16)
    }
}
