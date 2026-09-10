import DefaultBackend
import Foundation
import SwiftCrossUI

// P65: the three continuous gestures (#32).
//
// The number is checked: `ls testapp` gives P50..P64.
//
// **EACH PANEL REPORTS NUMBERS, NOT A COLOUR CHANGE.** A panel that turned blue
// on drag would prove the callback fired and nothing about the value; a
// translation that is inverted, or in the wrong coordinate space, or that
// reports the window's coordinates instead of the view's, all look identical
// when the assertion is "something happened".
//
// The drag panel is the one a synthesised event can reach: `CGEvent` can press,
// move and release a real mouse. Magnify and rotate need a trackpad gesture,
// which no synthesiser here can produce, so those two are driven by hand and
// this app exists so that hand has something to drive.
//
// P65:三種連續手勢(#32)。
//
// 編號是查過的:`ls testapp` 給出 P50..P64。
//
// **每一格回報的是數字，而不是顏色變化。** 一個「拖曳時變藍」的面板，只證明了那個 callback 有觸發，
// 對數值本身什麼都沒證明;而一個正負顛倒的位移、一個座標系錯了的位移、或一個回報視窗座標而非 view
// 座標的位移，在「有沒有發生什麼事」這個判定之下看起來完全相同。
//
// 拖曳那一格是合成事件到得了的:`CGEvent` 能按下、移動並放開一個真正的滑鼠。縮放與旋轉需要觸控板
// 手勢，而此處沒有任何合成器產得出來——因此那兩格是手動驅動的，而這支 app 的存在，正是為了讓那雙手
// 有東西可以驅動。

enum P65Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P65] \(message)")

        guard let data = "P65 \(Date()) \(message)\n".data(using: .utf8) else { return }
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
            .appendingPathComponent("p65-debug-events.log")
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
        write("RENDER COMPLETE -- P65 ready for gesture checks")
    }
}

@main
@HotReloadable
struct P65App: App {
    var body: some Scene {
        WindowGroup("P65 continuous gestures") {
            #hotReloadable {
                P65RootView()
            }
        }
        .defaultSize(width: 620, height: 560)
    }
}

@MainActor
final class P65Model: SwiftCrossUI.ObservableObject {
    /// One per process. `@ObservedObject var model = P65Model()` rebuilds the
    /// model on every update, which is how P64's first run lost its callbacks.
    /// 一個行程一個。`@ObservedObject var model = P65Model()` 會在每次更新時重建 model——P64 的第一次
    /// 執行正是這樣弄丟了它的 callback。
    static let shared = P65Model()

    @SwiftCrossUI.Published var drag = "drag: (none yet)"
    @SwiftCrossUI.Published var magnify = "magnify: (none yet)"
    @SwiftCrossUI.Published var rotate = "rotate: (none yet)"
    @SwiftCrossUI.Published var dragEvents = 0
}

struct P65RootView: View {
    @ObservedObject var model = P65Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P65: continuous gestures (#32)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            // Fixed width, and it is not cosmetic.
            //
            // The reporting line grows as the numbers do; the window's content
            // is centred; so a widening line shifts every panel LEFT while the
            // pointer is still moving right. Measured before this frame was
            // added: a drag of 80 points reported 100, and the excess was the
            // panel sliding out from under the cursor. That reads exactly like
            // a scale factor in the backend, and it was the test app moving its
            // own target.
            //
            // 固定寬度，而這不是為了好看。
            //
            // 那行回報文字會隨數字變長;視窗的內容是置中的;於是一行變寬的文字，會在指標仍向右移動的
            // 同時，把每一格都往**左**推。加上這個 frame 之前量到:一次 80 點的拖曳被回報為 100 點，
            // 而多出來的部分，是那一格從游標底下滑走。那讀起來完全像是 backend 裡的一個縮放係數——
            // 而實際上是這支測試 app 自己在移動它的目標。
            Text(model.drag)
                .frame(width: 460)
            Text("drag events: \(model.dragEvents)")
                .frame(width: 460)
            Color(red: 0.80, green: 0.86, blue: 0.95)
                .frame(width: 260, height: 90)
                .onDragGesture { value in
                    model.dragEvents += 1
                    model.drag = fmt("drag", value)
                    P65Diagnostics.write(fmt("drag changed", value))
                } onEnded: { value in
                    model.drag = fmt("drag ENDED", value)
                    P65Diagnostics.write(fmt("drag ended", value))
                }

            Text(model.magnify)
                .frame(width: 460)
            Color(red: 0.95, green: 0.88, blue: 0.78)
                .frame(width: 260, height: 60)
                .onMagnifyGesture { value in
                    model.magnify = String(format: "magnify: %.3f", value.magnification)
                    P65Diagnostics.write(model.magnify)
                } onEnded: { value in
                    model.magnify = String(format: "magnify ENDED: %.3f", value.magnification)
                    P65Diagnostics.write(model.magnify)
                }

            Text(model.rotate)
                .frame(width: 460)
            Color(red: 0.82, green: 0.92, blue: 0.82)
                .frame(width: 260, height: 60)
                .onRotateGesture { value in
                    model.rotate = String(format: "rotate: %.3f rad", value.radians)
                    P65Diagnostics.write(model.rotate)
                } onEnded: { value in
                    model.rotate = String(format: "rotate ENDED: %.3f rad", value.radians)
                    P65Diagnostics.write(model.rotate)
                }
        }
        .padding(20)
        .onAppear {
            P65Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P65Diagnostics.renderComplete()
        }
    }

    func fmt(_ label: String, _ value: DragGestureValue) -> String {
        String(
            format: "%@: start (%.0f, %.0f) now (%.0f, %.0f) translation (%.0f, %.0f)",
            label,
            value.startLocation.x, value.startLocation.y,
            value.location.x, value.location.y,
            value.translation.x, value.translation.y
        )
    }
}
