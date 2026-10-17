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
// Since 2026-10-17 (queue 27) the dots move on the DIRECT PATH: one `running` Bool
// flips inside `withAnimation`, each dot's x offset tweens linearly and its y offset
// tweens through the tile's own curve (`.animation(.timingCurve(curve, ...), value:)`),
// both set on the widget every frame with no body re-evaluation. Because y is
// affine in the curve's progress, y(curve(t)) is exactly the curve, so the dot still
// rides it. The app logs FRAMES (frame-clock ticks and draws of one dot in the first
// 3 s) and ERROR (the largest distance between a drawn dot and the curve at the x it
// is drawn at, in points, at four moments). The driven tweens run in their own child
// view, so their per-frame re-render does not re-evaluate the tiles.
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
// 自 2026-10-17(queue 27)起，紅點走**直接路徑**:`withAnimation` 內翻轉一個 `running` Bool,每個點的 x
// offset 線性補間、y offset 以該格自己的曲線補間(`.animation(.timingCurve(curve, ...), value:)`),兩者每幀直接
// 設到 widget 上，不重算 body。y 對曲線進度是仿射的，所以 y(curve(t)) 正是那條曲線，點仍沿曲線走。app 記錄
// FRAMES(前 3 秒的 frame clock tick 數與某一點的繪製次數)與 ERROR(四個時刻中，畫出的點與它所在 x 處曲線的
// 最大距離，單位為點)。driven 補間在自己的子 view 中執行，它每幀的重新算繪不會重算這些格子。
// 只看這些格子，driver 壞了也會通過：點的高度是從曲線算出來的，不是從時鐘。因此 app 也讓 `driven` 經由
// frame clock 從 0 動到 1 四次——`.back(.out)`、`.bounce(.out)`、`.steps(4)` 與 `.bouncy`——每 8 毫秒取樣，
// 並記錄峰值與相異值的數量。通過條件:back.out 的峰值接近 1.0998(GSAP 的超越量);bounce.out 從不超過 1;
// steps(4) 最多只有 5 個相異值(0、0.25、0.5、0.75、1);bouncy 的峰值高於 1.03。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

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

