// P107: GSAP's MotionPath as `.motionPath(_:progress:anchor:orientsAlongPath:)`
// -- a view drawn on a `Path` at a fraction of its length, turned to the path's
// direction, with `progress` tweened on the frame clock under an animation.
//
// The track is a line (20, 20) -> (220, 20), a clockwise half circle of radius
// 60 about (220, 80), and a line (220, 140) -> (20, 140): 400 + 60π = 588.50 pt,
// whose point and direction at any length have closed forms written out here.
// The dot is 20x20, anchored at its centre.
//   RUN     run = true under .animation(.linear(duration: 2), value: run): every
//           8 ms the drawn centre and rotation are compared with the closed
//           form at the progress drawn in the same frame, and the progress with
//           the clock. Pass: err <= 0.5 pt, angle err <= 1 degree, progress
//           within two frames (33 ms) of the line through the first moved
//           sample (an 8 ms timer reads a value the frame clock writes, and
//           the line is placed by one sample), DONE at (20, 140) facing
//           leading, frames >= 60.
//   BACK    run = false 1 s into a second run: the dot turns back from where
//           it is. Pass: the first progress drawn after the change is within
//           0.03 of the last before it, and it ends at (20, 20).
//   SET     progress set to 0.5 with no animation. Pass: one draw, at the
//           closed form's point for 0.5 (the top of the half circle's right).
//
// P107:GSAP 的 MotionPath,即 `.motionPath(_:progress:anchor:orientsAlongPath:)`——view 畫在 `Path` 上長度的某個
// 比例處、轉向路徑的方向，在動畫中 `progress` 於 frame clock 上補間。軌道與通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P107Log {
    /// Appends a line to p107-motion-path.log and stdout.
    /// 在 p107-motion-path.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P107] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p107-motion-path.log")
        guard let data = "P107 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P107App: App {
    var body: some Scene {
        WindowGroup("P107 motion path") {
            #hotReloadable {
                P107RootView()
            }
        }
        .defaultSize(width: 440, height: 560)
    }
}

/// The track, in the dot's coordinates. / 軌道，以圓點的座標表示。
let p107Track = Path()
    .move(to: SIMD2(20, 20))
    .addLine(to: SIMD2(220, 20))
    .addArc(center: SIMD2(220, 80), radius: 60, startAngle: 3 * .pi / 2, endAngle: .pi / 2, clockwise: true)
    .addLine(to: SIMD2(20, 140))

/// The track's point and direction (radians) at a fraction of its length,
/// in closed form. / 軌道在長度某個比例處的點與方向(弧度),以封閉形式表示。
func p107Expected(_ progress: Double) -> (position: SIMD2<Double>, direction: Double) {
    let arc = 60 * Double.pi
    let total = 400 + arc
    let s = min(max(progress, 0), 1) * total
    if s <= 200 {
        return (SIMD2(20 + s, 20), 0)
    } else if s <= 200 + arc {
        // From the top of the circle, clockwise. / 從圓的頂端順時針。
        let angle = -Double.pi / 2 + (s - 200) / 60
        return (SIMD2(220 + 60 * cos(angle), 80 + 60 * sin(angle)), angle + .pi / 2)
    } else {
        return (SIMD2(220 - (s - 200 - arc), 140), Double.pi)
    }
}

/// The track as a shape, stroked under the dot. / 軌道作為形狀，描在圓點下方。
struct P107TrackShape: Shape {
    func path(in bounds: Path.Rect) -> Path {
        p107Track
    }
}

@MainActor
final class P107Sampler {
    var timer: Timer?
    var samples: [(time: Double, progress: Double, centre: SIMD2<Double>, rotation: Double)] = []

    func start() {
        samples = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let effect = EffectAnimationDiagnostics.geometric["dot"],
                    let progress = MotionPathDiagnostics.samples["dot"]?.last?.progress
                else { return }
                // The centre: the anchor point (10, 10) moved by the effect.
                // 中心：錨點 (10, 10) 被效果移動之後。
                let centre = effect.translation + SIMD2(10, 10)
                self?.samples.append((ProcessInfo.processInfo.systemUptime, progress, centre, effect.rotation.radians))
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct P107RootView: View {
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

    @State var run = false
    @State var useSet = false
    @State var setProgress = 0.0
    @State var status = "steps: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P107: motion path")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            ZStack(alignment: .topLeading) {
                P107TrackShape()
                    .stroke(Color(red: 0.6, green: 0.6, blue: 0.6), style: StrokeStyle(width: 2))
                    .frame(width: 300, height: 170)
                Color(red: 0.9, green: 0.3, blue: 0.2)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Color(red: 1, green: 1, blue: 1)
                            .frame(width: 8, height: 4)
                            .offset(x: 6)
                    }
                    .motionPath(p107Track, progress: useSet ? setProgress : (run ? 1 : 0), orientsAlongPath: true)
                    ._effectDiagnosticsLabel("dot")
                    .animation(useSet ? nil : .linear(duration: 2), value: run)
            }
            .frame(width: 300, height: 170, alignment: .topLeading)
            Text(status)
                .font(.system(size: 11))
                .frame(width: 400, height: 220, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P107Log.write("backend \(String(describing: DefaultBackend.self))")
            P107Log.write("RENDER COMPLETE -- P107 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepsAfter) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P107Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { step() }
            }
        }
        let sampler = P107Sampler()
        func angleDifference(_ a: Double, _ b: Double) -> Double {
            var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            return abs(d)
        }

