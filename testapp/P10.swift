import DefaultBackend
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
            }

            Toggle("Transparent overlay present", active: $overlayEnabled)
                .frame(width: 260)

            VStack(spacing: 4) {
                Text("#478: press Ctrl-Q (Cmd-Q on macOS).")
                Text("The app should quit. If it stays open, the shortcut was not handled.")
            }
        }
        .padding(12)
    }
}
