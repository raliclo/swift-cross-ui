// P96: GSAP's eases as SwiftUI timing curves -- a gallery, and one tween driven
// through each kind of curve.
//
// Every tile draws one curve from its own formula, with progress on the y axis
// from -0.3 to 1.3 so that back, elastic and a bouncy spring show where they
// pass the target. A red dot rides each curve, driven by one `phase` state that
// runs 0 -> 1 under `.linear(duration: 3).repeatForever(autoreverses: false)`,
// so a capture during the run shows every dot part-way, and two captures a
// second apart show `repeatForever` still going.
//
// The tiles alone would pass with a broken driver: the dots compute their
// height from the curve, not from the clock. So the app also animates `driven`
// from 0 to 1 four times through the frame clock -- `.back(.out)`, `.bounce(.out)`,
// `.steps(4)` and `.bouncy` -- samples it every 8 ms, and logs the peak and the
// number of distinct values. Pass: back.out peaks near 1.0998 (GSAP's
// overshoot); bounce.out never exceeds 1; steps(4) shows at most 5 distinct
// values (0, 0.25, 0.5, 0.75, 1); bouncy peaks above 1.03.
//
// P96:GSAP 的 ease 化為 SwiftUI 的 timing curve——一份圖鑑，加上以每一類曲線驅動的補間。
// 每一格以曲線自己的公式畫出一條曲線,y 軸的進度從 -0.3 到 1.3,好讓 back、elastic 與會彈跳的彈簧顯示它們衝過
// 目標的地方。每條曲線上有一個紅點，由同一個 `phase` 狀態驅動，它以
// `.linear(duration: 3).repeatForever(autoreverses: false)` 從 0 跑到 1,因此執行中的擷圖會看到每個點都停在半路，
// 相隔一秒的兩張擷圖則顯示 `repeatForever` 仍在進行。
// 只看這些格子，driver 壞了也會通過：點的高度是從曲線算出來的，不是從時鐘。因此 app 也讓 `driven` 經由
// frame clock 從 0 動到 1 四次——`.back(.out)`、`.bounce(.out)`、`.steps(4)` 與 `.bouncy`——每 8 毫秒取樣，
// 並記錄峰值與相異值的數量。通過條件:back.out 的峰值接近 1.0998(GSAP 的超越量);bounce.out 從不超過 1;
// steps(4) 最多只有 5 個相異值(0、0.25、0.5、0.75、1);bouncy 的峰值高於 1.03。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P96Log {
    /// Appends a line to p96-curves.log and stdout. / 在 p96-curves.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P96] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p96-curves.log")
        guard let data = "P96 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

struct P96Tile: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let curve: any TimingCurve

    static let all: [P96Tile] = {
        let shapes: [(String, Ease.Shape)] = [
            ("power1", .power(1)), ("power2", .power(2)), ("power3", .power(3)),
            ("power4", .power(4)), ("sine", .sine), ("expo", .expo), ("circ", .circ),
            ("back", .back(overshoot: 1.70158)),
            ("elastic", .elastic(amplitude: 1, period: 0.3)), ("bounce", .bounce),
        ]
        var tiles: [P96Tile] = []
        for (name, shape) in shapes {
            tiles.append(P96Tile(name: "\(name).in", curve: Ease(shape, .in)))
            tiles.append(P96Tile(name: "\(name).out", curve: Ease(shape, .out)))
            tiles.append(P96Tile(name: "\(name).inOut", curve: Ease(shape, .inOut)))
        }
        tiles.append(P96Tile(name: "steps(4)", curve: Steps(4)))
        tiles.append(P96Tile(name: "bezier ease", curve: CubicBezier(0.25, 0.1, 0.25, 1)))
        tiles.append(P96Tile(name: "spring b0.3", curve: Spring(duration: 0.5, bounce: 0.3)))
        return tiles
    }()
}

/// The curve from (0, curve(0)) to (1, curve(1)), y from 1.3 at the top to -0.3
/// at the bottom.
/// 曲線從 (0, curve(0)) 畫到 (1, curve(1)),y 由頂端的 1.3 到底端的 -0.3。
struct P96CurveGraph: Shape {
    var curve: any TimingCurve

    static func y(_ value: Double, height: Double) -> Double {
        (1.3 - value) / 1.6 * height
    }

    func path(in bounds: Path.Rect) -> Path {
        func point(_ t: Double) -> SIMD2<Double> {
            SIMD2(
                bounds.x + t * bounds.width,
                bounds.y + Self.y(curve.progress(at: t), height: bounds.height)
            )
        }
        var path = Path().move(to: point(0))
        for step in 1...80 {
            path = path.addLine(to: point(Double(step) / 80))
        }
        return path
    }
}

