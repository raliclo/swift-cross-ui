// P108: GSAP's Draggable with InertiaPlugin as `.inertialDrag(offset:bounds:)`
// -- a card moved with the pointer and, when let go, coasting from the release
// velocity to a stop (UIScrollView's normal deceleration, τ = 0.4995 s),
// stopping on the bounds. The bounds are offsets x 0...300, y 0...0 (the card
// moves along its track only).
//
// The app runs two steps by itself; an action file (actions/mac/P108-*.actions)
// adds real drags. Each coast frame is compared with the closed form written
// out here: x(t) = x0 + D·(1 - e^(-t/τa)) / (1 - e^(-T/τa)), with D = v·τ and
// τa = τ for a free coast, D = bound - x0 and τa = D / v when the bound stops
// it, T = τa·ln(|D| / 0.1).
//   FREE     fling at 400 pt/s from 0: stops at 199.8 (400·τ). Pass: frame err
//            <= 0.01 pt, end 199.80, duration within 2 frames of T (3.80 s),
//            frames >= 60 per second of coast.
//   BOUND    fling at 3000 pt/s from 0: the bound at 300 stops it. Pass: frame
//            err <= 0.01 pt, never past 300, end 300.00.
//   DRAG     (action file) a press on the card, moves, and a release while
//            moving. Pass: the release velocity (SwiftCrossUI's tracker)
//            within 1 pt/s of the speed over the last 0.1 s of the points as
//            the app received them; the coast frames on the closed form within
//            0.01 pt; the end equal to release offset + v·τ (clamped) within
//            0.01 pt.
//   HOLD     (action file) the card pressed where the throw left it (not at
//            its layout frame), dragged 20 pt and held still 0.3 s. Pass: it
//            moves with the drag, release velocity 0, no coast.
//
// P108:GSAP 的 Draggable 加 InertiaPlugin,即 `.inertialDrag(offset:bounds:)`——卡片隨指標移動，放開時從放開的
// 速度滑行到停止(UIScrollView 的一般減速,τ = 0.4995 秒),停在範圍上。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P108Log {
    /// Appends a line to p108-inertia.log and stdout.
    /// 在 p108-inertia.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P108] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p108-inertia.log")
        guard let data = "P108 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P108App: App {
    var body: some Scene {
        WindowGroup("P108 inertia") {
            #hotReloadable {
                P108RootView()
            }
        }
        .defaultSize(width: 440, height: 520)
    }
}

let p108Bounds = Path.Rect(x: 0, y: 0, width: 300, height: 0)

/// The closed form of a coast from `x0` at `v` inside `0...300`.
/// 從 `x0` 以 `v` 在 `0...300` 之內滑行的封閉形式。
struct P108Coast {
    let x0: Double
    let distance: Double
    let tauA: Double
    let duration: Double

    init(x0: Double, v: Double) {
        let tau = -0.001 / log(0.998)
        self.x0 = x0
        let natural = x0 + v * tau
        let end = min(max(natural, 0), 300)
        distance = end - x0
        tauA = abs(distance) < abs(v * tau) && v != 0 ? abs(distance / v) : tau
        duration = abs(distance) > 0.1 ? tauA * log(abs(distance) / 0.1) : 0
    }

    func x(at t: Double) -> Double {
        guard duration > 0, t < duration else { return x0 + distance }
        return x0 + distance * (1 - exp(-t / tauA)) / (1 - exp(-duration / tauA))
    }
}

