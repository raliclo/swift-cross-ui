import DefaultBackend
import Foundation
import SwiftCrossUI

// P66: does `withAnimation` actually produce intermediate values (#28)?
//
// The number is checked: `ls testapp` gives P50..P65.
//
// **THE ASSERTION IS THE SEQUENCE, NOT THE ENDPOINT.** An animation that jumped
// straight to its target would leave the view in exactly the right place, and a
// screenshot taken after it finished could not tell the difference. So this app
// records every value the state takes and prints the count, the first few, the
// duration and whether the sequence is monotonic -- the four things that
// separate a tween from an assignment.
//
// It also runs a NON-animatable state change beside it. `Bool` has no
// intermediate values, so that one must record exactly two entries; if it
// records more, the driver is inventing steps for a type it cannot interpolate.
//
// P66:`withAnimation` 真的會產出中間值嗎(#28)?
//
// 編號是查過的:`ls testapp` 給出 P50..P65。
//
// **判定的是那個序列，而不是終點。** 一個「直接跳到目標」的動畫會把 view 留在完全正確的位置，而一張
// 在它結束之後拍的截圖分辨不出差別。因此這支 app 記錄那個狀態取過的每一個值，並印出:數量、最初幾個、
// 歷時、以及該序列是否單調——這四項正是「補間」與「賦值」的分野。
//
// 它旁邊還跑一個**不可動畫**的狀態改變。`Bool` 沒有中間值，因此那一個必須恰好記錄兩筆;若它記錄得更多，
// 就代表 driver 正在為一個它插值不了的型別捏造步驟。

enum P66Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P66] \(message)")

        guard let data = "P66 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p66-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P66 ready")
    }
}

@main
@HotReloadable
struct P66App: App {
    var body: some Scene {
        WindowGroup("P66 animation") {
            #hotReloadable {
                P66RootView()
            }
        }
        .defaultSize(width: 560, height: 420)
    }
}

// **A body with a side effect stopped `onAppear` from ever firing**, which is
// why the samples are taken by polling instead.
//
// The second version of this app recorded the value from inside `body`. It
// compiled, the window opened, `body` ran eleven times -- and `onAppear` never
// ran once, so the animation was never started and the log said nothing at all.
// Whatever the cause inside the framework, a `body` that only builds views is
// the shape everything else here relies on, and a test app is the wrong place to
// find out what happens when it does not.
//
// **一個帶有副作用的 body，讓 `onAppear` 從未觸發**——這正是那些樣本改以輪詢取得的原因。
//
// 本 app 的第二版是在 `body` 裡面記錄那個值的。它編得過、視窗開得起來、`body` 執行了十一次——而
// `onAppear` 一次都沒有執行，因此那個動畫從未被啟動，日誌裡什麼都沒有。無論框架內部的成因是什麼，
// 「`body` 只用來建立 view」是此處其他一切所倚賴的形狀，而一支測試 app 不是拿來探究「不這麼做會發生
// 什麼事」的地方。

struct P66RootView: View {
    @State var offset = 0.0
    @State var flag = false
    @State var summary = "not run yet"

