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

    /// `--restart`: measure, stop, measure again, and compare the two rates.
    ///
    /// **This asks whether `stopFrameClock` actually unsubscribes, which no
    /// other measurement here can tell you.** On WinUI the handler is a type
    /// property, so a leaked first subscription does not produce a second
    /// handler -- it makes the SAME handler run twice per composed frame, and
    /// the only visible effect is that the counted rate doubles.
    ///
    /// Both outcomes are informative, which is why it is worth running:
    ///
    /// - pass 2 at about the same rate as pass 1 -> the unsubscribe works
    /// - pass 2 at about DOUBLE -> the first subscription leaked, and since
    ///   `AnimationDriver` starts and stops the clock around every animation,
    ///   each animation would leak another
    ///
    /// A pass/fail on "does it still tick" cannot distinguish these: it ticks
    /// either way. The rate is the only thing that separates them.
    ///
    /// `--restart`:量一次、停掉、再量一次，然後比較兩個速率。
    ///
    /// **它問的是「`stopFrameClock` 是否真的解除了訂閱」——而此處其他任何量測都答不出這件事。**
    /// 在 WinUI 上，handler 是一個型別屬性，因此一個洩漏的第一次訂閱**不會**產生第二個 handler，
    /// 它會讓**同一個** handler 在每一個合成幀跑兩次；而唯一看得見的效果，就是數到的速率變成兩倍。
    ///
    /// 兩種結果都有意義，這正是它值得跑的原因:
    ///
    /// - 第二段與第一段速率相近 -> 取消訂閱有效
    /// - 第二段約為**兩倍** -> 第一次訂閱洩漏了;而由於 `AnimationDriver` 會在每個動畫前後啟停時鐘，
    ///   每一個動畫都會再洩漏一次
    ///
    /// 用「還會不會跳」來做 pass/fail 無法分辨這兩者:兩種情況都會跳。速率是唯一分得開它們的東西。
    static let isRestartProbe = CommandLine.arguments.contains("--restart")

    private var pass = 0
    private var firstPassRate: Double?
    private var firstPassMedian: Double?

    func start(backend: any BaseAppBackend) {
        guard let clock = backend as? any BackendFeatures.FrameClocks else {
            summary = "this backend does not conform to FrameClocks"
            P64Diagnostics.write(summary)
            return
        }
        started = true
        beginPass(clock: clock)
    }

    /// Everything a measurement window needs, in one place because the restart
    /// path needs all of it too.
    ///
    /// **It is one function because splitting it produced a broken instrument
    /// on the first run of `--restart`, and the log said so plainly.** The
    /// reset and the pass counter lived in `start(backend:)` while the restart
    /// called the private `start(clock:)` directly, so neither happened again:
    ///
    ///     PASS 1 TICKS 262 in 1.84s -> 141.9 Hz
    ///     PASS 1 TICKS 555 in 4.43s -> 124.9 Hz
    ///     PASS 1 TICKS 852 in 7.00s -> 121.6 Hz
    ///
    /// The label never left 1, so the `pass == 1` branch fired every time and
    /// restarted forever; `timestamps` never cleared, so the count accumulated
    /// and the rate drifted down as the span grew. **The apparent finding --
    /// "the rate falls after a restart" -- was entirely the instrument.** It is
    /// visible only because the run prints the tick COUNT and the SPAN next to
    /// the rate; a line that printed 124.9 Hz alone would have looked like a
    /// real and rather interesting result.
    ///
    /// 一段量測視窗所需要的一切,集中在一處——因為重啟路徑同樣需要它們全部。
    ///
    /// **它之所以是一個函式,是因為把它拆開之後,`--restart` 的第一次執行做出了一個壞掉的儀器,
    /// 而 log 把這件事講得很清楚。** 重置與段數計數住在 `start(backend:)` 裡,而重啟直接呼叫私有的
    /// `start(clock:)`,於是兩件事都沒有再發生一次:那個標籤始終停在 1,因此 `pass == 1` 的分支每次
    /// 都成立、永遠重啟下去;`timestamps` 從未清空,於是次數不斷累加、而速率隨著時距變長逐步下滑。
    /// **那個看似的發現——「重啟之後速率會下降」——完全來自儀器本身。** 它之所以看得出來,只因為每一行
    /// 都把 tick **次數**與**時距**印在速率旁邊;一行只印 124.9 Hz 的輸出,看起來會像一個真實而且
    /// 相當有趣的結果。
    private func beginPass<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        pass += 1
        timestamps.removeAll()
        ticks = 0
        P64Diagnostics.write("starting the frame clock (pass \(pass))")
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
            format:
                "PASS %d TICKS %d in %.2fs -> %.1f Hz; gap min %.1fms median %.1fms max %.1fms",
            pass,
            timestamps.count,
            span,
            rate,
            sorted.first ?? 0,
            sorted[sorted.count / 2],
            sorted.last ?? 0
        )
        P64Diagnostics.write(summary)

        if Self.isRestartProbe && pass == 1 {
            firstPassRate = rate
            firstPassMedian = sorted[sorted.count / 2]
            // Half a second of doing nothing between the two passes. It is not
            // a settling delay -- it is so that a leaked subscription has time
            // to be visible as ticks arriving while this app believes the clock
            // is stopped. Those ticks are counted: `stopFrameClock` clears the
            // handler, so anything still firing lands on nothing and the count
            // stays at zero unless the teardown is incomplete in a way that
            // leaves the handler installed.
            // 兩段之間有半秒什麼都不做。那不是為了等它穩定——那是為了讓「一個洩漏的訂閱」有時間以
            // 「在本 app 認為時鐘已停止時仍有 tick 抵達」的形式顯現出來。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    P64Diagnostics.write("restarting after a stop")
                    self.beginPass(clock: clock)
                }
            }
            return
        }

        if Self.isRestartProbe, pass == 2, let firstRate = firstPassRate,
            let firstMedian = firstPassMedian, firstMedian > 0
        {
            // **The verdict counts SUB-FRAME gaps, because that is the shape a
            // leak actually has.** Two live subscriptions call the same handler
            // -- it is a type property -- twice within one composed frame,
            // microseconds apart on a QueryPerformanceCounter clock. That does
            // not shift a rate or a median by some factor; it inserts gaps of
            // about ZERO between the members of each pair.
            //
            // Two weaker rules were tried on real runs first, and BOTH are
            // recorded because each looked reasonable until it was run:
            //
            //   rate ratio    one long stall while the window settles drags a
            //                 whole pass down. gtk4 gave 72.5 vs 88.3 Hz, ratio
            //                 1.22, from a single 450ms gap in pass 1.
            //   median ratio  survives that, but on GTK the median is BIMODAL:
            //                 7.0ms in one run and 13.9ms in the next, because
            //                 GTK produces a frame when something needs one and
            //                 the median measures how much this app asked to
            //                 redraw. Two runs gave 13.9/13.9 (ratio 1.00) and
            //                 7.0/13.9 (ratio 0.50) with nothing changed.
            //
            // A count of near-zero gaps has neither problem: it does not depend
            // on how many frames GTK chose to produce, only on whether any
            // frame was counted more than once.
            //
            // **判準改為計數「次於一幀」的間隔,因為那才是洩漏真正的形狀。** 兩個活著的訂閱會呼叫
            // **同一個** handler(它是型別屬性)——在同一個合成幀之內呼叫兩次,以
            // `QueryPerformanceCounter` 的時鐘來看只差微秒。那不會讓速率或中位數乘上某個倍數;
            // 它會在每一對之間插入**約為零**的間隔。
            //
            // 先在真實執行上試過兩個較弱的規則,兩個都記下來,因為它們在被跑之前都看起來很合理:
            //
            //   速率比值    視窗 settle 時的單次長停頓會把整段拉低。gtk4 得到 72.5 對 88.3 Hz、
            //               比值 1.22,而它來自 pass 1 中單獨一次 450ms 的間隔。
            //   中位數比值  它撐過了上述問題,但在 GTK 上中位數是**雙峰的**:一次執行是 7.0ms、
            //               下一次是 13.9ms——因為 GTK 有東西需要時才產生一幀,而中位數量到的是
            //               「這支 app 要求了多少重繪」。兩次執行分別給出 13.9/13.9(比值 1.00)
            //               與 7.0/13.9(比值 0.50),而中間什麼都沒改。
            //
            // 計數近乎零的間隔沒有這兩個問題:它不取決於 GTK 選擇產生了多少幀,只取決於「是否有
            // 任何一幀被計數了超過一次」。
            let subFrameGaps = gaps.filter { $0 < 1.0 }.count
            let median = sorted[sorted.count / 2]
            let verdict =
                subFrameGaps == 0
                ? "UNSUBSCRIBE OK"
                : "LEAKED -- \(subFrameGaps) ticks landed inside another tick's frame"
            // The two weaker numbers are still printed, and labelled as weak, so
            // that a reader can see WHY the verdict is not either of them.
            // 那兩個較弱的數字仍然印出來、並標明它們是弱的——好讓讀者看得出「判準為何不是它們」。
            P64Diagnostics.write(
                String(
                    format:
                        "RESTART sub-frame gaps in pass 2: %d of %d (the verdict); "
                        + "median %.1fms -> %.1fms, rate %.1f Hz -> %.1f Hz "
                        + "(both weak -- see the comment) -- %@",
                    subFrameGaps,
                    gaps.count,
                    firstMedian,
                    median,
                    firstRate,
                    rate,
                    verdict
                )
            )
        }
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
