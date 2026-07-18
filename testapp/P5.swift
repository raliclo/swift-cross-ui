import DefaultBackend
import SwiftCrossUI

// P5 Windows repro app:
// - #675 WinUIBackend: support displaying multiple alerts at once.
//
// Verifies that alerts on separate windows can be shown simultaneously
// (instead of queuing behind a single app-wide dialog), and that stacking
// several alerts on the same window restores each earlier alert once the
// one on top of it is dismissed.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P5MultiWindowAlertsApp: App {
    var body: some Scene {
        WindowGroup("P5 multi-window alerts", id: "p5-main") {
            #hotReloadable {
                P5AlertWindowView(windowLabel: "Main")
            }
        }
        .defaultSize(width: 480, height: 380)

        WindowGroup("P5 secondary window", id: "p5-secondary") {
            #hotReloadable {
                P5AlertWindowView(windowLabel: "Secondary")
            }
        }
        .defaultSize(width: 480, height: 380)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct P5AlertWindowView: View {
    var windowLabel: String

    @State var showAlertA = false
    @State var showAlertB = false
    @State var showAlertC = false
    @State var eventLog = "Ready."

    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("P5: \(windowLabel) window")
                .font(.system(size: 18))

            Text(
                "Verifies #675 (Fixed): alerts on different windows should show at the same time instead of queuing, and alerts stacked on the same window should restore the earlier alert once the later one closes."
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open another window") {
                openWindow(id: "p5-secondary")
            }

            HStack {
                Button("Show Alert A") {
                    eventLog = "\(windowLabel): showing Alert A"
                    showAlertA = true
                }

                Button("Show Alert B (stacks on A)") {
                    eventLog = "\(windowLabel): showing Alert B"
                    showAlertB = true
                }

                Button("Show Alert C (stacks on A+B)") {
                    eventLog = "\(windowLabel): showing Alert C"
                    showAlertC = true
                }
            }

            Text(eventLog)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .alert("Alert A (\(windowLabel))", isPresented: $showAlertA) {
            Button("OK") {
                eventLog = "\(windowLabel): Alert A dismissed"
            }
        }
        .alert("Alert B (\(windowLabel))", isPresented: $showAlertB) {
            Button("OK") {
                eventLog = "\(windowLabel): Alert B dismissed"
            }
        }
        .alert("Alert C (\(windowLabel))", isPresented: $showAlertC) {
            Button("OK") {
                eventLog = "\(windowLabel): Alert C dismissed"
            }
        }
    }
}
