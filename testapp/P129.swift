import DefaultBackend
import Foundation
import SwiftCrossUI

// P129 controlSize(_:): the same controls at .small, .regular and .large.
//
// Each row is one control -- a button, a stepper, a switch, a checkbox, a slider, a
// menu picker, a text field, a progress bar and a spinner -- shown at the three
// sizes side by side. A second after the window appears the app compares the sizes
// each one was laid out at and logs "P129 PASS" when, for every control, small is
// smaller than regular and regular smaller than large (no dimension shrinks and at
// least one grows), or "P129 FAIL (...)" naming the controls that did not, to
// p129-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout. The screenshot shows the
// controls drawn whole at each size.
//
// P129 controlSize(_:):同一組控制項分別以 .small、.regular、.large 顯示。
// 每一列是一種控制項——按鈕、stepper、switch、checkbox、slider、選單 picker、文字欄位、進度條與轉圈——三種尺寸並排。
// 視窗出現一秒後，app 比較每個控制項排版所得的尺寸：每一種都是 small 小於 regular、regular 小於 large(沒有任何
// 維度變小，且至少一個維度變大)時，在 p129-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P129 PASS」,
// 否則記下「P129 FAIL (...)」並列出不符合的控制項。截圖顯示各尺寸的控制項都完整畫出。
//
// Build this file as a standalone app target.

enum P129 {
    static let title = "P129 Control size"
    static let sizes: [(String, ControlSize)] = [
        ("small", .small), ("regular", .regular), ("large", .large),
    ]
    static let controls = [
        "button", "stepper", "switch", "checkbox", "slider", "picker", "textfield",
        "bar", "spinner",
    ]

    @MainActor static var measured: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p129-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    /// Whether `a` is smaller than `b`: neither dimension larger, one smaller.
    /// `a` 是否小於 `b`:沒有任何維度較大，且至少一個維度較小。
    static func smaller(_ a: ViewSize, _ b: ViewSize) -> Bool {
        a.width <= b.width && a.height <= b.height
            && (a.width < b.width || a.height < b.height)
    }

    @MainActor static func verdict() -> String {
        var failures: [String] = []
        for control in controls {
            let found = sizes.map { measured["\(control) \($0.0)"] }
            guard let small = found[0], let regular = found[1], let large = found[2] else {
                failures.append("\(control) not measured")
                continue
            }
            log(
                "P129 \(control): small \(small.width)x\(small.height), "
                    + "regular \(regular.width)x\(regular.height), "
                    + "large \(large.width)x\(large.height)"
            )
            if !smaller(small, regular) {
                failures.append("\(control) small is not smaller than regular")
            }
            if !smaller(regular, large) {
                failures.append("\(control) regular is not smaller than large")
            }
        }
        return failures.isEmpty ? "P129 PASS" : "P129 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P129App: App {
    var body: some Scene {
        WindowGroup(P129.title) {
            P129View()
        }
        .defaultSize(width: 760, height: 720)
    }
}

struct P129Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P129Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P129Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P129.measured[name] = size
        return Color.clear
    }
}

/// One control at the three sizes, each in a column 90 points wide, so all three fit a
/// phone (at 200 the large column ran off an Android screen, CI run 45505727478).
/// 一種控制項的三種尺寸，各放在 90 點寬的欄中，讓三欄都放得進手機(200 點時 Android 的 large 欄超出畫面，CI run 45505727478)。
struct P129Row<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(name).frame(width: 64, alignment: .leading)
            ForEach(P129.sizes.map(\.0), id: \.self) { sizeName in
                P129Measured(name: "\(name) \(sizeName)", content: content)
                    .controlSize(P129.sizes.first { $0.0 == sizeName }!.1)
                    .frame(width: 90, alignment: .leading)
            }
        }
    }
}

struct P129View: View {
    @State var verdict = "Measuring"
    @State var count = 3
    @State var isOn = true
    @State var isChecked = true
    @State var value = 0.5
    @State var fruit: String? = "Apple"
    @State var text = "Text"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(P129.title)
            Text(verdict)
            HStack(spacing: 12) {
                Text("").frame(width: 64, alignment: .leading)
                ForEach(P129.sizes.map(\.0), id: \.self) { sizeName in
                    Text(sizeName).frame(width: 90, alignment: .leading)
                }
            }
            P129Row(name: "button", content: Button("Button") {})
            P129Row(name: "stepper", content: Stepper("", value: $count).labelsHidden())
            P129Row(
                name: "switch",
                content: Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
            )
            P129Row(
                name: "checkbox",
                content: Toggle("", isOn: $isChecked).toggleStyle(.checkbox).labelsHidden()
            )
            P129Row(name: "slider", content: Slider(value: $value, in: 0...1))
            P129Row(
                name: "picker",
                content: Picker(of: ["Apple", "Banana"], selection: $fruit)
                    .pickerStyle(.menu)
            )
            P129Row(name: "textfield", content: TextField("Name", text: $text))
            P129Row(name: "bar", content: ProgressView(value: 0.6))
            P129Row(name: "spinner", content: ProgressView())
        }
        .padding(16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P129.verdict()
                P129.log(result)
                verdict = result
            }
        }
    }
}
