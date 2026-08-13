import DefaultBackend
import SwiftCrossUI

// P13 layout and view-graph repro app: ForEach identity, scroll view text
// clipping, split view minimum width, and Group inside ZStack.
//
// - #415 The message list benchmark crashes with AppKitBackend. Upstream traced
//   it to the fallback codepath for non-Identifiable ForEach elements handing
//   the backend duplicate child views; making the element Identifiable works
//   around it.
// - #595 Text inside a ScrollView is cut off when it should not be.
//   `.fixedSize()` works around it. Introduced between 0.3.0 and 0.4.0.
// - #291 NavigationSplitView deduces its minimum width correctly but never
//   moves the split to honour it. Upstream reports AppKitBackend affected and
//   GtkBackend not.
// - #158 A Group inside a ZStack lays its children out along the container's
//   orientation instead of the z axis.
//
// #415 crashes on purpose, so it is behind a button rather than on the launch
// path: everything else stays testable in the same run.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P13LayoutApp: App {
    var body: some Scene {
        WindowGroup("P13 layout and view graph") {
            #hotReloadable {
                P13RootView()
            }
        }
        .defaultSize(width: 900, height: 760)
    }
}

// Deliberately NOT Identifiable: this is the type that drives #415 down the
// fallback path. P13IdentifiableMessage below is the control.
struct P13Message {
    var author: String
    var body: String
}

struct P13IdentifiableMessage: Identifiable {
    var id: Int
    var author: String
    var body: String
}

struct P13RootView: View {
    @State var showsUnidentifiedList = false
    @State var duplicateCount = 3
    @State var splitWidth = 400.0
    @State var status = "Ready. #415 is behind a button because it crashes."

    // Every element is identical, which is what makes the non-Identifiable
    // fallback produce duplicate child views.
    var duplicatedMessages: [P13Message] {
        (0..<duplicateCount).map { _ in
            P13Message(author: "Same", body: "Identical message")
        }
    }

    var identifiableMessages: [P13IdentifiableMessage] {
        (0..<duplicateCount).map {
            P13IdentifiableMessage(id: $0, author: "Same", body: "Identical message")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("P13: layout and view graph")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 840, alignment: .leading)

            // ---- #415 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("ForEach identity (#415)")

                HStack(spacing: 10) {
                    Button("More duplicates (\(duplicateCount))") {
                        duplicateCount += 1
                        status = "Now \(duplicateCount) identical elements."
                    }

                    Button(showsUnidentifiedList ? "Hide unidentified list" :
                        "Show unidentified list (may crash)")
                    {
                        showsUnidentifiedList.toggle()
                        status = showsUnidentifiedList
                            ? "Rendering non-Identifiable ForEach: this is the #415 path."
                            : "Unidentified list hidden."
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Identifiable (control)")
                        ForEach(identifiableMessages) { message in
                            Text("\(message.author): \(message.body)")
                        }
                    }
                    .frame(width: 260, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Non-Identifiable (#415)")
                        if showsUnidentifiedList {
                            // The fallback codepath: no id keypath, and every
                            // element compares equal.
                            ForEach(duplicatedMessages) { message in
                                Text("\(message.author): \(message.body)")
                            }
                        } else {
                            Text("(hidden)")
                        }
                    }
                    .frame(width: 260, alignment: .leading)
                }
            }

            // ---- #595 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Text clipping inside a ScrollView (#595)")

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plain (#595)")
                        ScrollView {
                            Text(
                                "This sentence is long enough that it has to wrap, "
                                    + "and it must not be cut off at the bottom."
                            )
                            .padding(4)
                        }
                        .frame(width: 300, height: 80)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("With .fixedSize() (workaround)")
                        ScrollView {
                            Text(
                                "This sentence is long enough that it has to wrap, "
                                    + "and it must not be cut off at the bottom."
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(4)
                        }
                        .frame(width: 300, height: 80)
                    }
                }
            }

            // ---- #291 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("NavigationSplitView minimum width (#291)")

                HStack(spacing: 10) {
                    Button("Narrower (\(Int(splitWidth)))") {
                        splitWidth = max(120, splitWidth - 60)
                        status = "Split view frame is now \(Int(splitWidth)) px wide."
                    }

                    Button("Wider") {
                        splitWidth = min(760, splitWidth + 60)
                        status = "Split view frame is now \(Int(splitWidth)) px wide."
                    }
                }

                NavigationSplitView {
                    VStack(alignment: .leading) {
                        Text("Sidebar")
                        Text("Has its own minimum")
                    }
                    .padding(6)
                } detail: {
                    VStack(alignment: .leading) {
                        Text("Detail")
                        Text("Should stay visible as the frame shrinks")
                    }
                    .padding(6)
                }
                .frame(width: splitWidth, height: 120)
            }

            // ---- #158 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Group inside ZStack (#158)")

                // The three colours should stack along z and overlap, so only
                // the smallest stays fully visible on top. Laid out side by
                // side or vertically instead means the Group took the
                // container's orientation.
                ZStack {
                    Group {
                        Color.red.frame(width: 180, height: 90)
                        Color.green.frame(width: 120, height: 60)
                        Color.blue.frame(width: 60, height: 30)
                    }
                }
                .frame(width: 220, height: 110)
            }
        }
        .padding(18)
    }
}
