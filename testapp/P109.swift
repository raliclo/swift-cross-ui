// P109: text colours and gradients under an animation -- `.foregroundColor`
// and `.foregroundStyle` on `Text`, and `LinearGradient`, `RadialGradient` and
// `AngularGradient` (stop colours and locations, points, radii, angles) tween
// inside `withAnimation`, each frame handed to the backend's text or gradient
// call with no body evaluation.
//
// The app runs two steps by itself and logs each. Values are what the views
// handed the backend (LayoutAnimationDiagnostics), colour channels in 0-255.
//   WITH   withAnimation(.linear(duration: 1)) { on = true }. At p >= 0.5
//          (onUpdate) each is compared with its value at p written out here:
//          TEXT and STYLE blue -> red; LINEAR [blue@0, red@1] top->bottom to
//          [red@0.2, blue@0.8] leading->trailing (same stops: each stop moves);
//          RADIAL [red, blue] r 20 -> [red, green, blue] r 60, centre
//          (0.5,0.5) -> (0.3,0.3) (different stops: the middle sample goes
//          from the blend at 0.5, (128,0,128), to green); ANGULAR [blue, red]
//          to [red, blue], start angle 0 -> 90 degrees. Pass: colour err <= 3,
//          location and point err <= 0.01, radius err <= 0.5 pt, angle err <=
//          0.5 degree; root body evaluations 1 by the middle (the one that
//          read `on = true`; the status line written there adds one more);
//          DONE at the end values.
//   JUMP   on = false with no animation. Pass: one sample each, at the start
//          values.
//
// P109:動畫中的文字顏色與漸層——`Text` 上的 `.foregroundColor` 與 `.foregroundStyle`,以及 `LinearGradient`、
// `RadialGradient` 與 `AngularGradient`(色標顏色與位置、點、半徑、角度)在 `withAnimation` 之內補間，每一幀交給
// backend 的文字或漸層呼叫，不求值 body。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P109Log {
    /// Appends a line to p109-style-animation.log and stdout.
    /// 在 p109-style-animation.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P109] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p109-style-animation.log")
        guard let data = "P109 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P109App: App {
    var body: some Scene {
        WindowGroup("P109 style animation") {
            #hotReloadable {
                P109RootView()
            }
        }
        .defaultSize(width: 460, height: 600)
    }
}

@MainActor
enum P109Counter {
    static var bodies = 0
}

@MainActor
final class P109Probe: @unchecked Sendable {
    var midLogged = false
    var bodiesAtStart = 0
    var started = 0.0
}

let p109Red = Color(red: 1, green: 0, blue: 0)
let p109Blue = Color(red: 0, green: 0, blue: 1)
let p109Green = Color(red: 0, green: 1, blue: 0)

struct P109RootView: View {
    @State var on = false
    @State var status = "steps: running"

