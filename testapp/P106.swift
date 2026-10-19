// P106: keyframes and phases -- SwiftUI's `keyframeAnimator` (trigger and
// repeating), `KeyframeTrack` with Linear/Spring/Cubic/Move keyframes, and
// `phaseAnimator` / `PhaseAnimator` (trigger and cycling).
//
// The app runs four steps by itself and logs each.
//   KEYS    keyframeAnimator(initialValue:trigger:) on a square: x Linear(200,
//           0.8 s, easeInOut) then Cubic(120) and Cubic(240) 0.6 s each; y
//           Spring(-40, 1 s, bouncy), Move(0), Linear(20, 1 s); scale
//           Linear(1.5, 1 s), Linear(1, 1 s). While it plays, every 8 ms the
//           offset and scale the content's modifiers drew are compared with
//           KeyframeTimeline.value(time:) at the animator's last two frames
//           (the redraw follows the frame that published it). Pass: worst err
//           <= 0.01 pt and scale err <= 0.0001 over >= 60 checks; the timeline
//           matches closed forms (x(0.4) = 100, y(1.0) = -40 * (1 - a damped
//           spring's remaining, written out here)); DONE at (240, 20, 1),
//           last timeline time 2.000; frames >= 60 in 2 s.
//   LOOP    keyframeAnimator(repeating: true), Linear(100, 0.5 s) then
//           Linear(0, 0.5 s), shown for 3.2 s. Pass: 3 wraps, err as above.
//   PHASE   phaseAnimator([0, 1, 2], trigger:) offset x = phase * 80, each step
//           .linear(duration: 0.5). Pass: phases 1, 2, 0 in that order, steps
//           0.48-0.6 s apart; at every 8 ms sample the drawn x within one
//           frame (17 ms at the step's speed, 160 or 320 pt/s) of the line
//           through the step's first moved sample -- the timer samples a value
//           the frame clock writes, so a frame of skew is the resolution.
//   CYCLE   PhaseAnimator([0, 1]) with .linear(duration: 0.3), shown 2 s.
//           Pass: 6-7 phase changes.
//
// P106:關鍵影格與階段——SwiftUI 的 `keyframeAnimator`(trigger 與 repeating)、帶 Linear/Spring/Cubic/Move
// 關鍵影格的 `KeyframeTrack`,以及 `phaseAnimator` / `PhaseAnimator`(trigger 與循環)。app 自己執行四個步驟
// 並記錄;通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P106Log {
    /// Appends a line to p106-keyframes.log and stdout.
    /// 在 p106-keyframes.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P106] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p106-keyframes.log")
        guard let data = "P106 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
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
struct P106App: App {
    var body: some Scene {
        WindowGroup("P106 keyframes") {
            #hotReloadable {
                P106RootView()
            }
        }
        .defaultSize(width: 480, height: 640)
    }
}

struct P106Values: Equatable {
    var x = 0.0
    var y = 0.0
    var scale = 1.0
}

/// The KEYS keyframes, shared by the view and the check.
/// KEYS 的關鍵影格，由 view 與檢查共用。
@KeyframesBuilder<P106Values>
func p106Keys(_ initial: P106Values) -> KeyframeList<P106Values> {
    KeyframeTrack(\.x) {
        LinearKeyframe(200, duration: 0.8, timingCurve: .easeInOut)
        CubicKeyframe(120, duration: 0.6)
        CubicKeyframe(240, duration: 0.6)
    }
    KeyframeTrack(\.y) {
        SpringKeyframe(-40, duration: 1, spring: .bouncy)
        MoveKeyframe(0)
        LinearKeyframe(20, duration: 1)
    }
    KeyframeTrack(\.scale) {
        LinearKeyframe(1.5, duration: 1)
        LinearKeyframe(1, duration: 1)
    }
}

@KeyframesBuilder<Double>
func p106Loop(_ initial: Double) -> KeyframeList<Double> {
    KeyframeTrack {
        LinearKeyframe(100, duration: 0.5)
        LinearKeyframe(0, duration: 0.5)
    }
}

/// Samples taken by a repeating 8 ms timer. / 由每 8 毫秒重複的計時器取得的樣本。
@MainActor
final class P106Sampler {
    var timer: Timer?
    var samples: [(time: Double, values: [Double])] = []

