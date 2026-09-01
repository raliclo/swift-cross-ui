import DefaultBackend
import Foundation
import SwiftCrossUI

// P43: is a gradient clipped to the shape, or does it fill a rectangle?
//
// That is the whole question. `LinearGradient` has existed for a long time, but
// as an `ElementaryView` with its own backend protocol -- a gradient is a whole
// rectangular widget, so there was no way to put one inside a `Circle()`.
// `Circle().fill(someGradient)` did not compile at all.
//
// The check is visual and cannot be a number: a screenshot either shows a round
// gradient or a square one. What makes it readable is the control beside it --
// the same circle with a flat fill. If the additive change disturbed the old
// path, the control breaks, and that is worth as much as the new case working.
//
// A backend that has not opted in is not broken here. It draws the shape in the
// gradient's midpoint colour and logs once that it did, so the picture shows a
// flat circle rather than nothing. That is deliberate: something plausible and
// wrong reads as a rendering bug, so it has to say so out loud.
//
// P43：漸層會被裁進形狀裡，還是填滿一個矩形？
//
// 問題就這一個。`LinearGradient` 早就存在，但它是一個帶有自己 backend protocol 的
// `ElementaryView`——漸層是一整塊矩形 widget，因此沒有辦法把它放進 `Circle()` 之內。
// `Circle().fill(someGradient)` 根本無法編譯。
//
// 這個檢查是視覺性的，也不可能是一個數字：截圖不是顯示圓形漸層，就是顯示方形漸層。讓它可讀的是
// 旁邊的對照組——同一個圓形，改用平面色填充。若這次的加法式改動擾動了舊路徑，對照組就會壞掉，
// 而那與新功能能動同樣重要。
//
// 尚未加入的 backend 在此不算壞掉。它會用漸層中點的顏色畫出該形狀，並記錄一次它這麼做了，
// 因此畫面顯示的是一個平面色圓形而非空白。這是刻意的：一個看似合理但錯誤的結果會被讀成算繪
// bug，所以它必須明說。
//
// Build this file as a standalone app target.

enum P43Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P43] \(message)")

        guard let data = "P43 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p43-debug-events.log")
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
        write("RENDER COMPLETE -- P43 ready for gradient-fill checks")
    }
}

@main
@HotReloadable
struct P43ShapeFillApp: App {
    var body: some Scene {
        WindowGroup("P43 gradient fills in shapes") {
            #hotReloadable {
                P43RootView()
            }
        }
        .defaultSize(width: 720, height: 420)
    }
}

struct P43RootView: View {
    // Two stops far apart in hue, so a flattened midpoint is obviously not the
    // gradient: purple in the middle of a red-to-blue ramp cannot be mistaken
    // for the ramp itself.
    // 兩個色相相距甚遠的 stop，使被壓平的中點明顯不等於漸層本身：紅到藍之間的紫色，不可能被
    // 誤認為那道漸層。
    var ramp: Gradient {
        Gradient(colors: [.red, .blue])
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("P43: gradient fills, clipped to the shape")
                .font(.system(size: 18))

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    // The one that matters. A square gradient here means the
                    // fill was not clipped; a flat purple circle means this
                    // backend degraded and should have logged saying so.
                    // 關鍵的那一個。此處若出現方形漸層，代表填充未被裁切；若是平面紫色圓形，
                    // 代表此 backend 降級了，而它應該已經記錄說明。
                    Circle()
                        .fill(ramp)
                        .frame(width: 120, height: 120)
                    Text("circle + gradient")
                }

                VStack(spacing: 4) {
                    // The control. If the additive change disturbed the flat
                    // path, this breaks -- and that matters as much as the
                    // gradient working.
                    // 對照組。若加法式的改動擾動了平面色路徑，這一個就會壞掉——而那與漸層能動
                    // 同樣重要。
                    Circle()
                        .fill(Color.green)
                        .frame(width: 120, height: 120)
                    Text("circle + flat (control)")
                }

                VStack(spacing: 4) {
                    Rectangle()
                        .fill(ramp)
                        .frame(width: 120, height: 120)
                    Text("rectangle + gradient")
                }
            }

            Text(
                "The left circle must be a round gradient. A square one means "
                    + "the fill was not clipped; a flat one means this backend "
                    + "degraded and logged a warning."
            )
            Text("左邊的圓必須是圓形漸層。方形代表填充未被裁切；平面色代表此 backend 降級並記錄了警告。")
        }
        .padding(20)
        .onAppear {
            P43Diagnostics.write(
                "arguments \(CommandLine.arguments.joined(separator: " | "))"
            )
            P43Diagnostics.renderComplete()
        }
    }
}
