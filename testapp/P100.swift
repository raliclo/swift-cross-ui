// P100: GSAP's Flip -- matchedGeometryEffect and @Namespace. A layout change
// made inside withAnimation is drawn flying from the old frame to the new one.
//
// Three parts, each a Flip case:
//   blocks  four 50x50 blocks in a ForEach; reversing the order moves each one.
//   hero    a 40x40 thumbnail replaced by a 160x100 panel with the same id:
//           the panel grows out of the thumbnail (position and size).
//   tabs    an underline with isSource: false following the selected tab.
//
// The app runs four steps by itself and logs each. "err" is the largest
// distance, in points, between where a view is drawn and where the flip should
// have it at that moment (old + (new - old) * p, p the eased progress reported
// by .onUpdate in the same frame).
//   REVERSE  withAnimation(.linear(duration: 1)) { order.reverse() }.
//            Pass: MID err <= 1, DONE near 1 s plus the first frame, err <= 0.5.
//   HERO     withAnimation(.easeInOut(duration: 0.8)) { expanded = true }.
//            Pass: MID err <= 1 on origin and size, DONE err <= 0.5.
//   TAB      withAnimation(.linear(duration: 0.6)) { tab = "Tab 2" }.
//            Pass: MID err <= 1, DONE err <= 0.5.
//   JUMP     order = [2, 0, 3, 1] with no animation. Pass: drawn = layout at once.
// The buttons stay live afterwards for driving by hand.
//
// P100:GSAP 的 Flip——matchedGeometryEffect 與 @Namespace。在 withAnimation 內做的版面改變，會被畫成從舊
// frame 飛到新 frame。三個部分各是一種 Flip:blocks(ForEach 裡四個方塊，反轉順序讓每個都移動)、hero(40x40
// 縮圖被同 id 的 160x100 面板取代，面板從縮圖長出來，位置與尺寸皆動)、tabs(isSource: false 的底線跟隨選中
// 的分頁)。app 自己執行四個步驟並記錄;"err" 是 view 被畫出的位置與 flip 當下應在之處(舊 + (新 - 舊) * p,
// p 為同一幀 .onUpdate 回報的緩動後進度)之間的最大距離(點)。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P100Log {
    /// Appends a line to p100-flip.log and stdout. / 在 p100-flip.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P100] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p100-flip.log")
        guard let data = "P100 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P100App: App {
    var body: some Scene {
        WindowGroup("P100 flip") {
            #hotReloadable {
                P100RootView()
            }
        }
        .defaultSize(width: 440, height: 600)
    }
}

/// What one step remembers between its start, its midpoint and its end.
/// 一個步驟在開始、中點與結束之間要記住的東西。
@MainActor
final class P100Probe: @unchecked Sendable {
    var before: [AnyHashable: Path.Rect] = [:]
    var midLogged = false
    /// Frames the flip drew (onUpdate calls): data for the compositor decision.
    /// flip 畫了幾幀(onUpdate 次數):compositor 決策用的數據。
    var frames = 0
    var started = 0.0
}

struct P100RootView: View {
    @Namespace var ns
    @State var order = [0, 1, 2, 3]
    @State var expanded = false
    /// A String, not an Int: an Int is an AnimatableValue here, so `tab = 2` inside
    /// withAnimation would tween through tab 1 (it did, 2026-10-17) instead of
    /// moving the source once. / 用 String 而非 Int:Int 在這裡是 AnimatableValue,withAnimation 內的
    /// `tab = 2` 會補間經過 tab 1(2026-10-17 確實如此),而不是讓來源只移動一次。
    @State var tab = "Tab 0"
    @State var status = "steps: running"

