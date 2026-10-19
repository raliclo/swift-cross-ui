// P110: gradients that tween -- a gradient as a `Text`'s `.foregroundStyle(_:)`,
// gradient fills and strokes of shapes (`.fill(LinearGradient(...))`,
// `.stroke(gradient, style:)`, an unfilled shape under `.foregroundStyle`), and a
// flat colour turning into a gradient. Each frame of a tween is handed to the
// backend's `updateTextView` (with `EnvironmentValues.textGradient`) or
// `renderPath` (on GtkBackend, new GSK nodes), with no body evaluation.
//
// The app runs four steps by itself and logs each. Values are what the views
// handed the backend (LayoutAnimationDiagnostics): per stop location, red,
// green, blue, opacity (colours 0-1, errors reported in 0-255), then the points
// (unit x, y) and radii. "err" is the largest distance from the closed form.
//   WITH   withAnimation(.linear(duration: 1)) { on = true }. At p >= 0.5
//          (onUpdate) each value against its closed form at p:
//          tg  Text, linear [blue, green] top->bottom to [red, blue]
//              leading->trailing (stops and points move);
//          tc  Text, flat blue to linear [red, green] leading->trailing (the
//              gradient with both stops blue, moving to red and green);
//          lin Circle fill, linear [green, blue] top->bottom to [blue, red]
//              leading->trailing;
//          rad RoundedRectangle fill, flat green to radial [red, blue] centre
//              (0.3, 0.3), radius 0 to 0.7 (of the shorter side);
//          str Circle stroke 8 pt, linear [red, blue] top->bottom to [blue,
//              red] leading->trailing;
//          fg  unfilled Capsule under .foregroundStyle, linear [blue, red]
//              top->bottom to [green, blue] leading->trailing.
//          Pass: colour err <= 3, point and radius err <= 0.01; DONE at the end
//          values (err 0 at p = 1).
//   VALUE  flip = true with no withAnimation, under .animation(.linear(duration:
//          0.8), value: flip): tv Text [red, green] to [green, red], rv
//          Rectangle fill [blue, red] to [red, blue]. The frame nearest the
//          middle: p read from its first stop, every value against the closed
//          form at that p, and p against the clock. Pass: err <= 3, p within
//          0.05 of the clock, more than 30 frames.
//   JUMP   on = false with no animation. Pass: one sample per view, at the
//          start values (err 0).
//   FINAL  on = true with no animation, so the final capture shows the "on"
//          gradients: tg red to blue and tc red to green across the text,
//          the shapes in their gradients.
//
// P110:會補間的漸層——作為 `Text` 的 `.foregroundStyle(_:)` 的漸層、形狀的漸層填色與筆畫(`.fill(LinearGradient(...))`、
// `.stroke(gradient, style:)`、在 `.foregroundStyle` 之下沒有填色的形狀),以及平面色變成漸層。補間的每一幀交給
// backend 的 `updateTextView`(帶 `EnvironmentValues.textGradient`)或 `renderPath`(在 GtkBackend 上即新的 GSK
// 節點),不求值 body。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P110Log {
    /// Appends a line to p110-gradient-tween.log and stdout.
    /// 在 p110-gradient-tween.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P110] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p110-gradient-tween.log")
        guard let data = "P110 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P110App: App {
    var body: some Scene {
        WindowGroup("P110 gradient tween") {
            #hotReloadable {
                P110RootView()
            }
        }
        .defaultSize(width: 520, height: 720)
    }
}

/// Any shape style behind one type, so a view can switch between a colour and a
/// gradient. / 把任何 shape style 放在同一個型別後面，讓 view 能在顏色與漸層之間切換。
struct P110Style: ShapeStyle {
    var base: any ShapeStyle

    func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle {
        base._resolve(in: environment)
    }
}

@MainActor
final class P110Probe: @unchecked Sendable {
    var midLogged = false
    var started = 0.0
}

let p110Red = Color(red: 1, green: 0, blue: 0)
let p110Green = Color(red: 0, green: 1, blue: 0)
let p110Blue = Color(red: 0, green: 0, blue: 1)

@MainActor func p110Linear(_ a: Color, _ b: Color, _ horizontal: Bool) -> LinearGradient {
    LinearGradient(
        colors: [a, b],
        startPoint: horizontal ? .leading : .top,
        endPoint: horizontal ? .trailing : .bottom
    )
}

