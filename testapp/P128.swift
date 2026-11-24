import DefaultBackend
import Foundation
import SwiftCrossUI

// P128 tint(_:): the same controls with no tint and with .tint(.green), side by side.
//
// Each column holds an on switch, a checked checkbox, a slider at 60%, a progress
// bar at 60% and a borderless button. The screenshot is the check for the colours:
// on the left every accent-drawn part is the platform's accent (blue on macOS, the
// iOS green switch and blue checkbox on iOS and Android, the theme's accent on GTK
// and WinUI); on the right the switch track, the checkbox fill, the slider's filled
// track, the progress fill and the button label are green, and nothing else changes
// colour. The app also checks what it can measure: that the tint reaches the
// controls through the environment (green in the tinted column, nil in the plain
// one and under an inner .tint(nil)) and that tinting changes no size, then logs
// "P128 PASS" or "P128 FAIL (...)" to p128-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout.
//
// P128 tint(_:):同一組控制項，一欄不加 tint、一欄加 .tint(.green),左右並排。
// 每一欄有一個開啟的開關、一個勾選的核取方塊、一個在 60% 的滑桿、一條 60% 的進度條，以及一顆無框按鈕。
// 截圖用來檢查顏色：左欄每個以強調色繪製的部分都是平台的強調色(macOS 為藍色，iOS 與 Android 為 iOS 的綠色開關與
// 藍色核取方塊,GTK 與 WinUI 為主題的強調色);右欄的開關軌道、核取方塊填色、滑桿已填滿的軌道、進度條填色與按鈕標籤
// 都是綠色，其他顏色都不變。app 也檢查量得到的部分:tint 經由 environment 抵達控制項(加 tint 的欄是綠色，未加的欄
// 與內層 .tint(nil) 之下是 nil),以及加 tint 不改變任何尺寸，然後在 p128-debug-events.log(SCUI_DEBUG_EVENTS_DIR)
// 與 stdout 記下「P128 PASS」或「P128 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P128 {
    static let title = "P128 Tint"

    @MainActor static var sizes: [String: ViewSize] = [:]
    @MainActor static var tints: [String: Color?] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p128-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    @MainActor static func verdict() -> String {
        var failures: [String] = []
        let expected: [(String, Color?)] = [("plain", nil), ("tinted", .green), ("reset", nil)]
        for (name, want) in expected {
            guard let seen = tints[name] else {
                failures.append("\(name) tint not read")
                continue
            }
            log("P128 \(name) tint: \(seen.map { "\($0)" } ?? "nil")")
            if seen != want {
                failures.append("\(name) tint is \(seen.map { "\($0)" } ?? "nil")")
            }
        }
        guard let plain = sizes["plain"], let tinted = sizes["tinted"] else {
            failures.append("columns not measured")
            return "P128 FAIL (\(failures.joined(separator: "; ")))"
        }
        log("P128 columns: \(plain.width)x\(plain.height) -> \(tinted.width)x\(tinted.height)")
        if plain.width != tinted.width || plain.height != tinted.height {
            failures.append("tint changed the column's size")
        }
        return failures.isEmpty ? "P128 PASS" : "P128 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P128App: App {
    var body: some Scene {
        WindowGroup(P128.title) {
            P128View()
        }
        .defaultSize(width: 560, height: 520)
    }
}

struct P128Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P128.sizes[name] = size
        return Color.clear
    }
}

/// Records the tint the environment carries where it is placed.
/// 記下它所在位置的 environment 帶著的 tint。
struct P128TintProbe: View {
    var name: String
    @Environment(\.tint) var tint

    var body: some View {
        P128.tints[name] = .some(tint)
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// One column of controls, measured, with a probe for the tint it sees.
/// 一欄控制項，量測其尺寸，並以探針記下它看到的 tint。
struct P128Column: View {
    var name: String
    @State var isOn = true
    @State var isChecked = true
    @State var value = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name)
            Toggle("Switch", isOn: $isOn).toggleStyle(.switch)
            Toggle("Checkbox", isOn: $isChecked).toggleStyle(.checkbox)
            Slider(value: $value, in: 0...1).frame(width: 160)
            ProgressView(value: 0.6).frame(width: 160)
            Button("Borderless") {}.buttonStyle(.borderless)
            P128TintProbe(name: name)
        }
        .background(
            GeometryReader { proxy in
                P128Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P128View: View {
    @State var verdict = "Measuring"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(P128.title)
            Text(verdict)
            Text("left: no tint, right: .tint(.green)")
            HStack(alignment: .top, spacing: 40) {
                P128Column(name: "plain")
                P128Column(name: "tinted").tint(.green)
            }
            VStack {
                P128TintProbe(name: "reset").tint(nil)
            }
            .tint(.green)
        }
        .padding(24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P128.verdict()
                P128.log(result)
                verdict = result
            }
        }
    }
}
