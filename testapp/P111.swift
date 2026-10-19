// P111: keyframe velocities -- `SpringKeyframe(startVelocity:)`,
// `CubicKeyframe(startVelocity:endVelocity:)`, and the velocity one keyframe
// hands to the next (linear into spring, spring into cubic), as SwiftUI's
// keyframes use them.
//
// The keyframes, on a square's offset under keyframeAnimator(trigger:):
//   x  Linear(150, 0.5 s), then Spring(250, 0.6 s, bouncy) with no start
//      velocity (it takes the linear keyframe's 300 pt/s), then Cubic(100,
//      0.6 s, endVelocity: 0) (its start velocity is the spring's at its end).
//   y  Cubic(60, 0.8 s, startVelocity: 400, endVelocity: -200), then
//      Spring(0, 0.8 s, snappy, startVelocity: 300).
//
// The app runs two steps by itself and logs each. "err" is the largest
// distance from the closed form; slopes are KeyframeTimeline differences over
// 1e-6 s.
//   TIMELINE  The timeline against closed forms written out here: x slopes 300
//             on both sides of t = 0.5, x(0.8) = 250 - 100 r(0.3) + 300 g(0.3)
//             for the bouncy spring (damping 0.7, response 0.5 s; r the
//             distance left from rest, g the displacement per unit start
//             velocity), x slope equal on both sides of t = 1.1 and 0 at 1.7;
//             y slope 400 at 0, y(0.4) the Hermite cubic, y slope -200 before
//             0.8 and 300 after it, y(1.2) = 60 r(0.4) + 300 g(0.4) for the
//             snappy spring (damping 0.85). Pass: value err <= 1e-6 pt, slope
//             err <= 0.05 pt/s.
//   DRAW      The animator plays; every 8 ms the drawn offset against
//             KeyframeTimeline.value(time:) at the animator's last two frames
//             (as P106 checks it). Pass: err <= 0.01 pt over >= 60 checks, DONE
//             at the timeline's end value (x 100, y where the snappy spring is after 0.8 s).
//
// P111:關鍵影格的速度——`SpringKeyframe(startVelocity:)`、`CubicKeyframe(startVelocity:endVelocity:)`,以及一個
// 關鍵影格交給下一個的速度(線性進入彈簧、彈簧進入三次曲線),與 SwiftUI 的關鍵影格相同。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P111Log {
    /// Appends a line to p111-keyframe-velocity.log and stdout.
    /// 在 p111-keyframe-velocity.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P111] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p111-keyframe-velocity.log")
        guard let data = "P111 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P111App: App {
    var body: some Scene {
        WindowGroup("P111 keyframe velocity") {
            #hotReloadable {
                P111RootView()
            }
        }
        .defaultSize(width: 480, height: 520)
    }
}

struct P111Values: Equatable {
    var x = 0.0
    var y = 0.0
}

/// The keyframes, shared by the view and the checks.
/// 關鍵影格，由 view 與檢查共用。
@KeyframesBuilder<P111Values>
func p111Keys(_ initial: P111Values) -> KeyframeList<P111Values> {
    KeyframeTrack(\.x) {
        LinearKeyframe(150, duration: 0.5)
        SpringKeyframe(250, duration: 0.6, spring: .bouncy)
        CubicKeyframe(100, duration: 0.6, endVelocity: 0)
    }
    KeyframeTrack(\.y) {
        CubicKeyframe(60, duration: 0.8, startVelocity: 400, endVelocity: -200)
        SpringKeyframe(0, duration: 0.8, spring: .snappy, startVelocity: 300)
    }
}

/// A spring's distance left from rest, r, and displacement per unit start
/// velocity, g, under-damped, written out. / 欠阻尼彈簧從靜止起的剩餘距離 r 與每單位起始速度的位移 g,寫出來。
func p111Spring(damping zeta: Double, response: Double, at t: Double) -> (r: Double, g: Double) {
    let w = 2 * Double.pi / response
    let wd = w * (1 - zeta * zeta).squareRoot()
    let decay = exp(-zeta * w * t)
    return (decay * (cos(wd * t) + zeta * w / wd * sin(wd * t)), decay * sin(wd * t) / wd)
}

/// Samples taken by a repeating 8 ms timer. / 由每 8 毫秒重複的計時器取得的樣本。
@MainActor
final class P111Sampler {
    var timer: Timer?

