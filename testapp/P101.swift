// P101: GSAP's ScrollTrigger -- scrollTransition, onScrollVisibilityChange and
// onScrollGeometryChange, SwiftUI's names for scroll-driven animation.
//
// A 300-point ScrollView holds 20 rows, 50 points each, with no spacing:
//   - every row: .scrollTransition(.interactive(timingCurve: linear)) fading to
//     0.2 and scaling to 0.7 as it leaves (GSAP scrub). Rows 5, 10 and 15 use
//     .animated(.linear(duration: 0.3)) instead (GSAP toggleActions).
//   - row 15: onScrollVisibilityChange(threshold: 0.5) logs ENTER / LEAVE.
//   - the ScrollView: onScrollGeometryChange(for: Double) reads contentOffset.y
//     and seeks a TimelinePlayer with it, a scrubbed timeline driving the bar.
//
// The app scrolls itself with ScrollViewProxy and logs each step. "err" is the
// largest difference between the opacity a row is drawn with and the one its
// place in the viewport gives, computed here independently: with visible(1),
// position = side * (1 - visible share) and opacity = 1 - 0.8 * |position|.
// Animated rows are checked only where they are fully in or fully out.
//   START    offset 0. Pass: err <= 0.01, rows 0-5 identity, row 6 at 0.2.
//   TO10     scrollTo(10, anchor: .top). Pass: offset 500, err <= 0.01,
//            row 15 ENTER logged (its top is at 750 of 500-800).
//   CENTER3  scrollTo(3, anchor: .center): rows cut at both edges. Pass: err <= 0.01,
//            row 15 LEAVE logged.
//   SCRUB    at each step the player's progress equals offset / (1000 - 300).
//
// P101:GSAP 的 ScrollTrigger——scrollTransition、onScrollVisibilityChange 與 onScrollGeometryChange,也就是
// SwiftUI 對捲動驅動動畫的名稱。300 點高的 ScrollView 裡有 20 列、每列 50 點、無間距：每列以 interactive(線性)
// 在離開時淡到 0.2、縮到 0.7(GSAP scrub);第 5、10、15 列改用 animated(0.3 秒線性)(GSAP toggleActions);
// 第 15 列以 onScrollVisibilityChange(門檻 0.5)記錄 ENTER/LEAVE;ScrollView 以 onScrollGeometryChange 讀取
// contentOffset.y 並拿它 seek 一個 TimelinePlayer(擦洗的 timeline 驅動長條)。app 用 ScrollViewProxy 自己捲動並
// 逐步記錄;"err" 是某列被畫出的不透明度與其視口位置所得之值(在此獨立計算)的最大差。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P101Log {
    /// Appends a line to p101-scroll.log and stdout. / 在 p101-scroll.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P101] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p101-scroll.log")
        guard let data = "P101 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P101App: App {
    var body: some Scene {
        WindowGroup("P101 scroll") {
            #hotReloadable {
                P101RootView()
            }
        }
        .defaultSize(width: 440, height: 640)
    }
}

/// Shared between the view, the scroll callbacks and the steps.
/// 由 view、捲動回呼與步驟共用。
@MainActor
final class P101Probe: @unchecked Sendable {
    var proxy: ScrollViewProxy?
    var geometry: ScrollGeometry?
    var geometryChanges = 0
    var visibility: [String] = []
    var player: TimelinePlayer?
}

struct P101RootView: View {
    static let rows = 20
    static let rowHeight = 50.0
    static let viewport = 300.0
    static let animatedRows: Set<Int> = [5, 10, 15]

    @State var probe = P101Probe()
    @State var bar = 0.0
    @State var status = "steps: running"

    func row(_ index: Int) -> some View {
        let fill = Color(
            red: 0.2 + 0.03 * Double(index), green: 0.45, blue: 0.85 - 0.03 * Double(index)
        )
        return HStack {
            Text("Row \(index)\(Self.animatedRows.contains(index) ? " (animated)" : "")")
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.leading, 12)
        .frame(width: 280, height: Self.rowHeight)
        .background(fill)
    }