    var body: some View {
        // Recorded here because this is where the value is READ: every
        // intermediate the driver produces reaches the view through a re-render,
        // and that is the thing the app is asserting about.
        // 在此處記錄，因為這裡才是那個值被**讀取**之處:driver 產出的每一個中間值，都是透過一次重新
        // 算繪抵達這個 view 的——而那正是這支 app 所要斷言的東西。
        VStack(alignment: .leading, spacing: 10) {
            Text("P66: withAnimation (#28)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text(summary)
                .frame(width: 480)

            // The marker moves with the animated value, so a capture during the
            // animation shows it part-way rather than at either end.
            // 這個標記隨著被動畫的值移動，因此一張在動畫進行中拍下的擷圖，會顯示它停在半路，而不是
            // 停在任何一端。
            // Inside a fixed-width row, so the marker's x maps one-to-one to
            // `offset`. Without it the padding widens the content, the content
            // is centred, and the marker moves half as far as the value does --
            // the same trap P65 records, and the reason a screenshot alone is
            // never the assertion here.
            // 放在一個固定寬度的列裡，好讓標記的 x 與 `offset` 一對一對應。少了它，那個 padding 會
            // 撐寬內容、內容是置中的，於是標記移動的距離只有該值的一半——與 P65 記載的是同一個陷阱，
            // 也正是「此處絕不以截圖本身作為判定」的原因。
            HStack(spacing: 0) {
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .frame(width: 20, height: 20)
                    .padding(.leading, offset)
                Spacer()
            }
            .frame(width: 480)

            Text("offset: \(Int(offset))")
            Text("flag: \(flag ? "true" : "false")")
        }
        .padding(20)
        .onAppear {
            P66Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P66Diagnostics.renderComplete()
            run()
        }
    }

    func run() {
        var samples: [(time: Double, value: Double)] = []
        let started = ProcessInfo.processInfo.systemUptime

        withAnimation(.linear(duration: 0.5)) {
            offset = 200
            flag = true
        }
        // One assignment, and a `Bool` cannot tween, so this must stay 1.
        // 一次賦值，而 `Bool` 不能補間，因此這個值必須維持為 1。
        let flagAssignments = 1

        // Polled rather than observed. 8 ms is well under a frame at any refresh
        // rate this runs on, so the sampler cannot be the thing that limits how
        // many distinct values are seen -- if the count comes back low, that is
        // the animation and not the measurement.
        // 採輪詢而非觀察。8 毫秒遠短於本程式所在的任何更新率下的一幀，因此這個取樣器不可能成為
        // 「看得到幾個相異值」的限制——若數量偏低，那是動畫的問題，不是量測的問題。
        func sample() {
            let value = offset
            if samples.last?.value != value {
                samples.append((ProcessInfo.processInfo.systemUptime - started, value))
            }
            if ProcessInfo.processInfo.systemUptime - started < 1.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                    MainActor.assumeIsolated { sample() }
                }
            } else {
                report(samples: samples, flagSamples: flagAssignments)
            }
        }
        sample()
    }

    func report(samples: [(time: Double, value: Double)], flagSamples: Int) {
        guard samples.count >= 2 else {
            summary = "ANIMATION DID NOT RUN: \(samples.count) sample(s)"
            P66Diagnostics.write(summary)
            return
        }
        let values = samples.map(\.value)
        let monotonic = zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
        let span = samples.last!.time - samples.first!.time
        summary = String(
            format: "SAMPLES %d over %.2fs; first %.1f last %.1f; monotonic %@",
            samples.count,
            span,
            values.first!,
            values.last!,
            monotonic ? "yes" : "NO"
        )
        P66Diagnostics.write(summary)
        P66Diagnostics.write(
            "FIRST FIVE " + values.prefix(5).map { String(format: "%.1f", $0) }.joined(separator: " ")
        )
        P66Diagnostics.write(
            "LAST THREE " + values.suffix(3).map { String(format: "%.1f", $0) }.joined(separator: " ")
        )
        P66Diagnostics.write("BOOL assignments: \(flagSamples) (must be 1: a Bool cannot tween)")
        P66Diagnostics.write("ANIMATION MEASURED")

        // A slow return trip, so that a screenshot taken at any ordinary moment
        // catches the marker part-way instead of at one end. A picture of the
        // finished state cannot tell an animation from an assignment; this one
        // can.
        // 一段慢速的回程，好讓「在任何一個尋常時刻」拍下的截圖，都能抓到那個標記停在半路、而不是停在
        // 某一端。一張「已完成狀態」的圖分辨不出動畫與賦值;這一張可以。
        withAnimation(.easeInOut(duration: 6)) {
            offset = 20
        }
        P66Diagnostics.write("slow return started: 200 -> 20 over 6s")
    }
}
