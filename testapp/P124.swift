import DefaultBackend
import Foundation
import ImageFormats
import SwiftCrossUI

// P124 scaledToFit(), scaledToFill() and labelsHidden(), each checked by measuring.
//
// A 200x100 image drawn in code, resizable, goes into a 100x100 frame twice:
// scaledToFit must make it 100x50 and scaledToFill 200x100, keeping its 2:1
// ratio. A switch toggle and a stepper are each shown with their label and with
// labelsHidden(), which must make them narrower. A second after the window
// appears the app logs every measurement and "P124 PASS" or "P124 FAIL (...)" to
// p124-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout.
// The toggle is a switch: a button-style toggle -- the macOS default here -- keeps
// its label, which is the button itself.
//
// P124 scaledToFit()、scaledToFill() 與 labelsHidden(),各以量測檢查。一張在程式中畫出的 200x100 可縮放圖片，
// 兩次放進 100x100 的框:scaledToFit 必須使它成為 100x50,scaledToFill 則是 200x100,維持 2:1 的比例。一個
// toggle 與一個 stepper 各以帶標籤及 labelsHidden() 兩種方式顯示，後者必須較窄。視窗出現一秒後,app 在
// p124-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下每項量測，以及「P124 PASS」或「P124 FAIL (...)」。
// toggle 用 switch 樣式:button 樣式的 toggle(此處 macOS 的預設)保留其標籤，因為標籤就是按鈕本身。
//
// Build this file as a standalone app target.

enum P124 {
    static let title = "P124 Scaling and hidden labels"

    @MainActor static var sizes: [String: ViewSize] = [:]

    /// 200x100, orange with a blue left half, so the screenshot shows the ratio.
    /// 200x100,橘色、左半為藍色，讓截圖看得出比例。
    static let picture: ImageFormats.Image<RGBA> = {
        var pixels: [RGBA] = []
        for _ in 0..<100 {
            for x in 0..<200 {
                pixels.append(
                    x < 100
                        ? RGBA(40, 90, 220, 255)
                        : RGBA(240, 140, 30, 255)
                )
            }
        }
        return ImageFormats.Image(width: 200, height: 100, pixels: pixels)
    }()

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p124-debug-events.log")
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
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1 }
        for (name, width, height) in [("fit", 100.0, 50.0), ("fill", 200.0, 100.0)] {
            guard let size = sizes[name] else {
                failures.append("\(name) not measured")
                continue
            }
            log("P124 scaledTo\(name.capitalized): \(size.width)x\(size.height), expected \(width)x\(height)")
            if !near(size.width, width) || !near(size.height, height) {
                failures.append("scaledTo\(name.capitalized) \(size.width)x\(size.height)")
            }
        }
        for name in ["toggle", "stepper"] {
            guard let shown = sizes["\(name) shown"], let hidden = sizes["\(name) hidden"] else {
                failures.append("\(name) not measured")
                continue
            }
            log("P124 \(name) width: \(shown.width) -> \(hidden.width) with labelsHidden")
            if !(hidden.width < shown.width) {
                failures.append("\(name) \(shown.width) -> \(hidden.width)")
            }
        }
        return failures.isEmpty ? "P124 PASS" : "P124 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P124App: App {
    var body: some Scene {
        WindowGroup(P124.title) {
            P124View()
        }
        .defaultSize(width: 520, height: 560)
    }
}

struct P124Measured<Content: View>: View {
    var name: String
    var content: Content

    var body: some View {
        content.background(
            GeometryReader { proxy in
                P124Recorder(name: name, size: proxy.size)
            }
        )
    }
}

struct P124Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P124.sizes[name] = size
        return Color.clear
    }
}

struct P124View: View {
    @State var verdict = "Measuring"
    @State var isOn = true
    @State var count = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(P124.title)
            Text(verdict)
            HStack(alignment: .top, spacing: 24) {
                P124Measured(name: "fit", content: Image(P124.picture).resizable().scaledToFit())
                    .frame(width: 100, height: 100)
                P124Measured(name: "fill", content: Image(P124.picture).resizable().scaledToFill())
                    .frame(width: 100, height: 100)
            }
            HStack(spacing: 24) {
                P124Measured(name: "toggle shown", content: Toggle("Volume label", isOn: $isOn).toggleStyle(.switch))
                    .fixedSize()
                P124Measured(name: "toggle hidden", content: Toggle("Volume label", isOn: $isOn).toggleStyle(.switch).labelsHidden())
                    .fixedSize()
            }
            HStack(spacing: 24) {
                P124Measured(name: "stepper shown", content: Stepper("Count label", value: $count, in: 0...9))
                    .fixedSize()
                P124Measured(
                    name: "stepper hidden",
                    content: Stepper("Count label", value: $count, in: 0...9).labelsHidden()
                )
                .fixedSize()
            }
        }
        .padding(16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P124.verdict()
                P124.log(result)
                verdict = result
            }
        }
    }
}
