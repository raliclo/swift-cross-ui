import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

// P64: does the frame clock (#28) actually tick, and at what rate?
//
// The number is checked: `ls testapp` gives P50..P63.
//
// **THIS DRIVES THE BACKEND REQUIREMENT DIRECTLY, because there is no animation
// system on top of it yet, and a requirement nobody calls is not evidence of
// anything.** Three days ago this tree separated "compiles" from "works" twice
// in two days; a `FrameClocks` conformance that had never been started would be
// exactly that shape again.
//
// What it asserts is a RATE, not a tick. A clock that fired once and stopped
// would satisfy "did the handler run"; a clock that fired at 5 Hz would satisfy
// it too, and would be useless for an animation. So the app counts ticks over a
// fixed wall-clock window and prints the measured rate, and prints the gaps
// between ticks as well -- a clock that delivered 120 ticks in bursts of 20 has
// the right average and is not a frame clock.
//
// P64:frame clock(#28)真的會跳嗎?以及,以多快的速率?
//
// 編號是查過的:`ls testapp` 給出 P50..P63。
//
// **這支 app 直接驅動那個 backend requirement——因為它上面還沒有動畫系統，而一個沒有人呼叫的
// requirement 不構成任何證據。** 三天前這棵樹在兩天內兩次把「編得過」與「會動」分開;一個從未被啟動
// 過的 `FrameClocks` conformance，正是同一個形狀。
//
// 它斷言的是**速率**，不是「有沒有跳」。一個只跳一次就停的時鐘也能滿足「handler 有沒有跑過」;一個以
// 5 Hz 跳動的時鐘同樣滿足它，而那對動畫毫無用處。因此本 app 在一個固定的牆鐘視窗內計數，印出量到的
// 速率，並且**也印出每兩次跳動之間的間隔**——一個「以 20 次為一叢、共送出 120 次」的時鐘平均值是對的，
// 而它不是一個 frame clock。

enum P64Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P64] \(message)")

        guard let data = "P64 \(Date()) \(message)\n".data(using: .utf8) else { return }
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
            .appendingPathComponent("p64-debug-events.log")
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
}

@main
@HotReloadable
struct P64App: App {
    var body: some Scene {
        WindowGroup("P64 frame clock") {
            #hotReloadable {
                P64RootView()
            }
        }
        .defaultSize(width: 560, height: 340)
    }
}

@MainActor
final class P64Model: SwiftCrossUI.ObservableObject {
    /// One model for the process, not one per view construction.
    ///
    /// `@ObservedObject var model = P64Model()` builds a NEW model every time
    /// the view struct is constructed, and a view struct is constructed on
    /// every update. The first run of this app started the clock on a model
    /// that was then dropped: the `[weak self]` in the two-second callback
    /// found nothing, and the app printed "starting the frame clock" and
    /// nothing else -- which reads exactly like a clock that never ticked.
    ///
    /// 一個行程一個 model，而不是每次建構 view 就一個。
    ///
    /// `@ObservedObject var model = P64Model()` 會在每次建構那個 view struct 時建立一個**新的**
    /// model，而 view struct 在每一次更新時都會被建構。本 app 的第一次執行，把時鐘啟動在一個隨即
    /// 被丟棄的 model 上:兩秒後那個 callback 裡的 `[weak self]` 找不到任何東西，於是這支 app 印出了
    /// 「starting the frame clock」然後就沒有下文——而那讀起來，與「一個從未跳動過的時鐘」一模一樣。
    static let shared = P64Model()

    @SwiftCrossUI.Published var ticks = 0
    @SwiftCrossUI.Published var summary = "not started"
    @SwiftCrossUI.Published var started = false

    var timestamps: [Double] = []

    func start(backend: any BaseAppBackend) {
        guard let clock = backend as? any BackendFeatures.FrameClocks else {
            summary = "this backend does not conform to FrameClocks"
            P64Diagnostics.write(summary)
            return
        }
        started = true
        timestamps.removeAll()
        P64Diagnostics.write("starting the frame clock")
        start(clock: clock)

        // Two seconds is long enough for a rate to mean something and short
        // enough that the harness's default showtime covers it.
        // 兩秒:長到足以讓一個速率有意義，短到讓 harness 的預設 showtime 涵蓋得住。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.finish(clock: clock) }
        }
    }

    private func start<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        clock.startFrameClock { [weak self] timestamp in
            guard let self else { return }
            self.ticks += 1
            self.timestamps.append(timestamp)
        }
    }

    private func finish<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        clock.stopFrameClock()
        guard timestamps.count >= 2 else {
            summary = "TICKS \(ticks) -- too few to measure a rate"
            P64Diagnostics.write(summary)
            return
        }
        let span = timestamps.last! - timestamps.first!
        let rate = Double(timestamps.count - 1) / span
        var gaps: [Double] = []
        for index in 1..<timestamps.count {
            gaps.append((timestamps[index] - timestamps[index - 1]) * 1000)
        }
        let sorted = gaps.sorted()
        summary = String(
            format: "TICKS %d in %.2fs -> %.1f Hz; gap min %.1fms median %.1fms max %.1fms",
            timestamps.count,
            span,
            rate,
            sorted.first ?? 0,
            sorted[sorted.count / 2],
            sorted.last ?? 0
        )
        P64Diagnostics.write(summary)
        P64Diagnostics.write("RENDER COMPLETE -- P64 measured the frame clock")
    }
}

struct P64RootView: View {
    @ObservedObject var model = P64Model.shared
    @Environment(\.backend) var backend

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P64: the frame clock (#28)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("ticks so far: \(model.ticks)")
            Text(model.summary)

            Text("Expected: a rate near the display's refresh, and gaps that")
            Text("cluster around one frame rather than arriving in bursts.")
            Text("預期:速率接近顯示器的更新率，而各次間隔集中在「一幀」附近，而不是成叢抵達。")
        }
        .padding(20)
        .onAppear {
            P64Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            if !model.started {
                // The RUNNING backend, through the Backends SPI.
                //
                // The first version built a fresh `DefaultBackend()` because
                // this value was internal. That measures the right clock on
                // every backend written so far -- their clock state is
                // per-process -- but it is a guess about which state is which,
                // and the SPI removes the guess.
                //
                // 透過 Backends SPI 取得**執行中**的那個 backend。
                //
                // 第一版之所以自行建構一個 `DefaultBackend()`，是因為這個值當時是 internal。在目前
                // 所寫的每一個 backend 上，它量到的都是對的時鐘(它們的時鐘狀態是逐行程的)——但那是
                // 一個「哪些狀態屬於哪一邊」的猜測，而 SPI 讓那個猜測不必存在。
                model.start(backend: backend)
            }
        }
    }
}
