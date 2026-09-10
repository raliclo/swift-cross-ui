import DefaultBackend
import Foundation
import SwiftCrossUI

// P63: does `GeometryProxy.frame(in:)` report where a view actually is?
//
// The number is checked: `ls testapp` gives P50..P62 and nothing under
// testapp/plan or matrix_coverage mentions P63.
//
// **THE ASSERTION IS THE AGREEMENT BETWEEN A NUMBER AND A PIXEL, which is why
// the reader draws a marker at its own top-left corner.** A frame(in:) that
// returned zeros would look completely reasonable on its own -- (0, 0, 220, 60)
// is a perfectly ordinary rectangle. It is only wrong relative to where the
// view IS, so the app prints the numbers AND puts a mark at the corner they
// claim to describe, and the test measures the mark.
//
// Three spaces, three different right answers for the same view:
//   .local   always (0, 0): the view's own corner.
//   .global  where it sits in the window, which is what the marker checks.
//   .named   its offset from the box that declared the name -- and that box is
//            deliberately NOT at the window's origin, so a `.named` that quietly
//            fell back to window coordinates reads as a different number rather
//            than the same one.
//
// P63:`GeometryProxy.frame(in:)` 回報的，是這個 view 真正所在的位置嗎?
//
// 編號是查過的:`ls testapp` 給出 P50..P62，而 testapp/plan 與 matrix_coverage 底下都沒有提到 P63。
//
// **判定的是「一個數字」與「一個像素」是否一致——這正是那個 reader 會在自己左上角畫一個標記的原因。**
// 一個回傳全零的 frame(in:)，單獨看起來完全合理——(0, 0, 220, 60) 是一個再普通不過的矩形。它只有
// 「相對於這個 view 實際在哪」時才是錯的，因此這支 app 既印出數字、也在那些數字所宣稱描述的那個角落
// 放上一個記號，而測試量的是那個記號。
//
// 三種座標系，對同一個 view 有三個不同的正確答案:
//   .local   恆為 (0, 0):這個 view 自己的角。
//   .global  它在視窗中的位置，也就是那個標記所檢查的。
//   .named   它相對於「宣告了該名稱的那個盒子」的位移——而那個盒子刻意**不**位於視窗原點，因此一個
//            悄悄退回成視窗座標的 `.named`，讀起來會是另一個數字，而不是同一個。

enum P63Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P63] \(message)")

        guard let data = "P63 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p63-debug-events.log")
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
        write("RENDER COMPLETE -- P63 ready for coordinate space checks")
    }
}

@main
@HotReloadable
struct P63App: App {
    var body: some Scene {
        WindowGroup("P63 coordinate spaces") {
            #hotReloadable {
                P63RootView()
            }
        }
        .defaultSize(width: 640, height: 520)
    }
}

struct P63RootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P63: GeometryProxy.frame(in:)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("The black square marks the reader's own top-left corner.")
            Text("global x/y must equal that square's position in the window.")
            Text("黑色方塊標出該 reader 自己的左上角;global 的 x/y 必須等於那個方塊在視窗中的位置。")

            // The named box is inset from the window on both axes ON PURPOSE:
            // a `.named` that fell back to window coordinates would print the
            // same numbers as `.global`, and two columns of identical numbers
            // is the one result this app must be able to rule out.
            // 這個具名盒子在兩個軸上都刻意離開視窗邊緣:一個退回成視窗座標的 `.named` 會印出與
            // `.global` 相同的數字，而「兩欄一模一樣的數字」正是這支 app 必須能夠排除的那個結果。
            VStack(alignment: .leading, spacing: 6) {
                Text("named space \"box\" starts here")
                P63Probe()
            }
            .padding(24)
            .background(Color(red: 0.85, green: 0.88, blue: 0.95))
            .coordinateSpace(name: "box")
        }
        .padding(20)
        .onAppear {
            P63Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
        }
    }
}

struct P63Probe: View {
    var body: some View {
        GeometryReader { proxy in
            let local = proxy.frame(in: .local)
            let global = proxy.frame(in: .global)
            let box = proxy.frame(in: .named("box"))

            VStack(alignment: .leading, spacing: 2) {
                // The marker, first and unpadded, so its own top-left IS the
                // reader's top-left.
                // 這個標記排在最前面且不加內距，如此它自己的左上角**就是**該 reader 的左上角。
                Color.black
                    .frame(width: 12, height: 12)

                Text(fmt("local", local))
                Text(fmt("global", global))
                Text(fmt("named box", box))
            }
            .onAppear {
                P63Diagnostics.write(fmt("local", local))
                P63Diagnostics.write(fmt("global", global))
                P63Diagnostics.write(fmt("named box", box))
                P63Diagnostics.renderComplete()
            }
        }
        .frame(width: 260, height: 90)
    }

    func fmt(_ label: String, _ rect: Path.Rect) -> String {
        "\(label): x=\(Int(rect.x)) y=\(Int(rect.y)) w=\(Int(rect.width)) h=\(Int(rect.height))"
    }
}
