import DefaultBackend
import Foundation
import SwiftCrossUI

// P35 state and scene composition: compileable state baseline plus structural gaps.

enum P35Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P35] \(message)")
        let data = Data("P35 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p35-debug-events.log")
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
        write("RENDER COMPLETE -- P35 ready for state and scene checks")
    }
}

@main
@HotReloadable
struct P35StateSceneApp: App {
    var body: some Scene {
        WindowGroup("P35 state and scene") {
            #hotReloadable {
                P35RootView()
            }
        }
        .defaultSize(width: 760, height: 560)
    }
}

struct P35RootView: View {
    @State var count = 0
    @State var toggle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P35: state and scene composition")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("State baseline: count \(count), toggle \(toggle)")

            HStack(spacing: 8) {
                Button("Increment") {
                    count += 1
                    P35Diagnostics.write("count=\(count)")
                }
                Toggle("Toggle state", isOn: $toggle)
            }

            Text("Missing state APIs: @StateObject, @ObservedObject, @SceneStorage, Binding.constant, .environmentObject")
                .font(.system(size: 13))
            Text("Missing scene-builder APIs: Scene body composition, buildIf, buildOptional, buildEither")
                .font(.system(size: 13))
            Text("Missing view-builder API: buildLimitedAvailability for if #available in view bodies")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P35Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P35Diagnostics.renderComplete()
        }
    }
}
