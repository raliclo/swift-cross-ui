import DefaultBackend
import Foundation
import SwiftCrossUI

// P10 Linux (GtkBackend) repro app: hit testing and shortcuts.
//
// - #454 Transparent containers consume click events, so a button underneath
//   a transparent overlay stops responding even though nothing visible is in
//   the way.
// - #478 Ctrl-Q does not quit the application.
//
// The overlay is transparent rather than invisible: it is laid out and drawn,
// it just has nothing opaque in it. That is the case the issue is about, so
// the test needs it present rather than hidden.
//
// Build this file as a standalone app target.

enum P10Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P10] \(message)")

        guard let data = "P10 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p10-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
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
        write("RENDER COMPLETE -- P10 ready for #454 and #478 checks")
    }
}

@main
@HotReloadable
struct P10HitTestingApp: App {
    var body: some Scene {
        WindowGroup("P10 hit testing and shortcuts") {
            #hotReloadable {
                P10RootView()
            }
        }
        .defaultSize(width: 620, height: 460)
    }
}

struct P10RootView: View {
    @State var directClicks = 0
    @State var coveredClicks = 0
    @State var hiddenClicks = 0
    @State var overlayEnabled = true
    @State var eventLog = "Ready. Ctrl-Q should quit the app."

    var body: some View {
        VStack(spacing: 12) {
            Text("P10: hit testing and shortcuts")
                .font(.system(size: 20))
            Text(eventLog)

            Text("Direct clicks: \(directClicks)   Covered clicks: \(coveredClicks)")

            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("No overlay")
                    Button("Click me") {
                        directClicks += 1
                        eventLog = "Direct button received a click."
                    }
                }

                // #454: the ZStack's upper layer is a transparent colour. It
                // covers the button but should not take its clicks.
                VStack(spacing: 6) {
                    Text("Under a transparent overlay")
                    ZStack {
                        Button("Click me too") {
                            coveredClicks += 1
                            eventLog = "Covered button received a click."
                        }

                        if overlayEnabled {
                            Color.clear
                                .frame(width: 160, height: 60)
                        }
                    }
                    .frame(width: 160, height: 60)
                }

                // allowsHitTesting: the layer here is fully opaque, so nothing
                // about how it is drawn could let a click through. Only the
                // modifier can, which is what makes this a test of the modifier
                // rather than of transparency again.
                //
                // The button underneath is invisible on purpose. If the counter
                // rises, the click reached a button nobody could see, which is
                // the whole claim.
                //
                // allowsHitTesting：此處的圖層完全不透明，因此其繪製方式不可能讓點擊穿透，唯有該
                // modifier 能做到——這正是使本項成為「對該 modifier 的測試」而非又一次透明度測試的
                // 原因。
                //
                // 下方的按鈕刻意是看不見的。若計數上升，代表點擊抵達了一個沒有人看得見的按鈕，
                // 而那正是此項主張的全部內容。
                VStack(spacing: 6) {
                    Text("Under an opaque allowsHitTesting(false)")
                    ZStack {
                        Button("Hidden button") {
                            hiddenClicks += 1
                            eventLog = "Hidden button received a click."
                        }

                        Color.orange
                            .frame(width: 200, height: 60)
                            .allowsHitTesting(false)
                    }
                    .frame(width: 200, height: 60)
                }
            }

            Text("Hidden clicks: \(hiddenClicks)")

            Toggle("Transparent overlay present", active: $overlayEnabled)
                .frame(width: 260)

            VStack(spacing: 4) {
                Text("#478: press Ctrl-Q (Cmd-Q on macOS).")
                Text("The app should quit. If it stays open, the shortcut was not handled.")
            }
        }
        .padding(12)
        .onAppear {
            P10Diagnostics.renderComplete()
        }
    }
}