    func start(_ read: @escaping @MainActor () -> [Double]?) {
        samples = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let values = read() {
                    self?.samples.append((ProcessInfo.processInfo.systemUptime, values))
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct P106RootView: View {
    /// Seconds from the first appearance to the steps: 0.6, or `--steps-after N`.
    /// On iOS an action-file run attaches XCUITest about 2 s after launch, and its
    /// accessibility snapshot holds the main thread for most of a second; the iOS
    /// action file passes `--steps-after 6` (its `# app-args:` line) so the steps
    /// start after it.
    /// 從首次出現到開始步驟的秒數:0.6,或 `--steps-after N`。iOS 上動作檔執行會在啟動約 2 秒後附加 XCUITest,
    /// 它擷取無障礙樹時會佔住主執行緒將近一秒;iOS 動作檔以 `--steps-after 6`(它的 `# app-args:` 那一行)讓步驟在那之後才開始。
    static var stepsAfter: Double {
        let arguments = CommandLine.arguments
        if let at = arguments.firstIndex(of: "--steps-after"), at + 1 < arguments.count,
            let seconds = Double(arguments[at + 1])
        {
            return seconds
        }
        return 0.6
    }

    @State var keysKick = 0
    @State var loopOn = false
    @State var phaseKick = 0
    @State var cycleOn = false
    @State var status = "steps: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P106: keyframes and phases")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("keyframeAnimator(trigger:): x, y, scale").font(.system(size: 12))
            Color(red: 0.2, green: 0.5, blue: 0.9)
                .frame(width: 40, height: 40)
                .keyframeAnimator(initialValue: P106Values(), trigger: keysKick) { content, value in
                    content
                        .scaleEffect(value.scale)
                        ._effectDiagnosticsLabel("keysScale")
                        .offset(x: value.x, y: value.y)
                        ._effectDiagnosticsLabel("keysOffset")
                } keyframes: { initial in
                    p106Keys(initial)
                }
                .frame(width: 440, height: 90, alignment: .leading)

            Text("keyframeAnimator(repeating: true)").font(.system(size: 12))
            ZStack(alignment: .leading) {
                if loopOn {
                    KeyframeAnimator(initialValue: 0.0, repeating: true) { x in
                        Color(red: 0.9, green: 0.5, blue: 0.1)
                            .frame(width: 30, height: 30)
                            .offset(x: x)
                            ._effectDiagnosticsLabel("loop")
                    } keyframes: { initial in
                        p106Loop(initial)
                    }
                }
            }
            .frame(width: 440, height: 30, alignment: .leading)

            Text("phaseAnimator([0, 1, 2], trigger:)").font(.system(size: 12))
            Color(red: 0.3, green: 0.7, blue: 0.3)
                .frame(width: 30, height: 30)
                .phaseAnimator([0.0, 1.0, 2.0], trigger: phaseKick) { content, phase in
                    content
                        .offset(x: phase * 80)
                        ._effectDiagnosticsLabel("phase")
                } animation: { _ in
                    .linear(duration: 0.5)
                }
                .frame(width: 440, height: 30, alignment: .leading)

            Text("PhaseAnimator([0, 1]) cycling").font(.system(size: 12))
            ZStack(alignment: .leading) {
                if cycleOn {
                    PhaseAnimator([0.0, 1.0]) { phase in
                        Color(red: 0.7, green: 0.3, blue: 0.7)
                            .frame(width: 30, height: 30)
                            .offset(x: phase * 120)
                    } animation: { _ in
                        .linear(duration: 0.3)
                    }
                }
            }
            .frame(width: 440, height: 30, alignment: .leading)

            HStack(spacing: 6) {
                Button("Keys") { keysKick += 1 }
                Button("Phase") { phaseKick += 1 }
            }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 440, height: 200, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P106Log.write("backend \(String(describing: DefaultBackend.self))")
            P106Log.write("RENDER COMPLETE -- P106 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepsAfter) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    var uptime: Double { ProcessInfo.processInfo.systemUptime }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P106Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { step() }
            }
        }
        let sampler = P106Sampler()

        /// The drawn values against the timeline at the animator's last two
        /// frames; the smaller distance counts. / 畫出的值對照 animator 最後兩幀時 timeline 的值;取較小的距離。
        func check(_ drawn: [Double], against expected: (Double) -> [Double]) -> Double? {
            let frames = KeyframeAnimatorDiagnostics.samples.suffix(2)
            guard !frames.isEmpty else { return nil }
            return frames.map { frame in
                zip(drawn, expected(frame.time)).map { abs($0 - $1) }.max() ?? 0
            }.min()
        }

        func keys() {
            KeyframeAnimatorDiagnostics.clear()
            let timeline = KeyframeTimeline(initialValue: P106Values()) { p106Keys(P106Values()) }
            // The timeline against closed forms. / timeline 對照封閉形式。
            let x04 = timeline.value(time: 0.4).x
            let y10 = timeline.value(time: 0.999_999).y
            // A damped spring released from rest: bounce 0.3 is damping 0.7,
            // response 0.5 s. / 從靜止放開的阻尼彈簧:bounce 0.3 即阻尼 0.7,response 0.5 秒。
            let zeta = 0.7
            let w = 2 * Double.pi / 0.5
            let wd = w * (1 - zeta * zeta).squareRoot()
            let t = 0.999_999
            let remaining = exp(-zeta * w * t) * (cos(wd * t) + zeta * w / wd * sin(wd * t))
            let ySpring = -40 * (1 - remaining)
            record(String(format: "KEYS timeline x(0.4)=%.4f (closed form 100), y(1.0)=%.4f (closed form %.4f), duration %.2f", x04, y10, ySpring, timeline.duration))
            var offsetErr = 0.0
            var scaleErr = 0.0
            var checks = 0
            sampler.start {
                guard let offset = EffectAnimationDiagnostics.geometric["keysOffset"]?.translation,
                    let scale = EffectAnimationDiagnostics.geometric["keysScale"]?.scale.x,
                    !KeyframeAnimatorDiagnostics.samples.isEmpty
                else { return nil }
                if let err = check([offset.x, offset.y], against: { [timeline.value(time: $0).x, timeline.value(time: $0).y] }) {
                    offsetErr = max(offsetErr, err)
                }
                if let err = check([scale], against: { [timeline.value(time: $0).scale] }) {
                    scaleErr = max(scaleErr, err)
                }
                checks += 1
                return [offset.x, offset.y, scale]
            }
            keysKick += 1
            after(2.4) {
                sampler.stop()
                let frames = KeyframeAnimatorDiagnostics.samples
                let offset = EffectAnimationDiagnostics.geometric["keysOffset"]?.translation ?? .zero
                let scale = EffectAnimationDiagnostics.geometric["keysScale"]?.scale.x ?? 0
                record(String(format: "KEYS DONE err=%.3f pt, scale err=%.5f over %ld checks; end (%.2f, %.2f, %.3f); %ld frames, last time %.3f", offsetErr, scaleErr, checks, offset.x, offset.y, scale, frames.count, frames.last?.time ?? -1))
                after(0.3, loop)
            }
        }

        func loop() {
            KeyframeAnimatorDiagnostics.clear()
            let timeline = KeyframeTimeline(initialValue: 0.0) { p106Loop(0) }
            var err = 0.0
            var checks = 0
            sampler.start {
                guard let x = EffectAnimationDiagnostics.geometric["loop"]?.translation.x,
                    !KeyframeAnimatorDiagnostics.samples.isEmpty
                else { return nil }
                if let e = check([x], against: { [timeline.value(time: $0)] }) {
                    err = max(err, e)
                }
                checks += 1
                return [x]
            }
            loopOn = true
            after(3.2) {
                sampler.stop()
                let frames = KeyframeAnimatorDiagnostics.samples
                let wraps = zip(frames, frames.dropFirst()).filter { $1.time < $0.time }.count
                record(String(format: "LOOP DONE wraps %ld in %.2f s of frame clock; err=%.3f pt over %ld checks; %ld frames", wraps, frames.last?.elapsed ?? 0, err, checks, frames.count))
                loopOn = false
                after(0.3, phase)
            }
        }

        func phase() {
            PhaseAnimatorDiagnostics.clear()
            let start = uptime
            sampler.start {
                guard let x = EffectAnimationDiagnostics.geometric["phase"]?.translation.x else { return nil }
                return [x]
            }
            phaseKick += 1
            after(2.0) {
                sampler.stop()
                let changes = PhaseAnimatorDiagnostics.changes.filter { $0.uptime >= start }
                let order = changes.map { String($0.index) }.joined(separator: ",")
                let gaps = zip(changes, changes.dropFirst()).map { String(format: "%.3f", $1.uptime - $0.uptime) }.joined(separator: ", ")
                // Each step: 80 pt in 0.5 s, from the phase before to the next.
                // 每一步:0.5 秒走 80 pt,從前一個階段到下一個。
                var err = 0.0
                var errMs = 0.0
                var checked = 0
                let steps: [(from: Double, to: Double)] = [(0, 80), (80, 160), (160, 0)]
                for (index, change) in changes.enumerated() where index < steps.count {
                    let end = index + 1 < changes.count ? changes[index + 1].uptime : change.uptime + 0.6
                    let window = sampler.samples.filter { $0.time >= change.uptime && $0.time < end }
                    let step = steps[index]
                    let rate = (step.to - step.from) / 0.5
                    guard let moved = window.first(where: { abs($0.values[0] - step.from) > 0.01 }) else { continue }
                    let t0 = moved.time - (moved.values[0] - step.from) / rate
                    for sample in window where sample.time >= moved.time {
                        let progress = min(1, (sample.time - t0) / 0.5)
                        let expected = step.from + (step.to - step.from) * progress
                        err = max(err, abs(sample.values[0] - expected))
                        errMs = max(errMs, abs(sample.values[0] - expected) / abs(rate) * 1000)
                        checked += 1
                    }
                }
                let last = EffectAnimationDiagnostics.geometric["phase"]?.translation.x ?? -1
                record(String(format: "PHASE DONE order %@; steps %@ s apart; err=%.2f pt (%.1f ms at the step's speed) over %ld samples; end x %.1f", order, gaps, err, errMs, checked, last))
                after(0.3, cycle)
            }
        }

        func cycle() {
            PhaseAnimatorDiagnostics.clear()
            let start = uptime
            cycleOn = true
            after(2.0) {
                let changes = PhaseAnimatorDiagnostics.changes.filter { $0.uptime >= start }
                // The first entry is the first phase drawn, not a change.
                // 第一筆是畫出的第一個階段，不是改變。
                record("CYCLE DONE phase changes \(max(0, changes.count - 1)) in 2 s: \(changes.map { String($0.index) }.joined(separator: ","))")
                cycleOn = false
                P106Log.write("STEPS DONE")
            }
        }

        keys()
    }
}