struct P108RootView: View {
    @State var offset = SIMD2<Double>(0, 0)
    @State var status = "steps: running"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P108: draggable with inertia")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            ZStack(alignment: .topLeading) {
                Color(red: 0.85, green: 0.85, blue: 0.85)
                    .frame(width: 340, height: 40)
                Color(red: 0.2, green: 0.4, blue: 0.9)
                    .frame(width: 40, height: 40)
                    .inertialDrag(offset: $offset, bounds: p108Bounds)
                    ._effectDiagnosticsLabel("card")
            }
            .frame(width: 340, height: 40, alignment: .topLeading)
            Text(String(format: "offset (%.1f, %.1f)", offset.x, offset.y))
                .font(.system(size: 12))
            Text(status)
                .font(.system(size: 11))
                .frame(width: 400, height: 300, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P108Log.write("backend \(String(describing: DefaultBackend.self))")
            P108Log.write("RENDER COMPLETE -- P108 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P108Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { step() }
            }
        }

        /// The coast frames of `events` against the closed form from the coast
        /// event. / `events` 中的滑行幀對照從滑行事件開始的封閉形式。
        func coastReport(_ events: [InertialDragDiagnostics.Event]) -> String {
            guard let coast = events.last(where: { $0.kind == .coast }) else { return "no coast" }
            let closed = P108Coast(x0: coast.offset.x, v: coast.velocity.x)
            let frames = events.filter { $0.kind == .frame && $0.time >= coast.time }
            var err = 0.0
            var maxX = -Double.infinity
            for frame in frames {
                err = max(err, abs(frame.offset.x - closed.x(at: frame.elapsed)))
                maxX = max(maxX, frame.offset.x)
            }
            let end = events.last(where: { $0.kind == .end })
            let lastElapsed = frames.last?.elapsed ?? 0
            // The first frame after the release: the frame clock starting.
            // 放開之後的第一幀:frame clock 啟動所需的時間。
            let firstFrame = frames.first.map { $0.time - $0.elapsed - coast.time } ?? -1
            let ignored = events.filter { $0.kind == .ignoredEnd }
            let ignoredNote = ignored.isEmpty ? "" : " -- \(ignored.count) drag end(s) with no drag ignored, first at \(ignored[0].offset)"
            return ignoredNote.isEmpty ? report(firstFrame) : report(firstFrame) + ignoredNote
            func report(_ firstFrame: Double) -> String { String(
                format: "from %.2f at %.1f pt/s: frame err=%.4f pt over %ld frames, max x %.2f, end %.2f (closed form %.2f), coast %.3f s (closed form %.3f), %.0f frames/s, first tick %.3f s after the release",
                coast.offset.x, coast.velocity.x, err, frames.count, maxX, end?.offset.x ?? -1,
                closed.x0 + closed.distance, lastElapsed, closed.duration,
                lastElapsed > 0 ? Double(frames.count) / lastElapsed : 0, firstFrame
            ) }
        }

        func free() {
            InertialDragDiagnostics.clear()
            InertialDragDiagnostics.fling("card", velocity: SIMD2(400, 0))
            after(4.2) {
                record("FREE \(coastReport(InertialDragDiagnostics.events["card"] ?? []))")
                after(0.2, bound)
            }
        }

        func bound() {
            offset = .zero
            after(0.3) {
                InertialDragDiagnostics.clear()
                InertialDragDiagnostics.fling("card", velocity: SIMD2(3000, 0))
                after(4.0) {
                    record("BOUND \(coastReport(InertialDragDiagnostics.events["card"] ?? []))")
                    offset = .zero
                    record("STEPS DONE -- waiting for drags")
                    after(0.3) {
                        InertialDragDiagnostics.clear()
                        watch(seen: 0)
                    }
                }
            }
        }

        /// Reports each release and, when its coast ends, the coast.
        /// 回報每次放開，並在其滑行結束時回報滑行。
        func watch(seen: Int) {
            let events = InertialDragDiagnostics.events["card"] ?? []
            var seen = seen
            for (index, event) in events.enumerated() where index >= seen {
                switch event.kind {
                    case .release:
                        let drags = events[..<index].filter { $0.kind == .drag }
                        // The pointer as the app received it: the spacing of
                        // the drag points and the speed from the first to the last.
                        // app 收到的指標：拖曳點的間隔，以及從第一點到最後一點的速度。
                        var spacing = 0.0
                        var speed = 0.0
                        if let first = drags.first, let last = drags.last, drags.count > 1 {
                            spacing = (last.time - first.time) / Double(drags.count - 1) * 1000
                            speed = (last.offset.x - first.offset.x) / (last.time - first.time)
                        }
                        // Over the last 0.1 s, from the points as received (the release included).
                        // 最後 0.1 秒內，由收到的各點(含放開點)算出。
                        let recent = (drags + [event]).filter { event.time - $0.time <= 0.1 }
                        var lastSpeed = 0.0
                        if let first = recent.first, let last = recent.last, last.time - first.time > 0.004 {
                            lastSpeed = (last.offset.x - first.offset.x) / (last.time - first.time)
                        }
                        record(String(format: "DRAG release at %.2f, velocity %.1f pt/s after %ld drag points (received every %.1f ms; %.1f pt/s first to last, %.1f pt/s over the last 0.1 s)", event.offset.x, event.velocity.x, drags.count, spacing, speed, lastSpeed))
                        if event.velocity.x == 0 {
                            record("HOLD release velocity 0: no coast")
                        }
                    case .end:
                        let since = events[..<index].lastIndex(where: { $0.kind == .release }) ?? 0
                        let slice = Array(events[since...index])
                        if slice.contains(where: { $0.kind == .coast }) {
                            let release = slice.first!
                            let tau = -0.001 / log(0.998)
                            let predicted = min(max(release.offset.x + release.velocity.x * tau, 0), 300)
                            record(String(format: "DRAG coast %@; predicted end %.2f", coastReport(slice), predicted))
                        }
                        InertialDragDiagnostics.clear()
                        seen = -1
                    default:
                        break
                }
                if seen == -1 { break }
            }
            let next = seen == -1 ? 0 : events.count
            after(0.05) { watch(seen: next) }
        }

        free()
    }
}