    static let colors = [
        Color(red: 0.85, green: 0.15, blue: 0.15),
        Color(red: 0.15, green: 0.65, blue: 0.25),
        Color(red: 0.15, green: 0.35, blue: 0.85),
        Color(red: 0.95, green: 0.6, blue: 0.1),
    ]
    static let hero = Color(red: 0.55, green: 0.25, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P100: Flip (matchedGeometryEffect)")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("blocks: reverse the order")
                .font(.system(size: 12))
            HStack(spacing: 10) {
                ForEach(order, id: \.self) { n in
                    Self.colors[n]
                        .frame(width: 50, height: 50)
                        .matchedGeometryEffect(id: n, in: ns, anchor: .topLeading)
                }
            }

            Text("hero: thumbnail -> panel")
                .font(.system(size: 12))
            HStack(alignment: .top, spacing: 0) {
                if expanded {
                    Spacer()
                    Self.hero
                        .frame(width: 160, height: 100)
                        .matchedGeometryEffect(id: "hero", in: ns, anchor: .topLeading)
                } else {
                    Self.hero
                        .frame(width: 40, height: 40)
                        .matchedGeometryEffect(id: "hero", in: ns, anchor: .topLeading)
                    Spacer()
                }
            }
            .frame(width: 300, height: 100)

            Text("tabs: the underline follows")
                .font(.system(size: 12))
            HStack(spacing: 0) {
                ForEach([0, 1, 2], id: \.self) { index in
                    VStack(spacing: 0) {
                        Text("Tab \(index)")
                            .frame(width: 80, height: 24)
                        if tab == "Tab \(index)" {
                            Color(red: 0.92, green: 0.93, blue: 0.95)
                                .frame(width: 80, height: 3)
                                .matchedGeometryEffect(id: "selected", in: ns, anchor: .topLeading)
                        } else {
                            Color(red: 0.92, green: 0.93, blue: 0.95)
                                .frame(width: 80, height: 3)
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                Color(red: 0.1, green: 0.1, blue: 0.1)
                    .frame(width: 80, height: 3)
                    .matchedGeometryEffect(
                        id: "selected",
                        in: ns,
                        properties: .position,
                        anchor: .topLeading,
                        isSource: false
                    )
                Spacer()
            }
            .frame(width: 240)

            HStack(spacing: 6) {
                Button("Reverse") { withAnimation(.timingCurve(.power2(.inOut), duration: 0.6)) { order.reverse() } }
                Button("Hero") { withAnimation(.smooth) { expanded.toggle() } }
                Button("Tab") { withAnimation(.snappy) { tab = ["Tab 0": "Tab 1", "Tab 1": "Tab 2"][tab] ?? "Tab 0" } }
                Button("Shuffle") { order.shuffle() }
            }
            Text(status)
                .font(.system(size: 11))
                // A fixed box, so a new line here does not move the blocks: a
                // layout change inside an animation's window is itself animated.
                // 固定的框，讓這裡多一行時不會移動方塊：動畫時間窗內的版面改變本身也會被動畫。
                .frame(width: 400, height: 120, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P100Log.write("backend \(String(describing: DefaultBackend.self))")
            P100Log.write("RENDER COMPLETE -- P100 ready")
            // Give the first layout a turn to settle so every frame is measured.
            // 讓第一次排版有一輪時間安定下來，好讓每個 frame 都已量到。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    static func distance(_ a: Path.Rect, _ b: Path.Rect, size: Bool = true) -> Double {
        var d = max(abs(a.origin.x - b.origin.x), abs(a.origin.y - b.origin.y))
        if size {
            d = max(d, abs(a.size.x - b.size.x), abs(a.size.y - b.size.y))
        }
        return d
    }

    static func lerp(_ a: Path.Rect, _ b: Path.Rect, _ p: Double) -> Path.Rect {
        Path.Rect(origin: a.origin + (b.origin - a.origin) * p, size: a.size + (b.size - a.size) * p)
    }

    static func format(_ r: Path.Rect?) -> String {
        guard let r else { return "nil" }
        return String(format: "(%.1f, %.1f %.1fx%.1f)", r.origin.x, r.origin.y, r.size.x, r.size.y)
    }

    var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// REVERSE, HERO, TAB, JUMP, each after the last one's completion.
    /// 依序執行 REVERSE、HERO、TAB、JUMP,每一步在前一步的 completion 之後。
    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P100Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func next(_ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { step() }
            }
        }
        let ns = self.ns
        let blocks: [AnyHashable] = [0, 1, 2, 3]

        // Mid-flight: drawn against old + (new - old) * p for every id given.
        // 飛行途中：每個 id 的繪製位置對照 舊 + (新 - 舊) * p。
        func midError(_ probe: P100Probe, _ ids: [AnyHashable], _ p: Double) -> Double {
            var worst = 0.0
            for id in ids {
                guard let before = probe.before[id],
                    let after = MatchedGeometryDiagnostics.layoutFrame(of: id, in: ns),
                    let drawn = MatchedGeometryDiagnostics.drawnFrame(of: id, in: ns)
                else { return .infinity }
                worst = max(worst, Self.distance(drawn, Self.lerp(before, after, p)))
            }
            return worst
        }
        func restError(_ ids: [AnyHashable]) -> Double {
            var worst = 0.0
            for id in ids {
                guard let after = MatchedGeometryDiagnostics.layoutFrame(of: id, in: ns),
                    let drawn = MatchedGeometryDiagnostics.drawnFrame(of: id, in: ns)
                else { return .infinity }
                worst = max(worst, Self.distance(drawn, after))
            }
            return worst
        }

        func reverse() {
            let probe = P100Probe()
            for id in blocks {
                probe.before[id] = MatchedGeometryDiagnostics.layoutFrame(of: id, in: ns)
            }
            probe.started = uptime
            let animation = Animation.linear(duration: 1).onUpdate { p in
                probe.frames += 1
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record(
                    String(
                        format: "REVERSE MID p=%.3f err=%.2f; block 0 drawn %@ from %@ to %@",
                        p, midError(probe, blocks, p),
                        Self.format(MatchedGeometryDiagnostics.drawnFrame(of: 0, in: ns)),
                        Self.format(probe.before[0]),
                        Self.format(MatchedGeometryDiagnostics.layoutFrame(of: 0, in: ns))
                    )
                )
            }
            withAnimation(animation) {
                order.reverse()
            } completion: {
                record(
                    String(
                        format: "REVERSE DONE at %.2f err=%.2f; mid seen %@; %ld frames drawn",
                        uptime - probe.started, restError(blocks), probe.midLogged ? "yes" : "no",
                        probe.frames
                    )
                )
                next(hero)
            }
        }

        func hero() {
            let probe = P100Probe()
            probe.before["hero"] = MatchedGeometryDiagnostics.layoutFrame(of: "hero", in: ns)
            probe.started = uptime
            let animation = Animation.easeInOut(duration: 0.8).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record(
                    String(
                        format: "HERO MID p=%.3f err=%.2f; drawn %@ from %@ to %@",
                        p, midError(probe, ["hero"], p),
                        Self.format(MatchedGeometryDiagnostics.drawnFrame(of: "hero", in: ns)),
                        Self.format(probe.before["hero"]),
                        Self.format(MatchedGeometryDiagnostics.layoutFrame(of: "hero", in: ns))
                    )
                )
            }
            withAnimation(animation) {
                expanded = true
            } completion: {
                record(
                    String(
                        format: "HERO DONE at %.2f err=%.2f; mid seen %@",
                        uptime - probe.started, restError(["hero"]), probe.midLogged ? "yes" : "no"
                    )
                )
                next(tabStep)
            }
        }

        func tabStep() {
            let probe = P100Probe()
            let before = MatchedGeometryDiagnostics.followerFrames(of: "selected", in: ns).first
            probe.started = uptime
            func followerError(_ p: Double) -> Double {
                guard let before,
                    let source = MatchedGeometryDiagnostics.layoutFrame(of: "selected", in: ns),
                    let drawn = MatchedGeometryDiagnostics.followerFrames(of: "selected", in: ns).first
                else { return .infinity }
                let target = Path.Rect(origin: source.origin, size: before.size)
                return Self.distance(drawn, Self.lerp(before, target, p))
            }
            let animation = Animation.linear(duration: 0.6).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record(
                    String(
                        format: "TAB MID p=%.3f err=%.2f; underline drawn %@ from %@ to the source %@",
                        p, followerError(p),
                        Self.format(MatchedGeometryDiagnostics.followerFrames(of: "selected", in: ns).first),
                        Self.format(before), Self.format(MatchedGeometryDiagnostics.layoutFrame(of: "selected", in: ns))
                    )
                )
            }
            withAnimation(animation) {
                tab = "Tab 2"
            } completion: {
                record(
                    String(
                        format: "TAB DONE at %.2f err=%.2f; source %@; mid seen %@",
                        uptime - probe.started, followerError(1),
                        Self.format(MatchedGeometryDiagnostics.layoutFrame(of: "selected", in: ns)),
                        probe.midLogged ? "yes" : "no"
                    )
                )
                next(jump)
            }
        }

        func jump() {
            order = [2, 0, 3, 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    record(String(format: "JUMP err=%.2f (no animation)", restError(blocks)))
                    P100Log.write("STEPS DONE")
                }
            }
        }

        reverse()
    }
}
