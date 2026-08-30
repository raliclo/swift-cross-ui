import DefaultBackend
import Foundation
import SwiftCrossUI

// P32 accessibility baseline: inspect this window with platform accessibility tools.

enum P32Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P32] \(message)")
        let data = Data("P32 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p32-debug-events.log")
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
        write("RENDER COMPLETE -- P32 ready for accessibility inspection")
    }
}

@main
@HotReloadable
struct P32AccessibilityApp: App {
    var body: some Scene {
        WindowGroup("P32 accessibility") {
            #hotReloadable {
                P32RootView()
            }
        }
        .defaultSize(width: 760, height: 560)
    }
}

struct P32RootView: View {
    @State var text = ""
    @State var toggle = false
    @State var slider = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P32: accessibility baseline")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("Inspect with Accerciser on Linux or Accessibility Insights / inspect.exe on Windows.")

            Button("Labelled button") {
                P32Diagnostics.write("labelled button clicked")
            }
            Button("") {
                P32Diagnostics.write("empty-label button clicked")
            }
            .help("Icon-only equivalent with tooltip but no accessibility API")
            TextField("Placeholder text", text: $text)
            Toggle("Toggle label", isOn: $toggle)
            Slider(value: $slider, in: 0...1)
                .frame(width: 260)
            ProgressView(Text("Progress label"), value: slider)
            Rectangle()
                .fill(Color(red: 0.20, green: 0.55, blue: 0.85))
                .frame(width: 120, height: 70)

            Text("Missing APIs: accessibilityLabel, accessibilityHint, accessibilityValue, accessibilityHidden, accessibilityIdentifier")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P32Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P32Diagnostics.renderComplete()
        }
    }
}
