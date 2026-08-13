import DefaultBackend
import SwiftCrossUI

// P8 Linux (GtkBackend) repro app: scroll views.
//
// - #417 Giving a ScrollView a cornerRadius does not affect its children, so
//   content shows through the rounded corners instead of being clipped by
//   them.
// - #426 A horizontal ScrollView swallows scroll wheel input that belongs to
//   the vertical ScrollView it sits inside, so the outer view stops scrolling
//   whenever the pointer is over the inner one.
//
// The colours are deliberately loud: #417 is only visible where the child's
// background meets the corner, so a pale child on a pale background would hide
// it.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P8ScrollViewsApp: App {
    var body: some Scene {
        WindowGroup("P8 scroll views") {
            #hotReloadable {
                P8RootView()
            }
        }
        .defaultSize(width: 640, height: 560)
    }
}

struct P8RootView: View {
    @State var outerScrollNote = "Scroll the outer view: the row numbers should move."

    var body: some View {
        VStack(spacing: 10) {
            Text("P8: scroll views")
                .font(.system(size: 20))
            Text(outerScrollNote)

            // #417: the child fills the ScrollView, so its corners are the
            // only place the rounding can be judged. If the red reaches a
            // square corner, the child was not clipped.
            VStack(alignment: .leading, spacing: 4) {
                Text("#417 cornerRadius(20) with a red child")
                ScrollView {
                    Color.red
                        .frame(width: 260, height: 300)
                }
                .frame(width: 260, height: 120)
                .cornerRadius(20)
            }

            // #426: the outer vertical ScrollView contains a horizontal one.
            // Scrolling with the pointer over the inner strip should still
            // move the outer view once the inner one has nowhere left to go.
            VStack(alignment: .leading, spacing: 4) {
                Text("#426 horizontal strip inside a vertical scroll view")
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(0..<12)) { row in
                            if row == 4 {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(0..<14)) { column in
                                            Text("H\(column)")
                                                .padding(8)
                                        }
                                    }
                                }
                                .frame(height: 48)
                            } else {
                                Text("Outer row \(row)")
                                    .padding(6)
                            }
                        }
                    }
                }
                .frame(width: 420, height: 220)
            }
        }
        .padding(12)
    }
}