    func start(_ read: @escaping @MainActor () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            MainActor.assumeIsolated { read() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct P111RootView: View {
    /// Seconds from the first appearance to the steps: 0.6, or `--steps-after N`
    /// (an iOS action-file run waits for XCUITest to attach, as P106 does).
    /// 從首次出現到開始步驟的秒數:0.6,或 `--steps-after N`(iOS 動作檔執行時等 XCUITest 附加，與 P106 相同)。
    static var stepsAfter: Double {
        let arguments = CommandLine.arguments
        if let at = arguments.firstIndex(of: "--steps-after"), at + 1 < arguments.count,
            let seconds = Double(arguments[at + 1])
        {
            return seconds
        }
        return 0.6
    }

    @State var kick = 0
    @State var status = "steps: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P111: keyframe velocities")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Color(red: 0.2, green: 0.5, blue: 0.9)
                .frame(width: 30, height: 30)
                .keyframeAnimator(initialValue: P111Values(), trigger: kick) { content, value in
                    content
                        .offset(x: value.x, y: value.y)
                        ._effectDiagnosticsLabel("p111Offset")
                } keyframes: { initial in
                    p111Keys(initial)
                }
                .frame(width: 440, height: 130, alignment: .topLeading)
            Button("Play") { kick += 1 }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 440, height: 220, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P111Log.write("backend \(String(describing: DefaultBackend.self))")
            P111Log.write("RENDER COMPLETE -- P111 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepsAfter) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P111Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        let timeline = KeyframeTimeline(initialValue: P111Values()) { p111Keys(P111Values()) }

        func timelineStep() {
            let x = { timeline.value(time: $0).x }
            let y = { timeline.value(time: $0).y }
            let h = 1e-6
            func left(_ f: (Double) -> Double, _ t: Double) -> Double { (f(t) - f(t - h)) / h }
            func right(_ f: (Double) -> Double, _ t: Double) -> Double { (f(t + h) - f(t)) / h }

            let bouncy = p111Spring(damping: 0.7, response: 0.5, at: 0.3)
            let snappy = p111Spring(damping: 0.85, response: 0.5, at: 0.4)
            let s = 0.5
            let hermite =
                (-2 * s * s * s + 3 * s * s) * 60 + (s * s * s - 2 * s * s + s) * 0.8 * 400
                + (s * s * s - s * s) * 0.8 * -200
            let values: [(String, Double, Double)] = [
                ("x(0.8)", x(0.8), 250 - 100 * bouncy.r + 300 * bouncy.g),
                ("y(0.4)", y(0.4), hermite),
                ("y(1.2)", y(1.2), 60 * snappy.r + 300 * snappy.g),
            ]
            let slopes: [(String, Double, Double)] = [
                ("x' before 0.5", left(x, 0.5), 300),
                ("x' after 0.5", right(x, 0.5), 300),
                ("x' after 1.1 vs before", right(x, 1.1), left(x, 1.1)),
                ("x' before 1.7", left(x, 1.7), 0),
                ("y' at 0", right(y, 0), 400),
                ("y' before 0.8", left(y, 0.8), -200),
                ("y' after 0.8", right(y, 0.8), 300),
            ]
            let valueErr = values.map { abs($0.1 - $0.2) }.max() ?? .infinity
            let slopeErr = slopes.map { abs($0.1 - $0.2) }.max() ?? .infinity
            let detail = (values + slopes).map { String(format: "%@ %.3f (want %.3f)", $0.0, $0.1, $0.2) }
                .joined(separator: ", ")
            record(String(format: "TIMELINE value err %.2e pt, slope err %.4f pt/s; ", valueErr, slopeErr) + detail)
            draw()
        }

        func draw() {
            KeyframeAnimatorDiagnostics.clear()
            let sampler = P111Sampler()
            var err = 0.0
            var checks = 0
            sampler.start {
                guard let offset = EffectAnimationDiagnostics.geometric["p111Offset"]?.translation else { return }
                let frames = KeyframeAnimatorDiagnostics.samples.suffix(2)
                guard !frames.isEmpty else { return }
                let distance = frames.map { frame in
                    let value = timeline.value(time: frame.time)
                    return max(abs(offset.x - value.x), abs(offset.y - value.y))
                }.min() ?? 0
                err = max(err, distance)
                checks += 1
            }
            kick += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                MainActor.assumeIsolated {
                    sampler.stop()
                    let offset = EffectAnimationDiagnostics.geometric["p111Offset"]?.translation ?? .zero
                    let frames = KeyframeAnimatorDiagnostics.samples
                    record(
                        String(
                            format: "DRAW DONE err=%.4f pt over %ld checks; end (%.2f, %.2f), timeline end (%.2f, %.2f); %ld frames, last time %.3f",
                            err, checks, offset.x, offset.y, timeline.value(time: timeline.duration).x,
                            timeline.value(time: timeline.duration).y, frames.count, frames.last?.time ?? -1
                        )
                    )
                    P111Log.write("STEPS DONE")
                }
            }
        }

        timelineStep()
    }
}