/// Frame counts and the direct-path error for the 3 s phase run (queue 27).
/// 3 秒 phase 執行的幀數與直接路徑誤差(queue 27)。
enum P96Meter {
    nonisolated(unsafe) static var ticks: [Double] = []
    nonisolated(unsafe) static var bodies: [Double] = []
    nonisolated(unsafe) static var phase = 0.0
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Called from the phase animation's onUpdate, once per frame.
    /// 由 phase 動畫的 onUpdate 呼叫，每幀一次。
    @MainActor
    static func tick(_ progress: Double) {
        phase = progress
        ticks.append(now)
        if ticks.count == 1 {
            draws0 = EffectAnimationDiagnostics.draws["x power1.in"] ?? 0
            for delay in [1.0, 1.5, 2.0, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { measureError(at: delay) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                MainActor.assumeIsolated {
                    draws3 = EffectAnimationDiagnostics.draws["x power1.in"] ?? 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                MainActor.assumeIsolated { report(from: 0, label: "FRAMES") }
            }
            // Again once the driven tweens are done (about 4.5 s), so the second
            // count is the dots alone. / driven 補間結束後(約 4.5 秒)再數一次，第二個數字只有紅點。
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                MainActor.assumeIsolated {
                    draws5 = EffectAnimationDiagnostics.draws["x power1.in"] ?? 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                MainActor.assumeIsolated {
                    draws3 = EffectAnimationDiagnostics.draws["x power1.in"] ?? 0
                    draws0 = draws5
                    report(from: 5, label: "FRAMES-ALONE")
                }
            }
        }
    }

    nonisolated(unsafe) static var draws0 = 0
    nonisolated(unsafe) static var draws3 = 0
    nonisolated(unsafe) static var draws5 = 0

    /// For every tile: the drawn x gives the progress p, so the dot should be at
    /// y(curve(p)); the error is the distance from the drawn y. And x against the
    /// group's progress, which comes from the same frame.
    /// 每一格：畫出的 x 給出進度 p,點應在 y(curve(p));誤差是與畫出 y 的距離。另以群組進度(同一幀)檢查 x。
    @MainActor
    static func measureError(at time: Double) {
        let side = P96TileView.side
        var worstY = 0.0
        var worstX = 0.0
        var worstName = ""
        var missing = 0
        for tile in P96Tile.all {
            guard let x = EffectAnimationDiagnostics.geometric["x \(tile.name)"]?.translation.x,
                let y = EffectAnimationDiagnostics.geometric["y \(tile.name)"]?.translation.y
            else {
                missing += 1
                continue
            }
            let p = (x + 3.5) / side
            let expectedY = P96CurveGraph.y(tile.curve.progress(at: p), height: side) - 3.5
            if abs(y - expectedY) > worstY {
                worstY = abs(y - expectedY)
                worstName = tile.name
            }
            worstX = max(worstX, abs(x - (phase * side - 3.5)))
        }
        P96Log.write(
            "ERROR at \(String(format: "%.1f", time)) s phase \(String(format: "%.3f", phase)): curve y max \(String(format: "%.3f", worstY)) pt (\(worstName)), x vs clock max \(String(format: "%.3f", worstX)) pt, missing \(missing)"
        )
    }

    static func report(from offset: Double, label: String) {
        guard let first = ticks.first else {
            P96Log.write("\(label) no tick")
            return
        }
        let start = first + offset
        let end = start + 3
        let t = ticks.filter { $0 >= start && $0 < end }.count
        let b = bodies.filter { $0 >= start && $0 < end }.count
        P96Log.write(
            "\(label) from \(Int(offset)) s: ticks \(t) dot-draws \(draws3 - draws0) tile0-bodies \(b) in 3.0 s (\(String(format: "%.1f", Double(t) / 3)) fps)"
        )
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
    var running: Bool

    var body: some View {
        let _ = tile.name == "power1.in" ? P96Meter.bodies.append(P96Meter.now) : ()
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
                // y through the tile's curve, x linear: both on the direct path.
                // y 經過該格的曲線、x 線性：兩者都走直接路徑。
                Color(red: 0.85, green: 0.15, blue: 0.15)
                    .frame(width: 7, height: 7)
                    .offset(
                        y: P96CurveGraph.y(
                            tile.curve.progress(at: running ? 1 : 0), height: Self.side
                        ) - 3.5
                    )
                    ._effectDiagnosticsLabel("y \(tile.name)")
                    .animation(
                        .timingCurve(tile.curve, duration: 3).repeatForever(autoreverses: false),
                        value: running
                    )
                    .offset(x: (running ? Self.side : 0) - 3.5)
                    ._effectDiagnosticsLabel("x \(tile.name)")
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
    @State var running = false

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
                P96DrivenPanel()
                ForEach(rows.indices) { index in
                    HStack(spacing: 4) {
                        ForEach(rows[index]) { tile in
                            P96TileView(tile: tile, running: running)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P96Log.write("backend \(String(describing: DefaultBackend.self))")
            P96Log.write("RENDER COMPLETE -- P96 ready")
            startWhenDrawn()
            logPhase(remaining: 20)
        }
    }

    /// Flips `running` once the dots have been drawn at their start. onAppear runs
    /// before the window's first commit (one main-loop turn later on macOS, later
    /// still on iOS, where the scene connects first), and an effect animates from
    /// what is drawn, so flipping earlier would draw the dots at their end.
    /// 紅點畫在起點之後才翻轉 `running`。onAppear 在視窗第一次 commit 之前執行(macOS 上晚一輪，iOS 上更晚，
    /// 因為 scene 要先連上),而效果是從畫出的值開始補間，所以太早翻轉會把點直接畫在終點。
    func startWhenDrawn() {
        guard (EffectAnimationDiagnostics.draws["x power1.in"] ?? 0) > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                MainActor.assumeIsolated { startWhenDrawn() }
            }
            return
        }
        withAnimation(
            .linear(duration: 3).repeatForever(autoreverses: false)
                .onUpdate { P96Meter.tick($0) }
        ) {
            running = true
        }
        // What the direct path drew for one tile, so a run in which the dots did
        // not move says whether they were drawn at all.
        // 直接路徑為某一格畫了什麼，讓「點沒有動」的執行能看出它們到底有沒有被畫。
        for delay in [0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    let d = EffectAnimationDiagnostics.self
                    P96Log.write(
                        "DOT power1.in after \(delay) s: x draws \(d.draws["x power1.in"] ?? 0) at \(d.geometric["x power1.in"]?.translation.x ?? .nan), y draws \(d.draws["y power1.in"] ?? 0) at \(d.geometric["y power1.in"]?.translation.y ?? .nan), ticks \(P96Meter.ticks.count)"
                    )
                }
            }
        }
    }

    /// Logs `phase` every half second, so the log shows `repeatForever` wrapping
    /// from 1 back to 0 rather than stopping.
    /// 每半秒記錄一次 `phase`,讓紀錄顯示 `repeatForever` 從 1 繞回 0,而不是停住。
    func logPhase(remaining: Int) {
        P96Log.write("PHASE \(String(format: "%.3f", P96Meter.phase))")
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { logPhase(remaining: remaining - 1) }
        }
    }

}

/// The four driven tweens, in a view of their own so that their per-frame
/// re-render stays here and does not re-evaluate the tiles.
/// 四個 driven 補間放在自己的 view 中，讓它們每幀的重新算繪留在這裡，不去重算那些格子。
struct P96DrivenPanel: View {
    @State var driven = 0.0
    @State var summary = "driven tweens: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("driven: \(String(format: "%.3f", driven))")
            Text(summary)
        }
        .frame(width: 400, alignment: .leading)
        .onAppear {
            runDriven(Self.drivenCases, results: [])
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
