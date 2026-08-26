import DefaultBackend
import Foundation
import SwiftCrossUI

// P28 macOS hit-testing: a disabled overlay must let clicks reach the button
// underneath it. This covers AppKitBackend's allowsHitTesting implementation.
//
// P28 macOS hit-testing：停用的 overlay 必須讓點擊穿透至下方按鈕。本 app 覆蓋
// AppKitBackend 的 allowsHitTesting 實作。

enum P28Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P28] \(message)")
        let data = Data("P28 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p28-debug-events.log")
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
        write("RENDER COMPLETE -- P28 ready for hit-testing checks")
    }
}

@main
@HotReloadable
struct P28HitTestingApp: App {
    var body: some Scene {
        WindowGroup("P28 hit testing") {
            #hotReloadable {
                P28RootView()
            }
        }
        .defaultSize(width: 680, height: 420)
    }
}

struct P28RootView: View {
    @State var clicks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P28: AppKit allowsHitTesting")
                .font(.system(size: 20))
            Text("Click the visible button through the blue overlay.")
            Text("Clicks received: \(clicks)")

            ZStack {
                Button("Clickable button underneath") {
                    clicks += 1
                    P28Diagnostics.write("underlying button clicked count=\(clicks)")
                }
                .frame(width: 300, height: 90)

                Color(red: 0.15, green: 0.35, blue: 0.85)
                    .frame(width: 300, height: 90)
                    .allowsHitTesting(false)
            }

            Text("Expected: the blue overlay stays visible and every click increments the counter.")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P28Diagnostics.renderComplete()
        }
    }
}