struct P96TileView: View {
    static let side = 78.0
    var tile: P96Tile
    var phase: Double

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                Color(red: 0.94, green: 0.95, blue: 0.97)
                    .frame(width: Self.side, height: Self.side)
                // The target and start lines: 1 and 0.
                // 目標線與起點線:1 與 0。
                Color(red: 0.8, green: 0.8, blue: 0.85)
                    .frame(width: Self.side, height: 1)
                    .offset(y: P96CurveGraph.y(1, height: Self.side))
                Color(red: 0.8, green: 0.8, blue: 0.85)
                    .frame(width: Self.side, height: 1)
                    .offset(y: P96CurveGraph.y(0, height: Self.side))
                P96CurveGraph(curve: tile.curve)
                    .stroke(Color(red: 0.15, green: 0.35, blue: 0.8), style: StrokeStyle(width: 1.5))
                    .frame(width: Self.side, height: Self.side)
                Color(red: 0.85, green: 0.15, blue: 0.15)
                    .frame(width: 7, height: 7)
                    .offset(
                        x: phase * Self.side - 3.5,
                        y: P96CurveGraph.y(tile.curve.progress(at: phase), height: Self.side) - 3.5
                    )
            }
            .frame(width: Self.side, height: Self.side)
            Text(tile.name)
                .font(.system(size: 10))
        }
        .frame(width: Self.side + 12)
    }
}

@main
@HotReloadable
struct P96App: App {
    var body: some Scene {
        WindowGroup("P96 timing curves") {
            #hotReloadable {
                P96RootView()
            }
        }
        .defaultSize(width: 440, height: 900)
    }
}

struct P96RootView: View {
    /// Four fit a 402 pt phone screen with the padding; six did not.
    /// 四欄在加上留白後放得進 402 pt 寬的手機螢幕;六欄放不下。
    static let columns = 4
    @State var phase = 0.0
    @State var driven = 0.0
    @State var summary = "driven tweens: running"

    var rows: [[P96Tile]] {
        stride(from: 0, to: P96Tile.all.count, by: Self.columns).map {
            Array(P96Tile.all[$0..<min($0 + Self.columns, P96Tile.all.count)])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("P96: timing curves (GSAP eases, SwiftUI names)")
                    .font(.system(size: 16))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text("driven: \(String(format: "%.3f", driven))")
                Text(summary)
                ForEach(rows.indices) { index in
                    HStack(spacing: 4) {
                        ForEach(rows[index]) { tile in
                            P96TileView(tile: tile, phase: phase)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P96Log.write("backend \(String(describing: DefaultBackend.self))")
            P96Log.write("RENDER COMPLETE -- P96 ready")
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                phase = 1
            }
            runDriven(Self.drivenCases, results: [])
            logPhase(remaining: 24)
        }
    }

    /// Logs `phase` every half second, so the log shows `repeatForever` wrapping
    /// from 1 back to 0 rather than stopping.
    /// 每半秒記錄一次 `phase`,讓紀錄顯示 `repeatForever` 從 1 繞回 0,而不是停住。
    func logPhase(remaining: Int) {
        P96Log.write("PHASE \(String(format: "%.3f", phase))")
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { logPhase(remaining: remaining - 1) }
        }
    }

    static let drivenCases: [(String, Animation)] = [
        ("back.out", .timingCurve(.back(.out), duration: 0.8)),
        ("bounce.out", .timingCurve(.bounce(.out), duration: 0.8)),
        ("steps(4)", .timingCurve(.steps(4), duration: 0.8)),
        ("bouncy", .bouncy),
    ]

    /// Runs the cases one after another: reset to 0 at once, animate to 1, sample
    /// until the animation's duration has passed plus a margin, then log.
    /// 依序執行每個案例：立刻重設為 0、動畫到 1、取樣到動畫時長加上餘裕為止，然後記錄。
    func runDriven(_ cases: [(String, Animation)], results: [String]) {
        guard let (name, animation) = cases.first else {
            summary = results.joined(separator: "  ")
            P96Log.write("DRIVEN DONE")
            return
        }
        driven = 0
        withAnimation(animation) {
            driven = 1
        }
        let started = ProcessInfo.processInfo.systemUptime
        var values: [Double] = []
        func sample() {
            if values.last != driven {
                values.append(driven)
            }
            if ProcessInfo.processInfo.systemUptime - started < animation.duration + 0.3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                    MainActor.assumeIsolated { sample() }
                }
            } else {
                let peak = values.max() ?? 0
                let line =
                    "\(name) peak \(String(format: "%.4f", peak)) distinct \(Set(values).count) final \(String(format: "%.4f", driven))"
                P96Log.write("DRIVEN \(line)")
                runDriven(Array(cases.dropFirst()), results: results + [line])
            }
        }
        sample()
    }
}
