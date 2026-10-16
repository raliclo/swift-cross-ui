// P98: GSAP's callbacks and stagger -- onStart, onRepeat, onUpdate, withAnimation's
// completion (GSAP's onComplete) and Animation.stagger -- on a real frame clock.
//
// Four cases, all started in one onAppear, every event logged with its time since
// the call (the first tick arrives 0.1-0.4 s after it, depending on the backend):
//   callbacks  `.linear(duration: 0.8).delay(0.3).repeatCount(3)` with all three
//              callbacks and a completion. Pass: START once, about 0.3 s after the
//              first tick; REPEAT 1 and REPEAT 2 0.8 s apart; DONE about 2.7 s after
//              the first tick; one UPDATES count over 20.
//   two states one withAnimation moving two states. Pass: exactly one TWO DONE.
//   replaced   a 2 s tween replaced 0.5 s in by a 0.5 s tween back to 0. Pass:
//              FIRST DONE at the replacement (about 0.5 s), SECOND DONE about 0.5 s
//              later; the first is not left waiting for its full 2 s.
//   stagger    eight blocks, `.linear(duration: 0.5).stagger(i, of: 8, each: 0.1,
//              from: .center)`. Pass: blocks 3 and 4 move first, then 2 and 5, 1 and
//              6, 0 and 7, each pair 0.1 s after the last.
//
// P98:GSAP 的回呼與 stagger——onStart、onRepeat、onUpdate、withAnimation 的 completion(GSAP 的 onComplete)與
// Animation.stagger——在真正的 frame clock 上。四個案例都在同一個 onAppear 開始，每個事件都記下距離呼叫的時間
// (第一個 tick 依 backend 不同，在呼叫後 0.1–0.4 秒才到)。通過條件見上方英文說明。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P98Log {
    nonisolated(unsafe) static var origin = ProcessInfo.processInfo.systemUptime
    nonisolated(unsafe) static var updates = 0

    /// Appends a line to p98-callbacks.log and stdout. / 在 p98-callbacks.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P98] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p98-callbacks.log")
        guard let data = "P98 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Logs an event with its time since the cases started.
    /// 記錄一個事件，帶上距離案例開始的時間。
    static func mark(_ event: String) {
        write("\(event) at \(String(format: "%.2f", ProcessInfo.processInfo.systemUptime - origin))")
    }
}

@main
@HotReloadable
struct P98App: App {
    var body: some Scene {
        WindowGroup("P98 callbacks and stagger") {
            #hotReloadable {
                P98RootView()
            }
        }
        .defaultSize(width: 440, height: 720)
    }
}

struct P98RootView: View {
    static let track = 240.0
    static let staggerCount = 8

    @State var callbacks = 0.0
    @State var twoA = 0.0
    @State var twoB = 0.0
    @State var replaced = 0.0
    @State var s0 = 0.0
    @State var s1 = 0.0
    @State var s2 = 0.0
    @State var s3 = 0.0
    @State var s4 = 0.0
    @State var s5 = 0.0
    @State var s6 = 0.0
    @State var s7 = 0.0
    @State var staggerOrder = "stagger: running"

    func staggerValue(_ index: Int) -> Double {
        [s0, s1, s2, s3, s4, s5, s6, s7][index]
    }

    func setStagger(_ index: Int, _ value: Double) {
        switch index {
            case 0: s0 = value
            case 1: s1 = value
            case 2: s2 = value
            case 3: s3 = value
            case 4: s4 = value
            case 5: s5 = value
            case 6: s6 = value
            default: s7 = value
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("P98: callbacks, completion, stagger")
                    .font(.system(size: 16))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                bar("callbacks: delay 0.3, repeatCount(3)", callbacks)
                bar("two states, one completion (A)", twoA)
                bar("two states, one completion (B)", twoB)
                bar("replaced at 0.5 s", replaced)
                Text("stagger from .center, each 0.1")
                    .font(.system(size: 12))
                ForEach(Array(0..<Self.staggerCount)) { index in
                    HStack(spacing: 0) {
                        Color(red: 0.15, green: 0.35, blue: 0.8)
                            .frame(width: 16, height: 10)
                            .padding(.leading, staggerValue(index) * Self.track)
                        Spacer()
                    }
                    .frame(width: Self.track + 16)
                }
                Text(staggerOrder)
                    .font(.system(size: 11))
            }
            .padding(16)
        }
        .onAppear {
            P98Log.write("backend \(String(describing: DefaultBackend.self))")
            P98Log.write("RENDER COMPLETE -- P98 ready")
            run()
        }
    }

    func run() {
        P98Log.origin = ProcessInfo.processInfo.systemUptime

        withAnimation(
            .linear(duration: 0.8).delay(0.3).repeatCount(3)
                .onStart { P98Log.mark("START") }
                .onRepeat { P98Log.mark("REPEAT \($0)") }
                .onUpdate { _ in P98Log.updates += 1 }
        ) {
            callbacks = 1
        } completion: {
            P98Log.mark("DONE")
            P98Log.write("UPDATES \(P98Log.updates)")
        }

        withAnimation(.easeOut(duration: 0.6)) {
            twoA = 1
            twoB = 1
        } completion: {
            P98Log.mark("TWO DONE")
        }

        withAnimation(.linear(duration: 2)) {
            replaced = 1
        } completion: {
            P98Log.mark("FIRST DONE")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                withAnimation(.linear(duration: 0.5)) {
                    replaced = 0
                } completion: {
                    P98Log.mark("SECOND DONE")
                }
            }
        }

        for index in 0..<Self.staggerCount {
            withAnimation(
                .linear(duration: 0.5).stagger(index, of: Self.staggerCount, each: 0.1, from: .center)
            ) {
                setStagger(index, 1)
            }
        }
        watchStagger(firstMove: Array(repeating: nil, count: Self.staggerCount))
    }

    /// Polls the stagger blocks every 8 ms and logs when each first moved.
    /// 每 8 毫秒輪詢 stagger 方塊，記錄每一個第一次移動的時間。
    func watchStagger(firstMove: [Double?]) {
        var firstMove = firstMove
        let now = ProcessInfo.processInfo.systemUptime - P98Log.origin
        for index in 0..<Self.staggerCount where firstMove[index] == nil && staggerValue(index) > 0.001 {
            firstMove[index] = now
        }
        if firstMove.contains(where: { $0 == nil }) && now < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                MainActor.assumeIsolated { watchStagger(firstMove: firstMove) }
            }
            return
        }
        let times = firstMove.map { $0.map { String(format: "%.2f", $0) } ?? "-" }
        let order = firstMove.indices.sorted { (firstMove[$0] ?? 99) < (firstMove[$1] ?? 99) }
        P98Log.write("STAGGER first moves \(times.joined(separator: " "))")
        P98Log.write("STAGGER order \(order.map(String.init).joined(separator: " "))")
        staggerOrder = "stagger order: \(order.map(String.init).joined(separator: " "))"
    }
}
