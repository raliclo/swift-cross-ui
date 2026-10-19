// P105: insert and remove transitions -- `.transition(.opacity/.scale/.slide/
// .move(edge:)/.offset/.push(from:)/.asymmetric/.combined(with:))` on views an
// `if`, an `if`/`else` and a `ForEach` insert or remove under `withAnimation` or
// `.animation(_:value:)`. Each frame is set on the view's effect containers from
// the frame clock (no body evaluation); a removed view stays drawn until its
// removal ends.
//
// The app runs six steps by itself and logs each. Values are what the
// transitions drew (TransitionDiagnostics), compared in the same frame with
// AnyTransition.effects(for:size:progress:) at the animation's progress p.
//   INSERT  withAnimation(.linear(duration: 1)) { shown = true }: seven views
//           appear, one per transition (fade, scale, slide, move, offset,
//           push, asym+combined), each 60x30. MID at p >= 0.5: err (translation,
//           pt), opacity err and scale err against the curve. Pass: err <= 0.5
//           pt, opacity and scale err <= 0.01; DONE all seven at identity.
//   REMOVE  withAnimation(.linear(duration: 1)) { shown = false }: the same
//           seven go. MID as above against the removal. Pass: the same bounds,
//           and every view's onDisappear runs 0.95-1.4 s after the change
//           (the node lives until its removal ends), after its last frame.
//   ELSE    withAnimation(.linear(duration: 0.8)) { useB.toggle() } on an
//           if/else of two views with .push(from: .trailing): A leaves, B comes
//           in, in the same frames. Pass: MID err <= 0.5 pt and A's
//           onDisappear 0.75-1.2 s after the change.
//   EACH    a ForEach of four rows with .move(edge: .leading).combined(with:
//           .opacity) under .animation(.linear(duration: 0.8), value: rows):
//           row 2 removed, then row 9 inserted. Pass: MID err <= 0.5 pt for
//           the leaving and the arriving row; the leaving row's onDisappear
//           0.75-1.2 s after the change.
//   DEFAULT views with no `.transition` fade, SwiftUI's default (`.opacity`).
//           IF: withAnimation(.linear(duration: 1)) inserts, then removes, a
//           60x30 view in an `if`; MID at p >= 0.5 the opacity set on the
//           widget against p (insert) or 1 - p (remove). Pass: opacity err <=
//           0.01, the frame drawn on a widget, DONE at opacity 1 (insert), and
//           onDisappear 0.95-1.4 s after the removal. ELSE: an if/else of two
//           views under withAnimation(.linear(duration: 0.8)); MID the leaving
//           view against 1 - p and the arriving one against p, err <= 0.01.
//           EACH: a ForEach under .animation(.linear(duration: 0.8), value:)
//           loses row 2, then gains row 9; the frame nearest the middle against
//           its own progress and the clock. Pass: opacity err <= 0.01, the
//           frame's progress within 0.05 of the clock, drawn on a widget.
//           NOANIM: the `if` view inserted with no animation. Pass: no frames
//           (it appears at once). IDENTITY: a view with `.transition(.identity)`
//           inserted and removed under withAnimation. Pass: every frame at
//           opacity 1, translation 0.
//   JUMP    shown = true with no animation. Pass: no transition frame runs.
//
// P105:插入與移除轉場——`if`、`if`/`else` 與 `ForEach` 在 `withAnimation` 或 `.animation(_:value:)` 之下
// 插入或移除的 view 上的 `.transition(...)`。每一幀由 frame clock 設到 view 的效果容器上(不求值 body);被移除
// 的 view 會一直畫到移除結束;沒有 `.transition` 的 view 淡入淡出(SwiftUI 的預設)。app 自己執行六個步驟並記錄;數值是轉場畫出的東西(TransitionDiagnostics),
// 在同一幀與動畫進度 p 時的 AnyTransition.effects(for:size:progress:) 比較。通過條件見上方英文說明。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P105Log {
    /// Appends a line to p105-transitions.log and stdout.
    /// 在 p105-transitions.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P105] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p105-transitions.log")
        guard let data = "P105 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P105App: App {
    var body: some Scene {
        WindowGroup("P105 transitions") {
            #hotReloadable {
                P105RootView()
            }
        }
        .defaultSize(width: 480, height: 920)
    }
}

