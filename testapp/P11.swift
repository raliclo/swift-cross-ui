import DefaultBackend
import Foundation
import SwiftCrossUI

// P11 macOS (AppKitBackend) repro app: sliders, scrollbars and date pickers.
//
// - #82 Sliders jitter when two of them constrain each other. The minimum
//   slider is clamped below the maximum and vice versa, which SwiftUI absorbs
//   but AppKitBackend turns into a feedback loop.
// - #485 The scrollbar renders pointing the wrong way.
// - #473 Compact DatePicker sizing is off with Liquid Glass.
//
// #404 (window content size after View > Show Tab Bar) and #425 (window not
// focused at launch) are deliberately absent. #404 needs a menu item this app
// cannot drive from its own view tree, and #425 is described upstream as
// intermittent, so a pass/fail step would be misleading. Both are noted in the
// test plan instead.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P11AppKitSizingApp: App {
    var body: some Scene {
        WindowGroup("P11 sliders, scrollbars and pickers") {
            #hotReloadable {
                P11RootView()
            }
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P11RootView: View {
    // The two values constrain each other exactly as RandomNumberGeneratorExample
    // does, which is what #82 reports as jittering.
    @State var minimum = 0.0
    @State var maximum = 100.0

    // Counts how often each binding is written. A clean drag should move one of
    // them monotonically; a feedback loop shows up as both climbing together
    // while the values themselves barely change.
    @State var minimumWrites = 0
    @State var maximumWrites = 0

    @State var date = Date()
    @State var status = "Ready. Drag a slider past the other to test #82."

    var body: some View {
        VStack(spacing: 14) {
            Text("P11: AppKitBackend sliders, scrollbars and pickers")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 700, alignment: .leading)

            // ---- #82 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Mutually clamped sliders (#82)")

                Text(
                    "minimum \(Int(minimum))  /  maximum \(Int(maximum))"
                        + "   writes: min \(minimumWrites), max \(maximumWrites)"
                )

                Slider(
                    value: $minimum.onChange { value in
                        minimumWrites += 1
                        // The clamp that upstream reports as the trigger.
                        if value > maximum {
                            minimum = maximum
                        }
                    },
                    in: 0...100
                )
                .frame(width: 700)

                Slider(
                    value: $maximum.onChange { value in
                        maximumWrites += 1
                        if value < minimum {
                            maximum = minimum
                        }
                    },
                    in: 0...100
                )
                .frame(width: 700)

                HStack(spacing: 10) {
                    Button("Reset counters") {
                        minimumWrites = 0
                        maximumWrites = 0
                        status = "Counters reset. Drag one slider past the other."
                    }

                    Button("Separate them") {
                        minimum = 20
                        maximum = 80
                        status = "Sliders separated; neither clamp is active."
                    }

                    Button("Collide them") {
                        minimum = 50
                        maximum = 50
                        status = "Both at 50: any further drag hits the clamp."
                    }
                }
            }

            // ---- #485 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Scrollbar direction (#485)")

                // Tall content in a short frame, so the vertical scrollbar has a
                // small thumb near the top: easy to see which way it points.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(1...40)) { index in
                            Text("Row \(index) of 40")
                        }
                    }
                    .padding(6)
                }
                .frame(width: 340, height: 130)
            }

            // ---- #473 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Compact DatePicker sizing (#473)")

                HStack(spacing: 10) {
                    DatePicker("Pick a date", selection: $date)

                    // A plain button as a height reference: the picker should
                    // not be visibly taller or shorter than neighbouring
                    // controls, and should not clip its own text.
                    Button("Reference") {
                        status = "Reference button height is the comparison baseline."
                    }
                }
                .frame(width: 700, alignment: .leading)
            }
        }
        .padding(18)
    }
}
