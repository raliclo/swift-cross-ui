// P97: delay, speed, repeatCount and repeatForever -- GSAP's delay, timeScale,
// repeat and yoyo under SwiftUI's names.
//
// Eight bars, each a red block driven from 0 to 1 by its own state, all started
// in the same `onAppear`. Every state is sampled every 8 ms for 4.2 s and the
// app logs, per row: when the block first moved, when it first reached 1, how
// many times it turned round (a step back of less than half the track), how
// many times it jumped (a step of more than half: a forward repeat starting
// over, or the last frame of a reversed play landing on the assigned value),
// and the value at the end. A screenshot cannot tell a delay from a slow start;
// these numbers can.
//
// Pass (linear, 1 s, tolerance 0.1 s for the clock's first frame):
//   linear 1s            start 0.0  reach 1.0  turns 0  jumps 0  final 1
//   delay(0.5)           start 0.5  reach 1.5  turns 0  jumps 0  final 1
//   speed(2)             start 0.0  reach 0.5  turns 0  jumps 0  final 1
//   delay(0.5).speed(2)  start 0.5  reach 1.0  -- the delay is real time, as in GSAP
//   repeatCount(3)       reach 1.0  turns 2  jumps 0  final 1 (forward, back, forward)
//   repeatCount(2)       turns 1  jumps 1  final 1 -- back to 0, then SwiftUI's jump
//                        to the assigned value
//   repeatCount(2, autoreverses: false)  turns 0  jumps 1  final 1
//   repeatForever()      turns 3 or 4 in 4.2 s, never finished
//
// P97:delay、speed、repeatCount 與 repeatForever——即 GSAP 的 delay、timeScale、repeat 與 yoyo,用 SwiftUI 的名字。
// 八條軌道，每條有一個紅色方塊，由各自的狀態從 0 驅動到 1,全部在同一個 `onAppear` 開始。每個狀態每 8 毫秒取樣一次、
// 持續 4.2 秒，app 逐列記錄：方塊第一次移動的時間、第一次抵達 1 的時間、折返幾次(後退不到半條軌道)、跳躍幾次
// (一步超過半條軌道：順向重複重新開始，或倒著播放的最後一幀落到被賦予的值)、以及結束時的值。擷圖分不出延遲與
// 起步慢，這些數字分得出來。通過條件見上方英文表格(線性、1 秒，容許 0.1 秒的時鐘首幀誤差)。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P97Log {
    /// Appends a line to p97-timing.log and stdout. / 在 p97-timing.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P97] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p97-timing.log")
        guard let data = "P97 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// What the samples of one row add up to.
/// 一列的樣本歸納出的結果。
struct P97Summary {
    var start: Double?
    var reach: Double?
    var turns = 0
    var jumps = 0
    var final = 0.0

    init(_ samples: [(time: Double, value: Double)]) {
        var direction = 0.0
        for (index, sample) in samples.enumerated() {
            if start == nil && sample.value > 0.001 {
                start = sample.time
            }
            if reach == nil && sample.value >= 0.999 {
                reach = sample.time
            }
            guard index > 0 else { continue }
            let step = sample.value - samples[index - 1].value
            if abs(step) > 0.5 {
                jumps += 1
            } else if step != 0 {
                let sign = step > 0 ? 1.0 : -1.0
                if direction != 0 && sign != direction {
                    turns += 1
                }
                direction = sign
            }
        }
        final = samples.last?.value ?? 0
    }

    var text: String {
        func time(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "-"
        }
        return "start \(time(start)) reach \(time(reach)) turns \(turns) jumps \(jumps) final \(String(format: "%.3f", final))"
    }
}

@main
@HotReloadable
struct P97App: App {
    var body: some Scene {
        WindowGroup("P97 timing control") {
            #hotReloadable {
                P97RootView()
            }
        }
        .defaultSize(width: 440, height: 720)
    }
}

struct P97RootView: View {
    static let track = 240.0
    static let rows: [(String, Animation)] = [
        ("linear 1s", .linear(duration: 1)),
        ("delay(0.5)", .linear(duration: 1).delay(0.5)),
        ("speed(2)", .linear(duration: 1).speed(2)),
        ("delay(0.5).speed(2)", .linear(duration: 1).delay(0.5).speed(2)),
        ("repeatCount(3)", .linear(duration: 1).repeatCount(3)),
        ("repeatCount(2)", .linear(duration: 1).repeatCount(2)),
        ("repeatCount(2, autoreverses: false)", .linear(duration: 1).repeatCount(2, autoreverses: false)),
        ("repeatForever()", .linear(duration: 1).repeatForever()),
    ]

    @State var v0 = 0.0
    @State var v1 = 0.0
    @State var v2 = 0.0
    @State var v3 = 0.0
    @State var v4 = 0.0
    @State var v5 = 0.0
    @State var v6 = 0.0
    @State var v7 = 0.0
    @State var results: [String] = Array(repeating: "running", count: 8)

    func value(_ row: Int) -> Double {
        [v0, v1, v2, v3, v4, v5, v6, v7][row]
    }

    func setValue(_ row: Int, _ value: Double) {
        switch row {
            case 0: v0 = value
            case 1: v1 = value
            case 2: v2 = value
            case 3: v3 = value
            case 4: v4 = value
            case 5: v5 = value
            case 6: v6 = value
            default: v7 = value
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("P97: delay, speed, repeat, yoyo")
                    .font(.system(size: 16))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                ForEach(Array(Self.rows.indices)) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.rows[row].0)
                            .font(.system(size: 12))
                        HStack(spacing: 0) {
                            Color(red: 0.85, green: 0.15, blue: 0.15)
                                .frame(width: 16, height: 16)
                                .padding(.leading, value(row) * Self.track)
                            Spacer()
                        }
                        .frame(width: Self.track + 16)
                        .background(Color(red: 0.92, green: 0.93, blue: 0.95))
                        Text(results[row])
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P97Log.write("backend \(String(describing: DefaultBackend.self))")
            P97Log.write("RENDER COMPLETE -- P97 ready")
            run()
        }
    }

    func run() {
        for row in Self.rows.indices {
            withAnimation(Self.rows[row].1) {
                setValue(row, 1)
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var samples = Array(repeating: [(time: Double, value: Double)](), count: Self.rows.count)
        func sample() {
            let now = ProcessInfo.processInfo.systemUptime - started
            for row in Self.rows.indices {
                let current = value(row)
                if samples[row].last?.value != current {
                    samples[row].append((now, current))
                }
            }
            if now < 4.2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                    MainActor.assumeIsolated { sample() }
                }
            } else {
                var lines: [String] = []
                for row in Self.rows.indices {
                    let line = P97Summary(samples[row]).text
                    P97Log.write("ROW \(Self.rows[row].0): \(line)")
                    lines.append(line)
                }
                results = lines
                P97Log.write("ROWS DONE")
            }
        }
        sample()
    }
}
