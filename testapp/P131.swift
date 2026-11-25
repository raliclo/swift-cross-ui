import DefaultBackend
import Foundation
import SwiftCrossUI

// P131 contentShape(_:eoFill:), checked by where taps, long presses and the
// hovering pointer land.
//
// (a) An HStack of two labels with a wide Spacer between them, given
// `.contentShape(Rectangle())` and a tap gesture: a tap in the empty gap must
// register as "gap". (b) A 120x120 square with `.contentShape(Circle())` and a
// tap gesture, drawn over a grey square of the same size that has its own tap
// gesture. A tap near the square's corner is outside the circle, so it must
// pass through to the grey square ("under"), not register on the circle; a tap
// at the centre must register on the circle. (c) The same pair for long
// presses: the grey square has `.onTapGesture(gesture: .longPress)`, the
// circle `.onTapAndLongPressGesture`, so both long-press modifiers are made to
// take the shape. A long press at the corner must reach the grey square
// ("lp-under"), one at the centre the circle ("lp-circle"); the circle's own
// tap does nothing, because the files tap there first to put the pointer in
// place. The app logs "P131 PASS" once the hits are gap, under, circle,
// lp-under, lp-circle.
//
// (d) Desktop only, after that: a 100x100 green square at the top-left of the
// window, client (16,16), with `.contentShape(Circle()).onHover`. The files
// move the pointer to the square's corner (outside the circle), tap "Hover
// mark", then move to the centre. Hover must start only at the centre, so the
// hits after PASS must be mark, hover-in, and the app then logs "P131 PASS
// WITH HOVER"; a hover that ignored the shape starts at the corner, before
// the mark. Anything else logs "P131 FAIL (...)". Everything goes to
// p131-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// The square is first and the content is pinned to the top-left so that its
// client coordinates are the same on every desktop; the status text is last,
// where a long verdict cannot move anything the files point at.
//
// P131 contentShape(_:eoFill:),以點擊、長按與懸停的指標落在何處檢查。
//
// (a) 兩個標籤之間夾著寬 Spacer 的 HStack,加上 `.contentShape(Rectangle())` 與點擊手勢：點在空隙中必須記為
// 「gap」。(b) 一個 120x120、加上 `.contentShape(Circle())` 與點擊手勢的正方形，畫在一個同尺寸、有自己點擊手勢
// 的灰色正方形之上。點在正方形角落附近位於圓外，所以必須穿透到灰色正方形(「under」),而不是記在圓上；點在中心必須
// 記在圓上。(c) 長按的同一組：灰色正方形用 `.onTapGesture(gesture: .longPress)`,圓用
// `.onTapAndLongPressGesture`,讓兩種長按 modifier 都必須沿用形狀。角落的長按必須抵達灰色正方形(「lp-under」),
// 中心的長按必須抵達圓(「lp-circle」);圓自己的點按什麼都不做，因為動作檔會先在那裡點一下以放好指標。命中依序為
// gap、under、circle、lp-under、lp-circle 時，app 記下「P131 PASS」。
//
// (d) 僅限桌面，在那之後：視窗左上角 client (16,16) 處一個 100x100 的綠色正方形，加上
// `.contentShape(Circle()).onHover`。動作檔把指標移到正方形的角落(圓外),點「Hover mark」,再移到中心。懸停必須
// 只在中心開始，因此 PASS 之後的命中必須是 mark、hover-in,app 接著記下「P131 PASS WITH HOVER」;忽略形狀的懸停會
// 在角落、也就是 mark 之前開始。其餘情況記下「P131 FAIL (...)」。全部寫入 p131-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR)與 stdout。
//
// 正方形放在最前面，內容釘在左上角，讓它的 client 座標在每個桌面上都相同；狀態文字放在最後，長的結果訊息就推不動
// 動作檔所指的任何東西。
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

    static let expected = ["gap", "under", "circle", "lp-under", "lp-circle"]
    static let hoverExpected = ["mark", "hover-in"]

    /// The verdict on `hits` against `expected`, or nil while they are still a
    /// prefix of it. / `hits` 對照 `expected` 的結果；仍是其前綴時為 nil。
    static func verdict(_ hits: [String], _ expected: [String], pass: String) -> String? {
        if hits == expected { return pass }
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
        .defaultSize(width: 380, height: 640)
    }
}

struct P131View: View {
    @State var hits: [String] = []
    /// Hits after the touch checks passed; hover is checked here.
    /// 觸控檢查通過之後的命中；懸停在此檢查。
    @State var hoverHits: [String] = []
    @State var passed = false
    @State var verdict = "Waiting for taps"

    func hit(_ name: String) {
        P131.log("P131 hit: \(name)")
        if passed {
            hoverHits.append(name)
            if let result = P131.verdict(hoverHits, P131.hoverExpected, pass: "P131 PASS WITH HOVER") {
                P131.log(result)
                verdict = result
            }
            return
        }
        // A hover before the touch checks are done is not part of them: the
        // pointer may rest anywhere when the window opens.
        // 觸控檢查完成之前的懸停不屬於它們：視窗開啟時指標可能停在任何地方。
        if name == "hover-in" { return }
        hits.append(name)
        if let result = P131.verdict(hits, P131.expected, pass: "P131 PASS") {
            P131.log(result)
            verdict = result
            passed = result == "P131 PASS"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // (d) Hover counts only inside the circle. At the top-left, so the
            // files can point at it: the square spans client (16,16)-(116,116).
            // (d) 只有圓內才算懸停。放在左上角，讓動作檔能指向它：正方形涵蓋 client (16,16)-(116,116)。
            HStack(spacing: 12) {
                Color.green
                    .frame(width: 100, height: 100)
                    .contentShape(Circle())
                    .onHover { inside in
                        if inside { hit("hover-in") }
                    }
                Text("Hover mark")
                    .onTapGesture { hit("mark") }
            }
            .frame(height: 100)

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

            HStack(spacing: 16) {
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

                // (c) Only the circle takes long presses; its corners pass through.
                // (c) 只有圓形接受長按；其角落穿透到灰色。
                ZStack {
                    Color.gray.frame(width: 120, height: 120)
                        .onTapGesture(gesture: .longPress) { hit("lp-under") }
                    ZStack {
                        Color.purple
                        Text("Hold target")
                            .foregroundColor(.white)
                    }
                    .frame(width: 120, height: 120)
                    .contentShape(Circle())
                    .onTapAndLongPressGesture(onTap: {}, onLongPress: { hit("lp-circle") })
                }
            }

            Text("Blue and purple squares: only their inscribed circles take taps and long presses")
                .frame(width: 300, alignment: .leading)
            Text(P131.title)
            Text(verdict)
                .frame(width: 300, alignment: .leading)
            Text("Hits: \((hits + hoverHits).isEmpty ? "none" : (hits + hoverHits).joined(separator: ", "))")
                .frame(width: 300, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
