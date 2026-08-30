import DefaultBackend
import Foundation
import SwiftCrossUI

// P36 API-shape compatibility: SwiftCrossUI forms beside SwiftUI call-site gaps.

enum P36Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P36] \(message)")
        let data = Data("P36 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p36-debug-events.log")
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
        write("RENDER COMPLETE -- P36 ready for API-shape checks")
    }
}

@main
@HotReloadable
struct P36APIShapeApp: App {
    var body: some Scene {
        WindowGroup("P36 API shape compatibility") {
            #hotReloadable {
                P36RootView()
            }
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct P36RootView: View {
    @State var pickerSelection: String? = "Vanilla"
    @State var text = "SwiftCrossUI TextField"

    let choices = ["Vanilla", "Chocolate", "Strawberry"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P36: API-shape compatibility")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("SwiftCrossUI form that compiles")
                .font(.system(size: 15))
            Picker(of: choices, selection: $pickerSelection)
            Text("Picker selection: \(pickerSelection ?? "nil")")
            Button("String label button") {
                P36Diagnostics.write("button clicked")
            }
            TextField("Prompt text", text: $text)
            HStack(spacing: 8) {
                Text("Int spacing 8")
                Text("next")
            }
            .padding(8)

            Divider()
            Text("SwiftUI-shaped call sites missing here")
                .font(.system(size: 15))
            Text("Picker label/content/tag; non-optional Picker selection; Button label builder and ButtonRole")
            Text("LocalizedStringKey Text, Text + Text, Image(systemName:), bundle image lookup")
            Text("List without selection, Section, onDelete, swipeActions, TextField axis/prompt/value-format")
            Text("CGFloat geometry such as padding(8.5), cornerRadius(8.5), HStack(spacing: 8.5)")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P36Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P36Diagnostics.renderComplete()
        }
    }
}
