import DefaultBackend
import Foundation
import SwiftCrossUI

// P31 focus and keyboard: platform baseline plus missing focus/shortcut APIs.

enum P31Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P31] \(message)")
        let data = Data("P31 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p31-debug-events.log")
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
        write("RENDER COMPLETE -- P31 ready for focus and keyboard checks")
    }
}

@main
@HotReloadable
struct P31FocusKeyboardApp: App {
    var body: some Scene {
        WindowGroup("P31 focus and keyboard") {
            #hotReloadable {
                P31RootView()
            }
        }
        .defaultSize(width: 780, height: 560)
    }
}

struct P31RootView: View {
    @State var text = ""
    @State var enabled = false
    @State var slider = 0.25
    @State var clicks = 0
    @State var alertPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P31: focus and keyboard")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("Use Tab, Space, Return, Escape and Ctrl+Q. Focus is entirely platform-provided today.")

            TextField("Tab should reach this field", text: $text)
            HStack(spacing: 10) {
                Button("Button \(clicks)") {
                    clicks += 1
                    P31Diagnostics.write("button clicked count=\(clicks)")
                }
                Toggle("Toggle", isOn: $enabled)
                Slider(value: $slider, in: 0...1).frame(width: 220)
            }

            Button("Open alert for Escape test") {
                alertPresented = true
                P31Diagnostics.write("alert opened")
            }
            .alert("P31 alert", isPresented: $alertPresented) {
                Button("OK") {
                    P31Diagnostics.write("alert OK")
                }
            }

            Text("Missing APIs: @FocusState, .focused, .focusable, .keyboardShortcut, KeyEquivalent, CommandGroup")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P31Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P31Diagnostics.renderComplete()
        }
    }
}
