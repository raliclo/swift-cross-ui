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
                // Two buttons, eight points apart, that do different things to
                // the same state -- so they log DIFFERENT text. A single shared
                // message would say a button was pressed without saying which,
                // and a coordinate that drifted between them would still read as
                // a pass. Added 2026-09-04 for the Windows action file, which
                // otherwise had only the capture.
                //
                // Both are no-ops at the default rowCount of 100, because
                // visibleRows also starts at 100: min(100, 100+100) and
                // 100 = 100. Launch with `-rows 500` to make either do
                // anything. The log now says so out loud rather than leaving a
                // silent no-op to look like success.
                //
                // 兩顆相距八點的按鈕，對同一份狀態做不同的事——因此它們記錄**不同**的訊息。
                // 若共用一則訊息，就只能說明「有按鈕被按下」而說不出是哪一顆，而在兩者之間偏移
                // 的座標仍會被讀成通過。2026-09-04 為 Windows 動作檔新增，否則該檔只有擷圖可依。
                //
                // 在預設的 rowCount 100 之下兩者皆為 no-op，因為 visibleRows 起始亦為 100：
                // min(100, 100+100) 與 100 = 100。請以 `-rows 500` 啟動，任一顆才會有作用。
                // 現在 log 會直說這件事，而不是讓一個靜默的 no-op 看起來像成功。
                Button("Show +100") {
                    visibleRows = min(rowCount, visibleRows + 100)
                    P34Diagnostics.write("show plus 100 -> visibleRows=\(visibleRows)")
                }
                Button("Show all capped rows") {
                    visibleRows = rowCount
                    P34Diagnostics.write("show all -> visibleRows=\(visibleRows)")
                }
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
