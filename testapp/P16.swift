import DefaultBackend
import Foundation
import SwiftCrossUI

// P16 Windows (WinUIBackend) repro app: NavigationSplitView initial layout.
//
// - #160 Split views are laid out very incorrectly on the initial load, then
//   snap to a correct layout as soon as any state changes or the window is
//   resized. Upstream's suspicion, stated as unverified, is that WinUI cannot
//   produce a correct size before the first render and hands back a dud value.
//   Upstream reproduces it by running SplitExample on Windows.
//
// This mirrors SplitExample's structure -- two-column and three-column, a List
// in the sidebar, padding of 10 -- so that a difference in behaviour is a
// difference in the backend rather than in the view tree. What it adds is
// measurement: each pane reports the size it was given, so "very incorrectly"
// becomes a number that can be written down and compared after the snap.
//
// Read the numbers before touching anything. The bug is defined by the first
// render, and resizing the window is one of the two things that fixes it, so
// any interaction destroys the evidence. `Force update` exists to trigger the
// snap deliberately, without changing the structure being measured.
//
// The sizes are displayed live rather than captured into state at first
// render. Writing state from inside a layout pass would feed back into the
// layout it is measuring, and GeometryReader's own documentation warns that
// content may be evaluated several times with different sizes before the
// layout settles.
//
// Build this file as a standalone app target.

enum P16Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P16] \(message)")

        guard let data = "P16 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p16-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func recordPane(label: String, size: ViewSize) {
        guard isEnabled else { return }
        let line = "\(label): \(Int(size.width)) x \(Int(size.height))"
        guard lastReported[label] != line else { return }
        lastReported[label] = line
        write(line)
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P16 ready for #160 initial-layout checks")
    }
}

@main
@HotReloadable
struct P16SplitLayoutApp: App {
    var body: some Scene {
        WindowGroup("P16 split view initial layout") {
            #hotReloadable {
                P16RootView()
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}

enum P16Area: String, CaseIterable, Identifiable {
    var id: Self { self }

    case science = "Science"
    case humanities = "Humanities"
}

enum P16Columns {
    case two
    case three
}

struct P16RootView: View {
    @State var selectedArea: P16Area?
    @State var columns = P16Columns.two

    // Deliberately unrelated to the split view's structure. Changing it is a
    // state change and nothing else, which is exactly what #160 says is enough
    // to make the layout correct itself.
    @State var updateCount = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("P16: split view initial layout (#160)")
                .font(.system(size: 18))

            Text("Read the pane sizes below before clicking anything.")

            HStack(spacing: 10) {
                Button("Force update (\(updateCount))") {
                    updateCount += 1
                }

                Button(columns == .two ? "Switch to 3 column" : "Switch to 2 column") {
                    columns = columns == .two ? .three : .two
                }
            }

            switch columns {
                case .two:
                    doubleColumn
                case .three:
                    tripleColumn
            }
        }
        .padding(10)
        .onAppear {
            P16Diagnostics.renderComplete()
        }
    }

    var doubleColumn: some View {
        NavigationSplitView {
            VStack {
                P16PaneSize(label: "sidebar")
                List(P16Area.allCases, selection: $selectedArea) { area in
                    HStack {
                        Color.purple.frame(width: 40, height: 40).cornerRadius(4)
                        Text(area.rawValue)
                    }
                }
                Spacer()
            }
            .padding(10)
        } detail: {
            VStack {
                P16PaneSize(label: "detail")
                Text(selectedArea?.rawValue ?? "Select an area")
                Spacer()
            }
            .padding(10)
        }
    }

    var tripleColumn: some View {
        NavigationSplitView {
            VStack {
                P16PaneSize(label: "sidebar")
                List(P16Area.allCases, selection: $selectedArea) { area in
                    Text(area.rawValue)
                }
                Spacer()
            }
            .padding(10)
        } content: {
            VStack {
                P16PaneSize(label: "middle")
                Text(selectedArea?.rawValue ?? "Select an area")
                Spacer()
            }
            .padding(10)
        } detail: {
            VStack {
                P16PaneSize(label: "detail")
                Text("Detail for \(selectedArea?.rawValue ?? "nothing")")
                Spacer()
            }
            .padding(10)
        }
    }
}

// Reports the size its pane was given. Kept to a fixed frame so the reader
// itself does not influence the pane's height while measuring it.
struct P16PaneSize: View {
    var label: String

    var body: some View {
        GeometryReader { proxy in
            let _ = P16Diagnostics.recordPane(label: label, size: proxy.size)
            Text("\(label): \(Int(proxy.size.width)) x \(Int(proxy.size.height))")
        }
        .frame(height: 22)
    }
}
