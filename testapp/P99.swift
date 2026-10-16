// P99: GSAP's timeline -- AnimationTimeline and TimelinePlayer: play, pause,
// reverse, restart, seek, timeScale and a slider bound to the progress.
//
// Three blocks on one timeline, all linear so every value can be checked by
// hand: a 0-1 s; b 0.5 s starting 0.25 s after a (`.withPrevious(offset: 0.25)`);
// a label "c" 0.2 s after b ends, at 0.95 s; c 0.5 s from the label. 1.45 s in all.
//
// The app runs four steps by itself and logs each, times since the step began:
//   PLAY      play from 0. Pass: ENDED near 1.45 s plus the first frame, and the
//             slider followed (SLIDER > 0.99 at the end).
//   SEEK      seek(progress: 0.5), time 0.725 s. Pass: a 0.725, b 0.950, c 0.000,
//             exactly, with no frame needed.
//   REVERSE   reverse from 0.725 s. Pass: AT START near 0.725 s; a, b, c all 0.
//   FAST      timeScale 2, play from 0. Pass: ENDED near 0.725 s.
// The buttons and the slider stay live afterwards for driving by hand.
//
// P99:GSAP 的 timeline——AnimationTimeline 與 TimelinePlayer:播放、暫停、倒轉、重來、跳轉、timeScale,以及綁到
// 進度的 slider。一條 timeline 上有三個方塊，全部是線性的，每個值都能手算：a 0–1 秒;b 0.5 秒，比 a 晚 0.25 秒開始
// (`.withPrevious(offset: 0.25)`);標籤 "c" 在 b 結束後 0.2 秒，即 0.95 秒;c 從標籤開始 0.5 秒。總長 1.45 秒。
// app 自己執行四個步驟並逐一記錄(時間從每個步驟開始算),通過條件見上方英文說明。之後按鈕與 slider 仍可手動操作。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P99Log {
    /// Appends a line to p99-timeline.log and stdout. / 在 p99-timeline.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P99] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p99-timeline.log")
        guard let data = "P99 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P99App: App {
    var body: some Scene {
        WindowGroup("P99 timeline") {
            #hotReloadable {
                P99RootView()
            }
        }
        .defaultSize(width: 440, height: 520)
    }
}

struct P99RootView: View {
    static let track = 240.0

    @State var a = 0.0
    @State var b = 0.0
    @State var c = 0.0
    @State var scrub = 0.0
    @State var player: TimelinePlayer?
    @State var status = "steps: running"

    func values() -> String {
        String(format: "a %.3f b %.3f c %.3f", a, b, c)
    }

    func makePlayer() -> TimelinePlayer {
        var timeline = AnimationTimeline()
        timeline.add(.linear(duration: 1)) { a = $0 }
        timeline.add(.linear(duration: 0.5), at: .withPrevious(offset: 0.25)) { b = $0 }
        timeline.addLabel("c", at: .afterPrevious(gap: 0.2))
        timeline.add(.linear(duration: 0.5), at: .label("c")) { c = $0 }
        let player = TimelinePlayer(timeline)
        player.onUpdate = { scrub = $0 }
        return player
    }

    func bar(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12))
            HStack(spacing: 0) {
                Color(red: 0.85, green: 0.15, blue: 0.15)
                    .frame(width: 16, height: 16)
                    .padding(.leading, value * Self.track)
                Spacer()
            }
            .frame(width: Self.track + 16)
            .background(Color(red: 0.92, green: 0.93, blue: 0.95))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P99: timeline")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            bar("a: 0-1 s", a)
            bar("b: with a, +0.25, 0.5 s", b)
            bar("c: at label c (0.95 s), 0.5 s", c)
            HStack(spacing: 6) {
                Button("Play") { player?.play() }
                Button("Pause") { player?.pause() }
                Button("Reverse") { player?.reverse() }
                Button("Restart") { player?.restart() }
            }
            Slider(
                value: Binding(get: { scrub }, set: { player?.seek(progress: $0) }),
                in: 0...1
            )
            .frame(width: Self.track + 16)
            Text(String(format: "progress %.3f", scrub))
            Text(status)
                .font(.system(size: 11))
        }
        .padding(16)
        .onAppear {
            P99Log.write("backend \(String(describing: DefaultBackend.self))")
            P99Log.write("RENDER COMPLETE -- P99 ready")
            let player = makePlayer()
            self.player = player
            runSteps(player)
        }
    }

    /// PLAY, SEEK, REVERSE, FAST, each waiting for the last to stop.
    /// 依序執行 PLAY、SEEK、REVERSE、FAST,每一步等前一步停下來。
    func runSteps(_ player: TimelinePlayer) {
        var lines: [String] = []
        func record(_ line: String) {
            P99Log.write(line)
            lines.append(line)
            status = lines.joined(separator: "\n")
        }
        func whenStopped(_ started: Double, _ then: @escaping @MainActor (Double) -> Void) {
            if player.isPlaying && ProcessInfo.processInfo.systemUptime - started < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                    MainActor.assumeIsolated { whenStopped(started, then) }
                }
            } else {
                then(ProcessInfo.processInfo.systemUptime - started)
            }
        }

        let playStart = ProcessInfo.processInfo.systemUptime
        player.play()
        whenStopped(playStart) { elapsed in
            record("PLAY ENDED at \(String(format: "%.2f", elapsed)); \(values()); SLIDER \(String(format: "%.3f", scrub))")
            player.seek(progress: 0.5)
            record("SEEK 0.5 -> time \(String(format: "%.3f", player.time)); \(values())")
            let reverseStart = ProcessInfo.processInfo.systemUptime
            player.reverse()
            whenStopped(reverseStart) { elapsed in
                record("REVERSE AT START at \(String(format: "%.2f", elapsed)); \(values())")
                player.timeScale = 2
                let fastStart = ProcessInfo.processInfo.systemUptime
                player.play()
                whenStopped(fastStart) { elapsed in
                    record("FAST ENDED at \(String(format: "%.2f", elapsed)); \(values())")
                    player.timeScale = 1
                    P99Log.write("STEPS DONE")
                }
            }
        }
    }
}
