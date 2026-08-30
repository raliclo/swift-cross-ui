import DefaultBackend
import Foundation
import SwiftCrossUI

// P34 lazy containers and large collections: eager row construction probe.

enum P34Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static var requestedRows: Int {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-rows"),
            index + 1 < arguments.count,
            let rows = Int(arguments[index + 1])
        else { return 100 }
        return max(1, min(rows, 10_000))
    }

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P34] \(message)")
        let data = Data("P34 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p34-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete(rowCount: Int) {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P34 rows=\(rowCount)")
    }
}

@main
@HotReloadable
struct P34LargeCollectionsApp: App {
    var body: some Scene {
        WindowGroup("P34 large collections") {
            #hotReloadable {
                P34RootView(rowCount: P34Diagnostics.requestedRows)
            }
        }
        .defaultSize(width: 780, height: 620)
    }
}

struct P34RootView: View {
    var rowCount: Int
    @State var visibleRows = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P34: lazy containers and large collections")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("requested rows: \(rowCount); showing first \(min(visibleRows, rowCount))")
            Text("Missing APIs: LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, Grid, ScrollViewReader, ScrollViewProxy")
                .font(.system(size: 13))

            HStack(spacing: 8) {
                Button("Show +100") { visibleRows = min(rowCount, visibleRows + 100) }
                Button("Show all capped rows") { visibleRows = rowCount }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(0..<min(visibleRows, rowCount)), id: \.self) { index in
                        Text("Row \(index): eager VStack child")
                    }
                }
                .padding(8)
            }
            .frame(height: 360)
        }
        .padding(18)
        .onAppear {
            P34Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P34Diagnostics.renderComplete(rowCount: rowCount)
        }
    }
}
