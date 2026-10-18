// P104: layout and drawn state under an animation -- `.frame`, `.padding`, a
// `Color` view and a `Shape` fill tween when they change inside
// `withAnimation` or `.animation(_:value:)`, each frame re-laid out through the
// node that holds the value (no body evaluation) or redrawn.
//
// The app runs four steps by itself and logs each. Values are what the
// modifiers set on their widgets (LayoutAnimationDiagnostics), in points for a
// size and 0-255 for a colour channel.
//   WITH   withAnimation(.linear(duration: 1)) { wide = true }: the frame width
//          100 -> 300, the padding 0 -> 200 (padded width 40 -> 240), a Color
//          view and a Circle fill blue -> red. At p >= 0.5 (onUpdate), each is
//          compared with start + (end - start) * p. Pass: MID err <= 1 (size)
//          and <= 3 (colour), DONE at the end values, body evaluations 1.
//   VALUE  tall = true, no withAnimation, under .animation(.linear(duration: 1),
//          value: tall): a frame height 30 -> 120. Every sample against the
//          line through the first one. Pass: err <= 3, frames >= 20, DONE 120.
//   NIL    .animation(nil, value: tall) inside it: that frame jumps. Pass: one
//          sample, at the end value.
//   JUMP   wide = false with no animation. Pass: the width goes 300 -> 100 in
//          one sample.
//
// P104:動畫中的版面與繪製狀態——`.frame`、`.padding`、`Color` view 與 `Shape` 填色在 `withAnimation` 或
// `.animation(_:value:)` 之內改變時會補間，每一幀經由持有該值的節點重新排版(不求值 body)或重畫。app 自己執行
// 四個步驟並記錄;數值是 modifier 設到 widget 上的值(LayoutAnimationDiagnostics),尺寸以點、顏色通道以 0-255
// 表示。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P104Log {
    /// Appends a line to p104-layout-animation.log and stdout.
    /// 在 p104-layout-animation.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P104] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p104-layout-animation.log")
        guard let data = "P104 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P104App: App {
    var body: some Scene {
        WindowGroup("P104 layout animation") {
            #hotReloadable {
                P104RootView()
            }
        }
        .defaultSize(width: 440, height: 560)
    }
}

/// Body evaluations of the root, to show a frame does not re-evaluate it.
/// 根 view 的 body 求值次數，用來顯示每一幀不會重算它。
@MainActor
enum P104Counter {
    static var bodies = 0
}

@MainActor
final class P104Probe: @unchecked Sendable {
    var midLogged = false
    var bodiesAtStart = 0
    var started = 0.0
}

struct P104RootView: View {
    @State var wide = false
    @State var tall = false
    @State var status = "steps: running"

