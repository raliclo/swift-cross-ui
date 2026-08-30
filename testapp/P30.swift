import DefaultBackend
import Foundation
import SwiftCrossUI

// P30 effects and animation: current visual/geometric effects, plus animation gaps.
//
// This app is intentionally compileable. Missing SwiftUI APIs are listed on
// screen rather than written as broken code, so the same binary can be used for
// WSLg and Windows smoke testing.

enum P30Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P30] \(message)")
        let data = Data("P30 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p30-debug-events.log")
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
        write("RENDER COMPLETE -- P30 ready for effects and animation checks")
    }
}

@main
@HotReloadable
struct P30EffectsAnimationApp: App {
    var body: some Scene {
        WindowGroup("P30 effects and animation") {
            #hotReloadable {
                P30RootView()
            }
        }
        .defaultSize(width: 860, height: 620)
    }
}

struct P30RootView: View {
    @State var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P30: effects and animation")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("Toggle the size. Today the change should be instant; there is no animation API.")

            HStack(spacing: 10) {
                Button(wide ? "Use narrow frame" : "Use wide frame") {
                    wide.toggle()
                    P30Diagnostics.write("size toggled wide=\(wide)")
                }
                Text("frame width: \(wide ? 260 : 120)")
            }

            Rectangle()
                .fill(Color(red: 0.10, green: 0.45, blue: 0.85))
                .frame(width: wide ? 260 : 120, height: 56)

            Text("Visual effects")
                .font(.system(size: 15))
            HStack(spacing: 12) {
                P30Sample("control") { P30Wheel() }
                P30Sample("opacity") { P30Wheel().opacity(0.35) }
                P30Sample("blur") { P30Wheel().blur(radius: 3) }
                P30Sample("grayscale") { P30Wheel().grayscale(1) }
            }

            Text("Geometric effects")
                .font(.system(size: 15))
            HStack(spacing: 12) {
                P30Sample("offset") { P30Wheel().offset(x: 20, y: 8) }
                P30Sample("scale") { P30Wheel().scaleEffect(0.65) }
                P30Sample("rotate") { P30Wheel().rotationEffect(.degrees(20)) }
            }

            Text("Missing animation APIs: Animation, withAnimation, .animation(_:value:), .transition, Namespace")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P30Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P30Diagnostics.renderComplete()
        }
    }
}

struct P30Sample<Content: View>: View {
    var label: String
    var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 12))
            content()
                .frame(width: 120, height: 70)
        }
    }
}

struct P30Wheel: View {
    var body: some View {
        AngularGradient(
            colors: [.red, .yellow, .green, .blue, .purple, .red],
            center: UnitPoint(x: 0.5, y: 0.5),
            angle: .degrees(0)
        )
    }
}
