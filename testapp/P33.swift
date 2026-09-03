import DefaultBackend
import Foundation
import SwiftCrossUI

// P33 missing views: compileable approximations beside the missing SwiftUI names.

enum P33Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P33] \(message)")
        let data = Data("P33 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p33-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
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
        write("RENDER COMPLETE -- P33 ready for missing-view checks")
    }
}

@main
@HotReloadable
struct P33MissingViewsApp: App {
    var body: some Scene {
        WindowGroup("P33 missing views") {
            #hotReloadable {
                P33RootView()
            }
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct P33RootView: View {
    @State var stepperValue = 0
    @State var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P33: missing views")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("These SwiftUI names are compile-time gaps today; approximations are shown where possible.")

            Text("Missing: Form, Section, Label(systemImage:), Stepper, Gauge, DisclosureGroup, LabeledContent, ColorPicker, Link")
                .font(.system(size: 13))

            Divider()
            Text("Stepper approximation")
            HStack(spacing: 8) {
                Button("-") { stepperValue -= 1 }
                Text("value \(stepperValue)")
                Button("+") { stepperValue += 1 }
            }

            Text("DisclosureGroup approximation")
            Button(expanded ? "Hide details" : "Show details") {
                expanded.toggle()
                // Names the new value, so an action file has something better
                // than a picture to check. Added 2026-09-04: the Windows action
                // file for this button had to rest on the capture alone, and an
                // unchanged log after a click is then expected rather than
                // evidence -- the two are indistinguishable without this line.
                // 指出新的值，使動作檔有比截圖更可靠的東西可以檢查。2026-09-04 新增：此按鈕的
                // Windows 動作檔原本只能依靠擷圖，而在那種情況下「點擊後 log 沒有變化」是預期
                // 行為而非證據——少了這一行，兩者無從分辨。
                P33Diagnostics.write("details expanded=\(expanded)")
            }
            if expanded {
                Text("Details are plain conditional content, not a DisclosureGroup.")
            }

            Text("LabeledContent approximation")
            HStack(spacing: 12) {
                Text("Label")
                Text("Value")
            }
        }
        .padding(18)
        .onAppear {
            P33Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P33Diagnostics.write("missing Form Section Label(systemImage:) Stepper Gauge DisclosureGroup LabeledContent ColorPicker Link")
            P33Diagnostics.renderComplete()
        }
    }
}