    func transitioned(_ index: Int) -> some View {
        let configuration: ScrollTransitionConfiguration =
            Self.animatedRows.contains(index)
            ? .animated(.linear(duration: 0.3))
            : .interactive(timingCurve: Animation.Curve.linear)
        return row(index)
            .scrollTransition(configuration) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.2)
                    .scaleEffect(phase.isIdentity ? 1 : 0.7)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P101: ScrollTrigger (scrollTransition)")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            HStack(spacing: 0) {
                Color(red: 0.9, green: 0.4, blue: 0.1)
                    .frame(width: 12, height: 12)
                    .padding(.leading, bar * 268)
                Spacer()
            }
            .frame(width: 280)
            .background(Color(red: 0.92, green: 0.93, blue: 0.95))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(0..<Self.rows), id: \.self) { index in
                            if index == 15 {
                                transitioned(index)
                                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                                        probe.visibility.append(visible ? "ENTER" : "LEAVE")
                                        P101Log.write("row 15 \(visible ? "ENTER" : "LEAVE")")
                                    }
                                    .id(index)
                            } else {
                                transitioned(index)
                                    .id(index)
                            }
                        }
                    }
                }
                .frame(width: 300, height: Self.viewport)
                .onScrollGeometryChange(for: Double.self) { geometry in
                    probe.geometry = geometry
                    return geometry.contentOffset.y
                } action: { _, offset in
                    probe.geometryChanges += 1
                    let range = (probe.geometry?.contentSize.height ?? 1000) - Self.viewport
                    probe.player?.seek(progress: range > 0 ? offset / range : 0)
                }
                .onAppear { probe.proxy = proxy }
            }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 400, height: 110, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P101Log.write("backend \(String(describing: DefaultBackend.self))")
            P101Log.write("RENDER COMPLETE -- P101 ready")
            var timeline = AnimationTimeline()
            timeline.add(.linear(duration: 1)) { bar = $0 }
            probe.player = TimelinePlayer(timeline)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    /// Opacity the row should have, from its place alone (visible(1), linear).
    /// 只由列的位置算出它應有的不透明度(visible(1)、線性)。
    static func expectedOpacity(start: Double, length: Double, viewport: Double) -> Double {
        let shown = min(start + length, viewport) - max(start, 0)
        let share = min(max(shown, 0), length) / length
        return 1 - 0.8 * (1 - share)
    }

    /// The worst opacity error over every measured row, and the rows drawn at identity.
    /// 所有已量測列中最大的不透明度誤差，以及畫成 identity 的列。
    func check(offset: Double) -> (err: Double, identity: [Int], rows: Int) {
        var worst = 0.0
        var identity: [Int] = []
        var rows = 0
        for entry in ScrollTransitionDiagnostics.entries() {
            guard let frame = entry.frameInContent else { continue }
            rows += 1
            let index = Int((frame.origin.y / Self.rowHeight).rounded())
            let start = frame.origin.y - offset
            let expected = Self.expectedOpacity(
                start: start, length: frame.size.y, viewport: Self.viewport
            )
            if entry.effect.visual.opacity > 0.999 {
                identity.append(index)
            }
            if entry.isAnimated {
                guard expected == 1 || expected <= 0.2 + 1e-9 else { continue }
            }
            worst = max(worst, abs(entry.effect.visual.opacity - expected))
        }
        return (worst, identity.sorted(), rows)
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P101Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func report(_ name: String) {
            let offset = probe.geometry?.contentOffset.y ?? .nan
            let (err, identity, rows) = check(offset: offset)
            let range = (probe.geometry?.contentSize.height ?? .nan) - Self.viewport
            let scrub = abs((probe.player?.progress ?? -1) - (range > 0 ? offset / range : 0))
            record(
                String(
                    format: "%@ offset %.1f content %.0f; err=%.3f over %d rows; identity rows %@; scrub err %.3f; geometry changes %d; row 15 %@",
                    name, offset, probe.geometry?.contentSize.height ?? .nan, err, rows,
                    identity.map(String.init).joined(separator: ","), scrub,
                    probe.geometryChanges, probe.visibility.joined(separator: " ")
                )
            )
        }
        func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { step() }
            }
        }

        report("START")
        probe.proxy?.scrollTo(10, anchor: .top)
        after(0.6) {
            report("TO10")
            probe.proxy?.scrollTo(3, anchor: .center)
            after(0.6) {
                report("CENTER3")
                P101Log.write("STEPS DONE")
            }
        }
    }
}