/// When each labelled view's onDisappear ran. / 每個加了標籤的 view 的 onDisappear 執行的時刻。
@MainActor
enum P105Disappear {
    static var times: [String: Double] = [:]
}

@MainActor
final class P105Probe: @unchecked Sendable {
    var midLogged = false
    var started = 0.0
}

struct P105Row: Identifiable, Equatable {
    var id: Int
}

/// The seven transitions of INSERT and REMOVE, by label.
/// INSERT 與 REMOVE 的七個轉場，依標籤。
let p105Transitions: [(String, AnyTransition)] = [
    ("fade", .opacity),
    ("scale", .scale),
    ("slide", .slide),
    ("move", .move(edge: .bottom)),
    ("offset", .offset(x: 40, y: -20)),
    ("push", .push(from: .top)),
    ("asym", .asymmetric(insertion: .scale(scale: 0.5, anchor: .topLeading), removal: .move(edge: .trailing)).combined(with: .opacity)),
]

let p105Push = AnyTransition.push(from: .trailing)
let p105RowTransition = AnyTransition.move(edge: .leading).combined(with: .opacity)
let p105Size = SIMD2<Double>(60, 30)

struct P105Tile: View {
    var label: String
    var transition: AnyTransition
    var color: Color

    var body: some View {
        color
            .frame(width: 60, height: 30)
            .transition(transition)
            ._effectDiagnosticsLabel(label)
            .onDisappear {
                P105Disappear.times[label] = ProcessInfo.processInfo.systemUptime
            }
    }
}

struct P105RootView: View {
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

    @State var shown = false
    @State var useB = false
    @State var rows = [P105Row(id: 1), P105Row(id: 2), P105Row(id: 3), P105Row(id: 4)]
    @State var status = "steps: running"
    @State var defShown = false
    @State var defB = false
    @State var defRows = [P105Row(id: 1), P105Row(id: 2), P105Row(id: 3)]
    @State var idShown = false

    static let colors: [Color] = [
        Color(red: 0.9, green: 0.2, blue: 0.2), Color(red: 0.2, green: 0.6, blue: 0.2),
        Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.9, green: 0.6, blue: 0.1),
        Color(red: 0.6, green: 0.2, blue: 0.8), Color(red: 0.1, green: 0.7, blue: 0.7),
        Color(red: 0.5, green: 0.5, blue: 0.5),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P105: insert and remove transitions")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("if shown: fade, scale, slide, move, offset, push, asym").font(.system(size: 12))
            HStack(spacing: 6) {
                ForEach(0..<p105Transitions.count, id: \.self) { index in
                    ZStack {
                        if shown {
                            P105Tile(
                                label: p105Transitions[index].0,
                                transition: p105Transitions[index].1,
                                color: Self.colors[index]
                            )
                        }
                    }
                    .frame(width: 60, height: 30)
                }
            }
            .frame(height: 30)

            Text("if/else, push(from: .trailing)").font(.system(size: 12))
            ZStack {
                if useB {
                    P105Tile(label: "B", transition: p105Push, color: Color(red: 0.2, green: 0.4, blue: 0.9))
                } else {
                    P105Tile(label: "A", transition: p105Push, color: Color(red: 0.9, green: 0.6, blue: 0.1))
                }
            }
            .frame(width: 60, height: 30)

