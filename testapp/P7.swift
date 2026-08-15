import DefaultBackend
import SwiftCrossUI

// P7 Linux (GtkBackend) repro app: lists and split views.
//
// - #476 The List control starts with the first item already selected on the
//   GTK backend, even though no selection was set.
// - #556 Gtk List NavigationSplitView makes weird size decisions.
//
// Both are about a List reporting or occupying something other than what it
// was asked to. The selection binding starts as nil here on purpose, so any
// selection visible at launch came from the backend rather than from the app.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P7ListsApp: App {
    var body: some Scene {
        WindowGroup("P7 lists and split views") {
            #hotReloadable {
                P7RootView()
            }
        }
        .defaultSize(width: 720, height: 480)
    }
}

struct P7Fruit: Identifiable, Hashable {
    var id: String { name }
    var name: String
}

struct P7RootView: View {
    // Deliberately nil: at launch nothing should appear selected. #476 is that
    // the first row appears selected anyway.
    @State var selection: String?
    @State var sidebarSelection: String?
    @State var eventLog = "Ready. Nothing should be selected yet."

    let fruits = [
        P7Fruit(name: "Apple"),
        P7Fruit(name: "Banana"),
        P7Fruit(name: "Cherry"),
        P7Fruit(name: "Date"),
        P7Fruit(name: "Elderberry"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("P7: lists and split views")
                .font(.system(size: 20))

            Text("Selection: \(selection ?? "none")")
            Text(eventLog)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plain List (#476)")
                    List(fruits, selection: $selection) { fruit in
                        Text(fruit.name)
                    }
                    .frame(width: 200, height: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NavigationSplitView with a List (#556)")
                        .frame(width: 420, height: 24, alignment: .leading)
                    NavigationSplitView {
                        List(fruits, selection: $sidebarSelection) { fruit in
                            Text(fruit.name)
                        }
                    } detail: {
                        VStack {
                            Text(sidebarSelection ?? "No sidebar selection")
                            Text("This detail pane should keep its share of the width.")
                        }
                        .padding(10)
                    }
                    .frame(width: 420, height: 180)
                }
                .padding(.leading, 32)
            }

            HStack(spacing: 8) {
                Button("Clear selection") {
                    selection = nil
                    sidebarSelection = nil
                    eventLog = "Cleared. Both lists should show nothing selected."
                }
                Button("Select Cherry") {
                    selection = "Cherry"
                    eventLog = "Set selection to Cherry from code."
                }
                Button("Add a fruit's worth of text") {
                    eventLog =
                        "A longer message, to see whether the split view "
                        + "re-lays out when the text around it grows."
                }
            }
        }
        .padding(12)
    }
}