        func runStep() {
            MotionPathDiagnostics.clear()
            sampler.start()
            run = true
            after(2.4) {
                sampler.stop()
                var err = 0.0
                var angleErr = 0.0
                for sample in sampler.samples {
                    let expected = p107Expected(sample.progress)
                    let d = sample.centre - expected.position
                    err = max(err, (d.x * d.x + d.y * d.y).squareRoot())
                    angleErr = max(angleErr, angleDifference(sample.rotation, expected.direction) * 180 / .pi)
                }
                // Progress against the clock: the line through the first moved
                // sample, 0.5 per second. / 進度對照時鐘：通過第一個移動樣本、每秒 0.5 的直線。
                var clockErr = Double.nan
                if let moved = sampler.samples.first(where: { $0.progress > 0 }) {
                    let t0 = moved.time - moved.progress * 2
                    clockErr = sampler.samples.filter { $0.time >= moved.time && $0.progress < 1 }
                        .map { abs($0.progress - (($0.time - t0) / 2)) * 2000 }.max() ?? 0
                }
                let draws = MotionPathDiagnostics.samples["dot"]?.count ?? 0
                let end = sampler.samples.last
                record(String(format: "RUN DONE err=%.3f pt, angle err=%.3f deg over %ld samples; progress vs clock %.1f ms; %ld frames; end (%.2f, %.2f) facing %.1f deg", err, angleErr, sampler.samples.count, clockErr, draws, end?.centre.x ?? -1, end?.centre.y ?? -1, (end?.rotation ?? 0) * 180 / .pi))
                record(String(format: "RUN track length %.3f (closed form %.3f)", p107Track.length, 400 + 60 * Double.pi))
                after(0.3, back)
            }
        }

        func back() {
            // Back to the start without animation, then a second run turned back at 1 s.
            // 不帶動畫回到起點，然後第二次跑到 1 秒時折返。
            useSet = true
            setProgress = 0
            after(0.3) {
                useSet = false
                run = false
                after(0.3) {
                    MotionPathDiagnostics.clear()
                    run = true
                    after(1.0) {
                        let before = MotionPathDiagnostics.samples["dot"]?.last?.progress ?? -1
                        let count = MotionPathDiagnostics.samples["dot"]?.count ?? 0
                        run = false
                        after(2.4) {
                            let samples = MotionPathDiagnostics.samples["dot"] ?? []
                            let firstAfter = samples.count > count ? samples[count].progress : -1
                            let end = EffectAnimationDiagnostics.geometric["dot"].map { $0.translation + SIMD2(10, 10) }
                            record(String(format: "BACK at progress %.3f, first drawn after the change %.3f (jump %.3f); end (%.2f, %.2f)", before, firstAfter, abs(firstAfter - before), end?.x ?? -1, end?.y ?? -1))
                            after(0.3, set)
                        }
                    }
                }
            }
        }

        func set() {
            useSet = true
            setProgress = 0
            after(0.3) {
                MotionPathDiagnostics.clear()
                setProgress = 0.5
                after(0.4) {
                    let samples = MotionPathDiagnostics.samples["dot"] ?? []
                    let centre = EffectAnimationDiagnostics.geometric["dot"].map { $0.translation + SIMD2(10, 10) } ?? .zero
                    let expected = p107Expected(0.5).position
                    let d = centre - expected
                    record(String(format: "SET draws %ld at progress %.3f; centre (%.2f, %.2f), closed form (%.2f, %.2f), err=%.3f pt", samples.count, samples.last?.progress ?? -1, centre.x, centre.y, expected.x, expected.y, (d.x * d.x + d.y * d.y).squareRoot()))
                    P107Log.write("STEPS DONE")
                }
            }
        }

        runStep()
    }
}
