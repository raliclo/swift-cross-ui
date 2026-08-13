import DefaultBackend
import SwiftCrossUI

// P14 iOS (UIKitBackend) repro app: size proposals across rotation, and the
// app background colour after a system theme change.
//
// - #324 On an orientation change the content is given a proposal wider than
//   usual, and the layout only corrects itself on the next layout update.
//   Upstream suspects safe area insets.
// - #254 UIKitBackend detects system theme changes and restyles controls, but
//   does not update the app's background colour.
//
// Both need the running app to report what it was given, not what it looks
// like: #324 is about a transient wrong value that corrects itself, and #254 is
// about one surface staying the wrong colour while others change. So the app
// records the width it receives on every layout pass and keeps the history
// visible, rather than asking the tester to catch a flicker.
//
// Build and run:
//   zsh testapp/compile.sh -ios P14
//   xcrun simctl install swift-cross-ui testapp/output/P14.app
//   xcrun simctl launch swift-cross-ui dev.swiftcrossui.testapp.P14

@main
@HotReloadable
struct P14UIKitApp: App {
    var body: some Scene {
        WindowGroup("P14 rotation and theme") {
            #hotReloadable {
                P14RootView()
            }
        }
        .defaultSize(width: 420, height: 720)
    }
}

struct P14RootView: View {
    // A rolling log of the widths the content has been proposed. #324 shows up
    // as an entry wider than the others appearing immediately after a rotation
    // and then being superseded, which a still screenshot would miss.
    @State var widthLog: [String] = []
    @State var lastWidth = 0
    @State var rotations = 0
    @State var status = "Rotate the device. Widths are logged as they arrive."

    var body: some View {
        VStack(spacing: 12) {
            Text("P14: UIKit rotation and theme")
                .font(.system(size: 18))

            Text(status)

            // ---- #324 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Proposed width across rotation (#324)")

                // GeometryReader reports the proposal this subtree actually
                // received, which is the value #324 is about. Anything measured
                // after the layout settles would already be corrected.
                GeometryReader { geometry in
                    // Int, so a sub-pixel wobble does not fill the log. onChange
                    // takes no parameters here, hence reading the width back
                    // from geometry inside the action.
                    let width = Int(geometry.size.width)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current proposed width: \(width)")
                        Text("Screen edge to edge should match this.")
                    }
                    .onChange(of: width) {
                        lastWidth = width
                        widthLog.append("\(width)")
                        if widthLog.count > 8 {
                            widthLog.removeFirst()
                        }
                    }
                }
                .frame(height: 44)

                Text("Width history: \(widthLog.joined(separator: " -> "))")

                HStack(spacing: 10) {
                    Button("Clear history") {
                        widthLog = []
                        status = "History cleared. Rotate once and read the entries."
                    }

                    Button("Count a rotation (\(rotations))") {
                        rotations += 1
                        status = "Marked rotation \(rotations) at width \(lastWidth)."
                    }
                }
            }

            // ---- #254 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Background colour after a theme change (#254)")

                // Three surfaces that should all follow the system theme. The
                // window background is the one #254 says stays behind, so the
                // comparison is against controls and an explicit colour that do
                // update. No text describes the "correct" colour, because the
                // point is whether these agree with each other.
                VStack(spacing: 0) {
                    Text("1. Plain text on the app background")
                        .padding(6)

                    Button("2. A control, which upstream says does update") {
                        status = "Controls restyle on theme change; the background is the question."
                    }
                    .padding(6)

                    Text("3. Explicit adaptive colour block below")
                        .padding(6)

                    // Color.adaptive resolves per appearance, so this block is a
                    // known-good control: if it flips and the app background
                    // does not, the difference is #254 rather than the theme
                    // change failing to arrive.
                    Color.adaptive(light: .black, dark: .white)
                        .frame(width: 200, height: 24)
                }
            }

            Text(
                "Switch the system appearance while this is open. In the "
                    + "simulator: Features > Toggle Appearance, or "
                    + "`xcrun simctl ui <device> appearance dark`."
            )
        }
        .padding(16)
    }
}