            Text("ForEach rows, move(edge: .leading) + opacity").font(.system(size: 12))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    P105Tile(label: "row\(row.id)", transition: p105RowTransition, color: Color(red: 0.3, green: 0.3, blue: 0.8))
                }
            }
            .animation(.linear(duration: 0.8), value: rows)
            .frame(height: 140, alignment: .top)

            Text("no .transition (default fade): if, if/else, ForEach; .identity").font(.system(size: 12))
            HStack(alignment: .top, spacing: 6) {
                ZStack {
                    if defShown {
                        Color(red: 0.8, green: 0.3, blue: 0.3)
                            .frame(width: 60, height: 30)
                            .onDisappear {
                                P105Disappear.times["def-if"] = ProcessInfo.processInfo.systemUptime
                            }
                    }
                }
                .frame(width: 60, height: 30)
                ._effectDiagnosticsLabel("def-if")
                ZStack {
                    if defB {
                        Color(red: 0.2, green: 0.4, blue: 0.9).frame(width: 60, height: 30)
                    } else {
                        Color(red: 0.9, green: 0.6, blue: 0.1).frame(width: 60, height: 30)
                    }
                }
                .frame(width: 60, height: 30)
                ._effectDiagnosticsLabel("def-else")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(defRows) { row in
                        Color(red: 0.3, green: 0.6, blue: row.id == 2 ? 0.9 : 0.3).frame(width: 60, height: 16)
                    }
                }
                .animation(.linear(duration: 0.8), value: defRows)
                .frame(width: 60, height: 70, alignment: .top)
                ._effectDiagnosticsLabel("def-each")
                ZStack {
                    if idShown {
                        Color(red: 0.5, green: 0.5, blue: 0.5)
                            .frame(width: 60, height: 30)
                            .transition(.identity)
                    }
                }
                .frame(width: 60, height: 30)
                ._effectDiagnosticsLabel("def-identity")
            }
            .frame(height: 70, alignment: .top)

            HStack(spacing: 6) {
                Button("Shown") { withAnimation { shown.toggle() } }
                Button("A/B") { withAnimation { useB.toggle() } }
            }
            Text(status)
                .font(.system(size: 11))
                .frame(width: 440, height: 330, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P105Log.write("backend \(String(describing: DefaultBackend.self))")
            P105Log.write("RENDER COMPLETE -- P105 ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepsAfter) {
                MainActor.assumeIsolated { runSteps() }
            }
        }
    }

    var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// The worst distance of the labelled views' last frames from the curve at
    /// `p`: translation in points, opacity and scale as fractions.
    /// 加了標籤的 view 最後一幀與曲線在 `p` 時的最大距離：平移以點、不透明度與縮放以比例表示。
    static func errors(
        _ entries: [(String, AnyTransition)],
        phase: AnyTransition.Phase,
        p: Double
    ) -> (translation: Double, opacity: Double, scale: Double) {
        var translation = 0.0
        var opacity = 0.0
        var scale = 0.0
        for (label, transition) in entries {
            guard let sample = TransitionDiagnostics.samples[label]?.last else {
                translation = .infinity
                continue
            }
            let expected = transition.effects(for: phase, size: p105Size, progress: p)
            let drawn = sample.effects
            let d = drawn.geometric.translation - expected.geometric.translation
            translation = max(translation, abs(d.x), abs(d.y))
            opacity = max(opacity, abs(drawn.visual.opacity - expected.visual.opacity))
            // The drawn scale is floored at a ten-thousandth. / 畫出的縮放下限為萬分之一。
            let ds = drawn.geometric.scale - expected.geometric.scale
            scale = max(scale, abs(ds.x) > 0.00011 ? abs(ds.x) : 0, abs(ds.y) > 0.00011 ? abs(ds.y) : 0)
        }
        return (translation, opacity, scale)
    }

    func runSteps() {
        var lines: [String] = []
        func record(_ line: String) {
            P105Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func next(_ step: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { step() }
            }
        }
        func format(_ e: (translation: Double, opacity: Double, scale: Double)) -> String {
            String(format: "err=%.2f pt, opacity err=%.3f, scale err=%.3f", e.translation, e.opacity, e.scale)
        }
        /// Seconds from `start` to each label's onDisappear. / 從 `start` 到每個標籤 onDisappear 的秒數。
        func disappearances(_ labels: [String], since start: Double) -> String {
            labels.map { label in
                guard let time = P105Disappear.times[label] else { return "\(label) none" }
                return String(format: "%@ %.2f", label, time - start)
            }.joined(separator: ", ")
        }
        /// Seconds from `start` to each label's last transition frame.
        /// 從 `start` 到每個標籤最後一個轉場幀的秒數。
        func lastFrames(_ labels: [String], since start: Double) -> String {
            labels.map { label in
                guard let time = TransitionDiagnostics.samples[label]?.last?.time else { return "\(label) none" }
                return String(format: "%@ %.2f", label, time - start)
            }.joined(separator: ", ")
        }
        let labels = p105Transitions.map(\.0)

        func animatedStep(
            _ name: String,
            phase: AnyTransition.Phase,
            entries: [(String, AnyTransition)],
            duration: Double,
            change: @escaping @MainActor () -> Void,
            done: @escaping @MainActor (Double) -> Void
        ) {
            TransitionDiagnostics.clear()
            let probe = P105Probe()
            probe.started = uptime
            let animation = Animation.linear(duration: duration).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record("\(name) MID p=\(String(format: "%.3f", p)) \(format(Self.errors(entries, phase: phase, p: p)))")
            }
            withAnimation(animation) {
                change()
            } completion: {
                let frames = TransitionDiagnostics.samples[entries[0].0]?.count ?? 0
                record(
                    "\(name) DONE at \(String(format: "%.2f", uptime - probe.started)) s; \(format(Self.errors(entries, phase: phase, p: 1))); \(frames) frames (\(entries[0].0)); mid seen \(probe.midLogged ? "yes" : "no")"
                )
                done(probe.started)
            }
        }

        func insert() {
            animatedStep("INSERT", phase: .insertion, entries: p105Transitions, duration: 1) {
                shown = true
            } done: { _ in next(remove) }
        }

        func remove() {
            P105Disappear.times = [:]
            animatedStep("REMOVE", phase: .removal, entries: p105Transitions, duration: 1) {
                shown = false
            } done: { start in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        record("REMOVE last frame (s): \(lastFrames(labels, since: start))")
                        record("REMOVE onDisappear (s): \(disappearances(labels, since: start))")
                        next(orElse)
                    }
                }
            }
        }

        func orElse() {
            P105Disappear.times = [:]
            TransitionDiagnostics.clear()
            let probe = P105Probe()
            probe.started = uptime
            let animation = Animation.linear(duration: 0.8).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                let a = Self.errors([("A", p105Push)], phase: .removal, p: p)
                let b = Self.errors([("B", p105Push)], phase: .insertion, p: p)
                record("ELSE MID p=\(String(format: "%.3f", p)) A leaving \(format(a)); B arriving \(format(b))")
            }
            withAnimation(animation) {
                useB = true
            } completion: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        record(
                            "ELSE DONE at \(String(format: "%.2f", uptime - probe.started)) s; B \(format(Self.errors([("B", p105Push)], phase: .insertion, p: 1))); onDisappear \(disappearances(["A"], since: probe.started))"
                        )
                        next(each)
                    }
                }
            }
        }

        /// Samples taken by the frame closest to the middle of an 0.8 s tween
        /// that started with its first sample.
        /// 一個以第一個樣本開始的 0.8 秒補間，最接近中點的那一幀。
        func middle(_ label: String) -> (p: Double, sample: TransitionDiagnostics.Sample)? {
            guard let samples = TransitionDiagnostics.samples[label], let first = samples.first else {
                return nil
            }
            let running = samples.filter(\.isRunning)
            guard let mid = running.min(by: { abs($0.time - first.time - 0.4) < abs($1.time - first.time - 0.4) })
            else { return nil }
            let p = mid.phase == .insertion ? mid.presence : 1 - mid.presence
            return (p, mid)
        }

        func rowError(_ label: String, phase: AnyTransition.Phase) -> String {
            guard let (p, sample) = middle(label) else { return "\(label) no frames" }
            let expected = p105RowTransition.effects(for: phase, size: p105Size, progress: p)
            // The progress here is read off the frame itself, so check the
            // frame against the curve and the time against the clock.
            // 這裡的進度取自該幀本身，所以拿該幀對照曲線，拿時間對照時鐘。
            let first = TransitionDiagnostics.samples[label]!.first!.time
            let clockP = min(1, (sample.time - first) / 0.8)
            let d = sample.effects.geometric.translation - expected.geometric.translation
            let opacity = abs(sample.effects.visual.opacity - expected.visual.opacity)
            return String(
                format: "%@ p=%.3f (clock %.3f) err=%.2f pt, opacity err=%.3f, frames %ld",
                label, p, clockP, max(abs(d.x), abs(d.y)), opacity,
                TransitionDiagnostics.samples[label]!.count
            )
        }

        func each() {
            P105Disappear.times = [:]
            TransitionDiagnostics.clear()
            let start = uptime
            rows.remove(at: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                MainActor.assumeIsolated {
                    record("EACH REMOVE \(rowError("row2", phase: .removal)); onDisappear \(disappearances(["row2"], since: start))")
                    TransitionDiagnostics.clear()
                    rows.insert(P105Row(id: 9), at: 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        MainActor.assumeIsolated {
                            record("EACH INSERT \(rowError("row9", phase: .insertion))")
                            next(defaults)
                        }
                    }
                }
            }
        }

        /// The last frame of `label` in `phase`. / `label` 在 `phase` 中的最後一幀。
        func last(_ label: String, _ phase: AnyTransition.Phase) -> TransitionDiagnostics.Sample? {
            TransitionDiagnostics.samples[label]?.last { $0.phase == phase }
        }

        /// The default fade's frame against `p`: opacity err, and whether it
        /// was set on a widget. / 預設淡入淡出的一幀對照 `p`:不透明度誤差，以及它是否設到了 widget 上。
        func fadeError(_ label: String, _ phase: AnyTransition.Phase, p: Double) -> String {
            guard let sample = last(label, phase) else { return "\(label) no frames" }
            let expected = phase == .insertion ? p : 1 - p
            return String(
                format: "%@ opacity %.3f err=%.3f, drawn %@",
                label, sample.effects.visual.opacity, abs(sample.effects.visual.opacity - expected),
                sample.isDrawn ? "yes" : "no"
            )
        }

        /// The default fade's frame nearest the middle of an 0.8 s tween: its
        /// opacity against its own progress, and that progress against the clock.
        /// 0.8 秒補間中最接近中點的預設淡入淡出幀：不透明度對照它自己的進度，進度再對照時鐘。
        func eachFade(_ phase: AnyTransition.Phase) -> String {
            let samples = (TransitionDiagnostics.samples["def-each"] ?? []).filter { $0.phase == phase }
            guard let first = samples.first,
                let mid = samples.filter(\.isRunning).min(by: {
                    abs($0.time - first.time - 0.4) < abs($1.time - first.time - 0.4)
                })
            else { return "def-each no frames" }
            let p = phase == .insertion ? mid.presence : 1 - mid.presence
            let expected = phase == .insertion ? p : 1 - p
            let clockP = min(1, (mid.time - first.time) / 0.8)
            return String(
                format: "p=%.3f (clock %.3f) opacity %.3f err=%.3f, drawn %@, frames %ld",
                p, clockP, mid.effects.visual.opacity, abs(mid.effects.visual.opacity - expected),
                mid.isDrawn ? "yes" : "no", samples.count
            )
        }

        func defaults() {
            TransitionDiagnostics.clear()
            let probe = P105Probe()
            probe.started = uptime
            let insertion = Animation.linear(duration: 1).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record("DEFAULT IF INSERT MID p=\(String(format: "%.3f", p)) \(fadeError("def-if", .insertion, p: p))")
            }
            withAnimation(insertion) {
                defShown = true
            } completion: {
                record(
                    "DEFAULT IF INSERT DONE at \(String(format: "%.2f", uptime - probe.started)) s; \(fadeError("def-if", .insertion, p: 1)); frames \(TransitionDiagnostics.samples["def-if"]?.count ?? 0)"
                )
                next(defaultRemove)
            }
        }

        func defaultRemove() {
            P105Disappear.times = [:]
            TransitionDiagnostics.clear()
            let probe = P105Probe()
            probe.started = uptime
            let removal = Animation.linear(duration: 1).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record("DEFAULT IF REMOVE MID p=\(String(format: "%.3f", p)) \(fadeError("def-if", .removal, p: p))")
            }
            withAnimation(removal) {
                defShown = false
            } completion: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        record(
                            "DEFAULT IF REMOVE DONE; \(fadeError("def-if", .removal, p: 1)); onDisappear \(disappearances(["def-if"], since: probe.started))"
                        )
                        next(defaultElse)
                    }
                }
            }
        }

        func defaultElse() {
            TransitionDiagnostics.clear()
            let probe = P105Probe()
            let animation = Animation.linear(duration: 0.8).onUpdate { p in
                guard !probe.midLogged, p >= 0.5 else { return }
                probe.midLogged = true
                record(
                    "DEFAULT ELSE MID p=\(String(format: "%.3f", p)) leaving \(fadeError("def-else", .removal, p: p)); arriving \(fadeError("def-else", .insertion, p: p))"
                )
            }
            withAnimation(animation) {
                defB = true
            } completion: {
                next(defaultEach)
            }
        }

        func defaultEach() {
            TransitionDiagnostics.clear()
            defRows.remove(at: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    record("DEFAULT EACH REMOVE row2 \(eachFade(.removal))")
                    TransitionDiagnostics.clear()
                    defRows.insert(P105Row(id: 9), at: 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        MainActor.assumeIsolated {
                            record("DEFAULT EACH INSERT row9 \(eachFade(.insertion))")
                            next(defaultNoAnimation)
                        }
                    }
                }
            }
        }

        func defaultNoAnimation() {
            TransitionDiagnostics.clear()
            defShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    defShown = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        MainActor.assumeIsolated {
                            record(
                                "DEFAULT NOANIM frames \(TransitionDiagnostics.samples["def-if"]?.count ?? 0) (insert and remove with no animation)"
                            )
                            next(defaultIdentity)
                        }
                    }
                }
            }
        }

        func defaultIdentity() {
            TransitionDiagnostics.clear()
            withAnimation(.linear(duration: 0.6)) {
                idShown = true
            } completion: {
                withAnimation(.linear(duration: 0.6)) {
                    idShown = false
                } completion: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        MainActor.assumeIsolated {
                            let samples = TransitionDiagnostics.samples["def-identity"] ?? []
                            let opacity = samples.map { abs($0.effects.visual.opacity - 1) }.max() ?? .infinity
                            let moved = samples.map {
                                max(abs($0.effects.geometric.translation.x), abs($0.effects.geometric.translation.y))
                            }.max() ?? .infinity
                            record(
                                "DEFAULT IDENTITY frames \(samples.count) (insert \(samples.filter { $0.phase == .insertion }.count), remove \(samples.filter { $0.phase == .removal }.count)); opacity err=\(String(format: "%.3f", opacity)), translation \(String(format: "%.2f", moved)) pt"
                            )
                            next(jump)
                        }
                    }
                }
            }
        }

        func jump() {
            shown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    TransitionDiagnostics.clear()
                    shown = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        MainActor.assumeIsolated {
                            let running = labels.reduce(0) { count, label in
                                count + (TransitionDiagnostics.samples[label] ?? []).filter(\.isRunning).count
                            }
                            let drawn = labels.reduce(0) { count, label in
                                count + (TransitionDiagnostics.samples[label]?.count ?? 0)
                            }
                            record("JUMP running frames \(running), frames \(drawn)")
                            P105Log.write("STEPS DONE")
                        }
                    }
                }
            }
        }

        insert()
    }
}