    var body: some View {
        let _ = P109Counter.bodies += 1
        VStack(alignment: .leading, spacing: 8) {
            Text("P109: text colour and gradients")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            HStack(spacing: 16) {
                Text("foregroundColor")
                    .font(.system(size: 18))
                    .foregroundColor(on ? p109Red : p109Blue)
                    ._effectDiagnosticsLabel("text")
                Text("foregroundStyle")
                    .font(.system(size: 18))
                    .foregroundStyle(on ? p109Red : p109Blue)
                    ._effectDiagnosticsLabel("style")
            }
            HStack(spacing: 10) {
                LinearGradient(
                    stops: on
                        ? [.init(color: p109Red, location: 0.2), .init(color: p109Blue, location: 0.8)]
                        : [.init(color: p109Blue, location: 0), .init(color: p109Red, location: 1)],
                    startPoint: on ? .leading : .top,
                    endPoint: on ? .trailing : .bottom
                )
                .frame(width: 120, height: 80)
                ._effectDiagnosticsLabel("linear")
                RadialGradient(
                    colors: on ? [p109Red, p109Green, p109Blue] : [p109Red, p109Blue],
                    center: on ? UnitPoint(x: 0.3, y: 0.3) : .center,
                    startRadius: 0,
                    endRadius: on ? 60 : 20
                )
                .frame(width: 120, height: 80)
                ._effectDiagnosticsLabel("radial")
                AngularGradient(
                    colors: on ? [p109Red, p109Blue] : [p109Blue, p109Red],
                    center: .center,
                    angle: on ? .degrees(90) : .zero
                )
                .frame(width: 120, height: 80)
                ._effectDiagnosticsLabel("angular")
            }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 420, height: 260, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P109Log.write("backend \(String(describing: DefaultBackend.self))")
            P109Log.write("RENDER COMPLETE -- P109 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    static func last(_ key: String) -> [Double]? {
        LayoutAnimationDiagnostics.samples[key]?.last?.values
    }

    /// Expected values at `p`, in the order the views report them.
    /// 在 `p` 時的預期值，依 view 回報的順序。
    static func expected(_ p: Double) -> [String: [Double]] {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        let redToBlue = [mix(1, 0), 0, mix(0, 1)]
        let blueToRed = [mix(0, 1), 0, mix(1, 0)]
        return [
            "text/text": blueToRed + [1],
            "style/text": blueToRed + [1],
            // [loc, r, g, b, a] per stop, then start and end points.
            "linear/gradient": [mix(0, 0.2)] + blueToRed + [1] + [mix(1, 0.8)] + redToBlue + [1]
                + [mix(0.5, 0), mix(0, 0.5), mix(0.5, 1), mix(1, 0.5)],
            // Stops at 0, 0.5, 1: red, blend -> green, blue; centre; radii.
            "radial/gradient": [0, 1, 0, 0, 1] + [0.5, mix(0.5, 0), mix(0, 1), mix(0.5, 0), 1] + [1, 0, 0, 1, 1]
                + [mix(0.5, 0.3), mix(0.5, 0.3), 0, mix(20, 60)],
            "angular/gradient": [0] + blueToRed + [1] + [1] + redToBlue + [1] + [0.5, 0.5, mix(0, Double.pi / 2)],
        ]
    }

    /// The worst distance per kind of value between what was drawn and `expected`.
    /// 畫出的值與 `expected` 之間、每一類值的最大距離。
    static func errors(_ p: Double) -> String {
        var parts: [String] = []
        for key in ["text/text", "style/text", "linear/gradient", "radial/gradient", "angular/gradient"] {
            guard let drawn = last(key), let want = expected(p)[key], drawn.count == want.count else {
                parts.append("\(key) count \(last(key)?.count ?? 0)")
                continue
            }
            var colour = 0.0
            var other = 0.0
            for (index, (d, w)) in zip(drawn, want).enumerated() {
                let isColour: Bool
                if key.hasSuffix("/text") {
                    isColour = true
                } else {
                    let stopValues = drawn.count - (key == "linear/gradient" ? 4 : (key == "radial/gradient" ? 4 : 3))
                    isColour = index < stopValues && index % 5 != 0
                }
                if isColour {
                    colour = max(colour, abs(d - w) * 255)
                } else {
                    other = max(other, abs(d - w))
                }
            }
            parts.append(String(format: "%@ colour %.1f other %.3f", key, colour, other))
        }
        return parts.joined(separator: "; ")
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P109Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }

        func with() {
            LayoutAnimationDiagnostics.clear()
            let probe = P109Probe()
            probe.bodiesAtStart = P109Counter.bodies
            probe.started = ProcessInfo.processInfo.systemUptime
            let animation = Animation.linear(duration: 1).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                // Counted before this line rewrites the status text (which re-renders).
                // 在這一行改寫狀態文字(會重新算繪)之前計數。
                let bodies = P109Counter.bodies - probe.bodiesAtStart
                record(String(format: "WITH MID p=%.3f ", p) + Self.errors(p) + "; body evaluations so far \(bodies)")
            }
            withAnimation(animation) {
                on = true
            } completion: {
                let frames = ["text/text", "linear/gradient", "radial/gradient", "angular/gradient"].map {
                    "\($0) \(LayoutAnimationDiagnostics.samples[$0]?.count ?? 0)"
                }.joined(separator: ", ")
                record(
                    String(format: "WITH DONE at %.2f s; ", ProcessInfo.processInfo.systemUptime - probe.started)
                        + Self.errors(1)
                        + "; frames \(frames); body evaluations \(P109Counter.bodies - probe.bodiesAtStart)"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { jump() }
                }
            }
        }

        func jump() {
            LayoutAnimationDiagnostics.clear()
            on = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated {
                    let counts = ["text/text", "linear/gradient", "radial/gradient", "angular/gradient"].map {
                        "\($0) \(LayoutAnimationDiagnostics.samples[$0]?.count ?? 0)"
                    }.joined(separator: ", ")
                    let text = Self.last("text/text").map { $0.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "none"
                    record("JUMP samples \(counts); text colour (\(text))")
                    P109Log.write("STEPS DONE")
                }
            }
        }

        with()
    }
}
