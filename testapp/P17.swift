import DefaultBackend
import SwiftCrossUI

// P17 cross-backend layout comparison: ideal sizing, picker sizing, and two
// documented layout edge cases.
//
// - #264 frame(idealWidth:idealHeight:) sets only the view's full idealSize,
//   not its idealWidthForHeight / idealHeightForWidth. Those are what
//   fixedSize(horizontal:vertical:) reads, so asking for an ideal width and
//   then fixing the horizontal axis does not produce the requested width.
//   SwiftUI does set it for basic cases such as frame(idealWidth: 100) on a
//   text view.
// - #161 Some backends size a Picker from its currently selected item, others
//   from its largest item. Upstream wants this consistent, and leans towards
//   sizing by the largest item.
// - #266 Two layout edge cases upstream wrote down while specifying the layout
//   algorithm, both of which must keep working after any ScrollView or stack
//   optimisation:
//     (a) A constant-aspect-ratio view inside a ScrollView that is slightly too
//         short. The scroll bar has to be shown, but showing it narrows the
//         content, which shortens it via the aspect ratio, which can make the
//         scroll bar look unnecessary. Upstream reports SwiftUI flickering here
//         and believes SwiftCrossUI handles it correctly but inefficiently.
//     (b) An ideal-width VStack given a proposed height. Each child should take
//         its ideal width, the stack should take the widest child's width, and
//         the other children should then expand to match.
//
// Unlike P7-P16 this app is not aimed at one backend. Every check here is a
// comparison: the same build is run under GtkBackend and WinUIBackend and the
// numbers are compared. For #161 that comparison *is* the issue -- it is about
// backends disagreeing, so a single-backend result cannot answer it.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P17LayoutComparisonApp: App {
    var body: some Scene {
        WindowGroup("P17 cross-backend layout") {
            #hotReloadable {
                P17RootView()
            }
        }
        .defaultSize(width: 900, height: 760)
    }
}

// Deliberately very different lengths. If the picker is sized from the
// selected item its width changes as the selection moves; if it is sized from
// the largest item the width stays put.
let p17Options = [
    "S",
    "A medium option",
    "An extremely long option label that dwarfs the others",
]

struct P17RootView: View {
    @State var selection: String? = "S"
    @State var scrollHeight = 120.0
    @State var stackHeight = 140.0
    @State var status = "Run this on both backends and compare the numbers."

    var body: some View {
        VStack(spacing: 14) {
            Text("P17: cross-backend layout comparison")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 840, alignment: .leading)

            // ---- #264 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Ideal width and fixedSize (#264)")

                HStack(spacing: 16) {
                    // The subject: an ideal width, then the horizontal axis
                    // fixed. Its width should come out near 160.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("idealWidth 160 + fixedSize(h:)")
                        P17Measured(label: "subject") {
                            Text("A sentence long enough that its ideal width matters here")
                                .frame(idealWidth: 160)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    // The control: same text, same ideal width, no fixedSize.
                    // Any difference between the two is what #264 is about.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("idealWidth 160 only")
                        P17Measured(label: "control") {
                            Text("A sentence long enough that its ideal width matters here")
                                .frame(idealWidth: 160)
                        }
                    }
                }
            }

            // ---- #161 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Picker sizing (#161)")

                Text("Selected: \(selection ?? "none")")

                P17Measured(label: "picker") {
                    Picker(of: p17Options, selection: $selection)
                }

                HStack(spacing: 8) {
                    Button("Shortest") {
                        selection = p17Options[0]
                        status = "Picker set to the shortest option."
                    }
                    Button("Medium") {
                        selection = p17Options[1]
                        status = "Picker set to the medium option."
                    }
                    Button("Longest") {
                        selection = p17Options[2]
                        status = "Picker set to the longest option."
                    }
                }

                Text("Width changing with the selection means it is sized from")
                Text("the selected item; a constant width means the largest item.")
            }

            // ---- #266 (a) ---------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Aspect ratio inside a ScrollView (#266a)")

                // A 2:1 view inside a scroll view whose height is adjustable in
                // small steps, so the height where the scroll bar appears can
                // be walked over rather than guessed.
                ScrollView {
                    Color.purple
                        .aspectRatio(2.0, contentMode: .fit)
                }
                .frame(width: 300, height: scrollHeight)

                HStack(spacing: 8) {
                    Button("Shorter (\(Int(scrollHeight)))") {
                        scrollHeight = max(40, scrollHeight - 5)
                        status = "Scroll view height \(Int(scrollHeight))."
                    }
                    Button("Taller") {
                        scrollHeight = min(240, scrollHeight + 5)
                        status = "Scroll view height \(Int(scrollHeight))."
                    }
                }

                Text("Step through the heights. The scroll bar may appear and")
                Text("disappear, but it must settle rather than flicker.")
            }

            // ---- #266 (b) ---------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Ideal-width VStack with a proposed height (#266b)")

                // Children of different natural widths, in a stack given a
                // fixed height. All three should end up the width of the
                // widest, and the reported widths say whether they did.
                P17Measured(label: "stack") {
                    VStack(spacing: 2) {
                        Text("Short")
                            .background(Color.blue)
                        Text("A somewhat longer line")
                            .background(Color.green)
                        Text("Mid length")
                            .background(Color.orange)
                    }
                    .frame(height: stackHeight)
                }

                HStack(spacing: 8) {
                    Button("Less height (\(Int(stackHeight)))") {
                        stackHeight = max(40, stackHeight - 20)
                        status = "Stack height \(Int(stackHeight))."
                    }
                    Button("More height") {
                        stackHeight = min(300, stackHeight + 20)
                        status = "Stack height \(Int(stackHeight))."
                    }
                }

                Text("The three coloured bands should all end up the same width.")
            }
        }
        .padding(16)
    }
}

// Reports the size of the view it wraps, so a result can be written down and
// compared between backends instead of being described.
//
// The reader goes in an overlay, which is the only arrangement here that
// measures the subject rather than something else. OverlayModifier lays the
// content out against the original proposal first and then proposes exactly
// that size to the overlay, and a GeometryReader takes the size proposed to it
// and no more -- so the reader reports the subject's own size, and cannot grow
// the result while doing it. Putting the reader beside the subject in an HStack
// would only ever report the reader's own slot, and wrapping the subject in one
// would replace the subject's sizing with the reader's.
//
// The readout is drawn on top of the subject on purpose. What is under test is
// the subject's box, not its contents, and the coloured background makes the
// box visible where the text is covered.
struct P17Measured<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.blue)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    Text("\(label): \(Int(proxy.size.width)) x \(Int(proxy.size.height))")
                }
            }
    }
}
