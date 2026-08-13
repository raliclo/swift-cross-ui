import DefaultBackend
import SwiftCrossUI

// P9 Linux (GtkBackend) repro app: text and field sizing.
//
// - #504 TextField/SecureField shrinks in height after the first update, so a
//   field that looked right at launch becomes shorter as soon as anything
//   causes the view to update.
// - #295 Text is not clipped when necessary to reach zero width, so a label
//   refuses to shrink past its text and pushes its container wider.
//
// Nothing here changes the fields themselves. The point of "Force update" is
// that an unrelated state change is enough to trigger #504.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P9TextSizingApp: App {
    var body: some Scene {
        WindowGroup("P9 text and field sizing") {
            #hotReloadable {
                P9RootView()
            }
        }
        .defaultSize(width: 640, height: 520)
    }
}

struct P9RootView: View {
    @State var text = ""
    @State var secureText = ""
    @State var updateCount = 0
    @State var clipWidth = 200.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P9: text and field sizing")
                .font(.system(size: 20))

            // #504: compare the fields against the button beside them. They
            // start the same height; the bug is that the fields lose height
            // after the first update.
            VStack(alignment: .leading, spacing: 6) {
                Text("#504 field height after an update (updates: \(updateCount))")
                HStack(spacing: 8) {
                    TextField("Text field", text: $text)
                        .frame(width: 200)
                    SecureField("Secure field", text: $secureText)
                        .frame(width: 200)
                    Button("Reference") {}
                }
                Button("Force update") {
                    updateCount += 1
                }
            }

            // #295: the label is given less width than its text needs. It
            // should be clipped to the width it was given, not push past it.
            VStack(alignment: .leading, spacing: 6) {
                Text("#295 text clipped to its given width (\(Int(clipWidth)) px)")
                Text("A single line of text that is much wider than the frame it was given")
                    .frame(width: clipWidth)
                    .background(Color.blue)
                HStack(spacing: 8) {
                    Button("Narrower") {
                        clipWidth = max(0, clipWidth - 40)
                    }
                    Button("Wider") {
                        clipWidth = min(400, clipWidth + 40)
                    }
                    Button("Zero width") {
                        clipWidth = 0
                    }
                }
                Text("The blue band marks the frame. Text must not spill past it.")
            }
        }
        .padding(12)
    }
}