struct P110RootView: View {
    @State var on = false
    @State var flip = false
    @State var status = "steps: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P110: gradients that tween")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            HStack(spacing: 16) {
                Text("GRADIENT")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(on ? p110Linear(p110Red, p110Blue, true) : p110Linear(p110Blue, p110Green, false))
                    ._effectDiagnosticsLabel("tg")
                Text("COLOUR")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(P110Style(base: on ? p110Linear(p110Red, p110Green, true) : p110Blue))
                    ._effectDiagnosticsLabel("tc")
            }
            HStack(spacing: 12) {
                Circle()
                    .fill(on ? p110Linear(p110Blue, p110Red, true) : p110Linear(p110Green, p110Blue, false))
                    .frame(width: 80, height: 80)
                    ._effectDiagnosticsLabel("lin")
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        P110Style(
                            base: on
                                ? RadialGradient(
                                    colors: [p110Red, p110Blue], center: UnitPoint(x: 0.3, y: 0.3),
                                    startRadius: 0, endRadius: 0.7
                                )
                                : p110Green
                        )
                    )
                    .frame(width: 100, height: 80)
                    ._effectDiagnosticsLabel("rad")
                Circle()
                    .stroke(
                        on ? p110Linear(p110Blue, p110Red, true) : p110Linear(p110Red, p110Blue, false),
                        style: StrokeStyle(width: 8)
                    )
                    .frame(width: 80, height: 80)
                    ._effectDiagnosticsLabel("str")
                Capsule()
                    .frame(width: 100, height: 50)
                    .foregroundStyle(on ? p110Linear(p110Green, p110Blue, true) : p110Linear(p110Blue, p110Red, false))
                    ._effectDiagnosticsLabel("fg")
            }
            HStack(spacing: 16) {
                Text("VALUE")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(flip ? p110Linear(p110Green, p110Red, true) : p110Linear(p110Red, p110Green, true))
                    ._effectDiagnosticsLabel("tv")
                Rectangle()
                    .fill(flip ? p110Linear(p110Red, p110Blue, false) : p110Linear(p110Blue, p110Red, false))
                    .frame(width: 100, height: 40)
                    ._effectDiagnosticsLabel("rv")
            }
            .animation(.linear(duration: 0.8), value: flip)
            Text(status)
                .font(.system(size: 11))
                .frame(width: 480, height: 300, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P110Log.write("backend \(String(describing: DefaultBackend.self))")
            P110Log.write("RENDER COMPLETE -- P110 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    static func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }

    /// A stop's values: location, then red, green, blue, opacity.
    /// 一個色標的值：位置，然後紅、綠、藍、不透明度。
    static func stop(_ location: Double, _ from: [Double], _ to: [Double], _ p: Double) -> [Double] {
        [location] + zip(from, to).map { mix($0, $1, p) } + [1]
    }

    static let red = [1.0, 0, 0]
    static let green = [0.0, 1, 0]
    static let blue = [0.0, 0, 1]
    /// top -> bottom to leading -> trailing. / 由上而下變成由前而後。
    static func points(_ p: Double) -> [Double] {
        [mix(0.5, 0, p), mix(0, 0.5, p), mix(0.5, 1, p), mix(1, 0.5, p)]
    }

    /// Each WITH view's diagnostics key and its values at `p`.
    /// WITH 中每個 view 的診斷鍵與它在 `p` 時的值。
    static func expected(_ p: Double) -> [(String, [Double], Int)] {
        // (key, values, number of colour-and-location values before the geometry)
        [
            ("tg/text-gradient", stop(0, blue, red, p) + stop(1, green, blue, p) + points(p), 10),
            ("tc/text-gradient", stop(0, blue, red, p) + stop(1, blue, green, p) + [0, 0.5, 1, 0.5], 10),
            ("lin/fill-gradient", stop(0, green, blue, p) + stop(1, blue, red, p) + points(p), 10),
            ("rad/fill-gradient", stop(0, green, red, p) + stop(1, green, blue, p) + [0.3, 0.3, 0, 0.7], 10),
            ("str/stroke-gradient", stop(0, red, blue, p) + stop(1, blue, red, p) + points(p), 10),
            ("fg/fill-gradient", stop(0, blue, green, p) + stop(1, red, blue, p) + points(p), 10),
        ]
    }

    /// Colour error (0-255) and geometry error between `drawn` and `want`.
    /// `drawn` 與 `want` 之間的顏色誤差(0-255)與幾何誤差。
    static func error(_ drawn: [Double], _ want: [Double], stopValues: Int) -> (colour: Double, other: Double)? {
        guard drawn.count == want.count else { return nil }
        var colour = 0.0
        var other = 0.0
        for (index, (d, w)) in zip(drawn, want).enumerated() {
            if index < stopValues && index % 5 != 0 {
                colour = max(colour, abs(d - w) * 255)
            } else {
                other = max(other, abs(d - w))
            }
        }
        return (colour, other)
    }

    static func last(_ key: String) -> [Double]? {
        LayoutAnimationDiagnostics.samples[key]?.last?.values
    }

    static func errors(_ p: Double) -> String {
        expected(p).map { key, want, stopValues in
            guard let drawn = last(key), let e = error(drawn, want, stopValues: stopValues) else {
                return "\(key) values \(last(key)?.count ?? 0)"
            }
            return String(format: "%@ colour %.1f other %.3f", key, e.colour, e.other)
        }.joined(separator: "; ")
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P110Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func next(_ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { step() }
            }
        }

        func with() {
            LayoutAnimationDiagnostics.clear()
            let probe = P110Probe()
            probe.started = ProcessInfo.processInfo.systemUptime
            let animation = Animation.linear(duration: 1).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record(String(format: "WITH MID p=%.3f ", p) + Self.errors(p))
            }
            withAnimation(animation) {
                on = true
            } completion: {
                let frames = Self.expected(1).map { key, _, _ in
                    "\(key.split(separator: "/")[0]) \(LayoutAnimationDiagnostics.samples[key]?.count ?? 0)"
                }.joined(separator: ", ")
                record(
                    String(format: "WITH DONE at %.2f s; ", ProcessInfo.processInfo.systemUptime - probe.started)
                        + Self.errors(1) + "; frames \(frames)"
                )
                next(value)
            }
        }

        /// The VALUE frame nearest the middle of `key`'s tween: p from its first
        /// stop's red, every value against the closed form at p, p against the clock.
        /// `key` 補間中最接近中點的 VALUE 幀：由第一個色標的紅色得到 p,每個值對照 p 時的閉合式，p 對照時鐘。
        func valueError(_ key: String, red: (Double) -> Double, want: (Double) -> [Double]) -> String {
            guard let samples = LayoutAnimationDiagnostics.samples[key], let first = samples.first else {
                return "\(key) no frames"
            }
            guard let mid = samples.min(by: { abs($0.time - first.time - 0.4) < abs($1.time - first.time - 0.4) })
            else { return "\(key) no frames" }
            let p = red(mid.values[1])
            let clock = min(1, (mid.time - first.time) / 0.8)
            guard let e = Self.error(mid.values, want(p), stopValues: 10) else { return "\(key) values \(mid.values.count)" }
            return String(
                format: "%@ p=%.3f (clock %.3f) colour err %.1f other %.3f, frames %ld",
                key, p, clock, e.colour, e.other, samples.count
            )
        }

        func value() {
            LayoutAnimationDiagnostics.clear()
            flip = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    let horizontal = [0.0, 0.5, 1, 0.5]
                    let vertical = [0.5, 0.0, 0.5, 1]
                    let tv = valueError("tv/text-gradient", red: { 1 - $0 }) { p in
                        Self.stop(0, Self.red, Self.green, p) + Self.stop(1, Self.green, Self.red, p) + horizontal
                    }
                    let rv = valueError("rv/fill-gradient", red: { $0 }) { p in
                        Self.stop(0, Self.blue, Self.red, p) + Self.stop(1, Self.red, Self.blue, p) + vertical
                    }
                    record("VALUE \(tv); \(rv)")
                    next(jump)
                }
            }
        }

        func jump() {
            LayoutAnimationDiagnostics.clear()
            on = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated {
                    let counts = Self.expected(0).map { key, _, _ in
                        "\(key.split(separator: "/")[0]) \(LayoutAnimationDiagnostics.samples[key]?.count ?? 0)"
                    }.joined(separator: ", ")
                    // At rest tc is a flat colour again. / 靜止時 tc 又是平面色。
                    let tc = Self.last("tc/text").map { $0.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "none"
                    let starts = Self.expected(0).filter { $0.0 != "tc/text-gradient" && $0.0 != "rad/fill-gradient" }
                    let worst = starts.compactMap { key, want, n in
                        Self.last(key).flatMap { Self.error($0, want, stopValues: n) }
                    }
                    let colour = worst.map(\.colour).max() ?? .infinity
                    let other = worst.map(\.other).max() ?? .infinity
                    let rad = Self.last("rad/fill").map { $0.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "none"
                    record(
                        "JUMP samples \(counts); gradients at start colour err \(String(format: "%.1f", colour)) other \(String(format: "%.3f", other)); tc colour (\(tc)); rad colour (\(rad))"
                    )
                    final()
                }
            }
        }

        func final() {
            on = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated {
                    record("FINAL on = true with no animation; " + Self.errors(1))
                    P110Log.write("STEPS DONE")
                }
            }
        }

        with()
    }
}
