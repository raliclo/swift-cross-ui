import DefaultBackend
import SwiftCrossUI

// P12 Android (AndroidBackend) repro app: button margins, state across
// rotation, and toggle state visibility.
//
// - #632 Buttons have an unnecessary margin. A background colour applied to a
//   button does not reach the button's edges.
// - #580 Rotating the screen resets @State. Upstream reproduced it by switching
//   tabs in GradientsExample and rotating; the tab reverted to the default.
// - #544 Toggle button state is not indicated visually: on and off look the
//   same, because the styling that would distinguish them is missing.
//
// #610 (sheet sizing) is deliberately absent. Upstream describes it as two
// coupled defects, one in the layout system and one in AndroidBackend's
// reported sheet size, and pinning it down needs measurements rather than a
// look-and-see step. It stays in the test plan as an open item.
//
// This app is built for Android, but every check also renders on the host
// platform, so the layout can be sanity-checked before deploying.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P12AndroidChecksApp: App {
    var body: some Scene {
        WindowGroup("P12 Android margins, state and toggles") {
            #hotReloadable {
                P12RootView()
            }
        }
        .defaultSize(width: 420, height: 720)
    }
}

enum P12Tab: String, CaseIterable {
    case first = "First"
    case second = "Second"
    case third = "Third"
}

struct P12RootView: View {
    // #580: this must survive a rotation. It starts on .first, so finding
    // .first after rotating away from it is the failure.
    @State var tab = P12Tab.second

    // Also state, and also expected to survive. A counter makes an accidental
    // reset obvious in a way a tab selection alone does not.
    @State var counter = 0

    // #544: both toggles below must look different when on versus off.
    @State var toggleOn = true
    @State var toggleOff = false

    @State var status = "Rotate the device to test #580."

    var body: some View {
        VStack(spacing: 14) {
            Text("P12: Android margins, state and toggles")
                .font(.system(size: 18))

            Text(status)

            // ---- #580 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("State across rotation (#580)")

                Text("Selected tab: \(tab.rawValue)   counter: \(counter)")

                HStack(spacing: 8) {
                    ForEach(P12Tab.allCases.map(\.rawValue)) { name in
                        Button(name) {
                            tab = P12Tab(rawValue: name) ?? .first
                            status = "Now on \(name). Rotate without touching anything."
                        }
                    }
                }

                Button("Increment counter") {
                    counter += 1
                    status = "Counter is \(counter). Rotate and check it holds."
                }
            }

            // ---- #632 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Button margins (#632)")

                // The blue should reach the edges of each button. Any gap
                // between the blue and the neighbouring green band is the
                // margin that #632 reports.
                VStack(spacing: 0) {
                    Color.green.frame(width: 220, height: 10)

                    Button("-") {
                        counter -= 1
                    }
                    .background(Color.blue)
                    .frame(width: 220)

                    Color.green.frame(width: 220, height: 10)

                    Button("Wide button") {
                        counter += 1
                    }
                    .background(Color.blue)
                    .frame(width: 220)

                    Color.green.frame(width: 220, height: 10)
                }
            }

            // ---- #544 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Toggle state visibility (#544)")

                // Two toggles pinned to opposite states, side by side: if they
                // render identically, that is #544. Comparing against each
                // other avoids relying on memory of what "on" looked like.
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Forced on")
                        Toggle("Toggle", isOn: $toggleOn)
                            .toggleStyle(.button)
                    }

                    VStack(spacing: 4) {
                        Text("Forced off")
                        Toggle("Toggle", isOn: $toggleOff)
                            .toggleStyle(.button)
                    }
                }

                HStack(spacing: 10) {
                    Button("Set both on") {
                        toggleOn = true
                        toggleOff = true
                        status = "Both on: they should look the same as each other."
                    }

                    Button("Set opposite") {
                        toggleOn = true
                        toggleOff = false
                        status = "Opposite states: they must look different."
                    }
                }

                Text("switch style, for comparison:")
                Toggle("Switch", isOn: $toggleOn)
                    .toggleStyle(.switch)
            }
        }
        .padding(16)
    }
}