    static let blue = Color(red: 0, green: 0, blue: 1)
    static let red = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        let _ = P104Counter.bodies += 1
        VStack(alignment: .leading, spacing: 10) {
            Text("P104: layout and colour under an animation")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("frame width 100 -> 300").font(.system(size: 12))
            Color(red: 0.2, green: 0.5, blue: 0.9)
                .frame(width: wide ? 300 : 100, height: 30)
                ._effectDiagnosticsLabel("width")

            Text("padding 0 -> 200").font(.system(size: 12))
            Color(red: 0.95, green: 0.6, blue: 0.1)
                .frame(width: 40, height: 30)
                .padding(.leading, wide ? 200 : 0)
                ._effectDiagnosticsLabel("pad")

            Text("Color view and Circle fill, blue -> red").font(.system(size: 12))
            HStack(spacing: 12) {
                (wide ? Self.red : Self.blue)
                    .frame(width: 60, height: 30)
                    ._effectDiagnosticsLabel("color")
                Circle()
                    .fill(wide ? Self.red : Self.blue)
                    .frame(width: 30, height: 30)
                    ._effectDiagnosticsLabel("circle")
            }

            Text(".animation(_:value:) height 30 -> 120; nil jumps").font(.system(size: 12))
            HStack(alignment: .top, spacing: 12) {
                Color(red: 0.2, green: 0.7, blue: 0.3)
                    .frame(width: 60, height: tall ? 120 : 30)
                    ._effectDiagnosticsLabel("value")
                Color(red: 0.5, green: 0.5, blue: 0.5)
                    .frame(width: 60, height: tall ? 120 : 30)
                    ._effectDiagnosticsLabel("nil")
                    .animation(nil, value: tall)
            }
            .animation(.linear(duration: 1), value: tall)
            .frame(height: 120, alignment: .top)

            HStack(spacing: 6) {
                Button("Wide") { withAnimation(.smooth) { wide.toggle() } }
                Button("Tall") { tall.toggle() }
            }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 400, height: 110, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P104Log.write("backend \(String(describing: DefaultBackend.self))")
            P104Log.write("RENDER COMPLETE -- P104 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    var uptime: Double { ProcessInfo.processInfo.systemUptime }

    static func last(_ key: String) -> [Double]? {
        LayoutAnimationDiagnostics.samples[key]?.last?.values
    }

    static func format(_ values: [Double]?) -> String {
        guard let values else { return "nil" }
        return "(" + values.map { String(format: "%.1f", $0) }.joined(separator: ", ") + ")"
    }

    /// WITH, VALUE (with NIL), JUMP. / 依序執行 WITH、VALUE(含 NIL)、JUMP。
    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P104Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func next(_ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { step() }
            }
        }

        // The worst distance of the four WITH values from start + (end - start) * p.
        // WITH 的四個值與 起點 + (終點 - 起點) * p 的最大距離。
        func withErrors(_ p: Double) -> (size: Double, colour: Double) {
            var size = 0.0
            var colour = 0.0
            if let w = Self.last("width/frame") {
                size = max(size, abs(w[0] - (100 + 200 * p)))
            } else {
                size = .infinity
            }
            if let w = Self.last("pad/padding") {
                size = max(size, abs(w[0] - (40 + 200 * p)))
            } else {
                size = .infinity
            }
            for key in ["color/color", "circle/fill"] {
                guard let c = Self.last(key) else {
                    colour = .infinity
                    continue
                }
                colour = max(colour, abs(c[0] - p) * 255, abs(c[2] - (1 - p)) * 255)
            }
            return (size, colour)
        }

        func with() {
            let probe = P104Probe()
            probe.bodiesAtStart = P104Counter.bodies
            probe.started = uptime
            let animation = Animation.linear(duration: 1).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                let (size, colour) = withErrors(p)
                record(
                    String(
                        format: "WITH MID p=%.3f err=%.2f pt, colour err=%.1f; width %@ pad %@ color %@ circle %@",
                        p, size, colour,
                        Self.format(Self.last("width/frame")), Self.format(Self.last("pad/padding")),
                        Self.format(Self.last("color/color")), Self.format(Self.last("circle/fill"))
                    )
                )
            }
            withAnimation(animation) {
                wide = true
            } completion: {
                let (size, colour) = withErrors(1)
                record(
                    String(
                        format: "WITH DONE at %.2f err=%.2f pt, colour err=%.1f; %ld width frames; body evaluations %ld; mid seen %@",
                        uptime - probe.started, size, colour,
                        LayoutAnimationDiagnostics.samples["width/frame"]?.count ?? 0,
                        P104Counter.bodies - probe.bodiesAtStart, probe.midLogged ? "yes" : "no"
                    )
                )
                next(value)
            }
        }

        func value() {
            LayoutAnimationDiagnostics.clear()
            let started = uptime
            tall = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                MainActor.assumeIsolated {
                    let samples = LayoutAnimationDiagnostics.samples["value/frame"] ?? []
                    // The line through the first sample, at 90 pt/s: its start
                    // is where that sample says the tween began.
                    // 通過第一個樣本、斜率 90 pt/s 的直線：起點由該樣本推回補間開始的時刻。
                    var err = Double.infinity
                    if let first = samples.first {
                        let t0 = first.time - (first.values[1] - 30) / 90
                        err = 0
                        for sample in samples {
                            let expected = min(120, 30 + 90 * (sample.time - t0))
                            err = max(err, abs(sample.values[1] - expected))
                        }
                        record(
                            String(
                                format: "VALUE DONE err=%.2f pt over %ld frames; first at %.3f s; last %@",
                                err, samples.count, t0 - started, Self.format(samples.last?.values)
                            )
                        )
                    } else {
                        record("VALUE DONE no samples")
                    }
                    let jumped = LayoutAnimationDiagnostics.samples["nil/frame"] ?? []
                    record(
                        "NIL samples \(jumped.count): \(jumped.map { Self.format($0.values) }.joined(separator: " "))"
                    )
                    next(jump)
                }
            }
        }

        func jump() {
            LayoutAnimationDiagnostics.clear()
            wide = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated {
                    let widths = LayoutAnimationDiagnostics.samples["width/frame"] ?? []
                    record(
                        "JUMP width samples \(widths.count): \(widths.map { Self.format($0.values) }.joined(separator: " "))"
                    )
                    P104Log.write("STEPS DONE")
                }
            }
        }

        with()
    }
}
