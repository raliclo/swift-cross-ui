import DefaultBackend
import Foundation
import SwiftCrossUI

// P25 drag and drop, for comparing how a dropped file arrives across backends
// and platforms.
//
// Drag and drop appears in no other test app because SwiftCrossUI had no API for
// it until now: `onDrop(of:isTargeted:perform:)`, backed by
// BackendFeatures.DragAndDrop. This app is the first thing above the backends to
// exercise it.
//
// The questions worth asking are the ones where platforms have room to disagree,
// not whether a drop arrives at all:
//   - Does the same file report the same payload? Windows delivers a path
//     through CF_HDROP; X11 delivers a text/uri-list. One is C:\x\y.txt, the
//     other file:///x/y.txt. `received` is printed verbatim, never normalised,
//     because tidying it here would hide exactly that difference.
//   - Is a refused type refused visibly, or does the drop appear to succeed?
//   - Does dragging over the area give feedback before the release, or only
//     after? The area changes colour on hover, before the button is released, so
//     the feedback stage is observable separately from the drop stage.
//   - Do multiple files arrive as multiple items or as one string?
//
// P25 拖放，用於比較「被拖入的檔案」在不同 backend 與平台上如何抵達。
//
// 拖放未出現在任何其他測試 app，因為 SwiftCrossUI 直到現在才有其 API：
// `onDrop(of:isTargeted:perform:)`，底層為 BackendFeatures.DragAndDrop。此 app 是 backend
// 之上第一個操作它的東西。
//
// 值得詢問的，是兩平台有分歧空間的問題，而非「拖放到底會不會抵達」：
//   - 同一個檔案是否回報相同酬載？Windows 透過 CF_HDROP 傳路徑，X11 傳 text/uri-list；一個是
//     C:\x\y.txt，另一個是 file:///x/y.txt。`received` 原樣印出、永不正規化，因為在此整理它，
//     正好會掩蓋這個差異。
//   - 被拒絕的型別是否可見地被拒，還是看起來像成功了？
//   - 拖曳經過該區時，是在放開前就給回饋，還是放開後才給？該區於懸停時（放開前）變色，使
//     「回饋階段」能與「放置階段」分開觀察。
//   - 多個檔案是以多個項目抵達，還是合併為一個字串？
//
// Build this file as a standalone app target.

enum P25Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P25] \(message)")

        guard let data = "P25 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p25-debug-events.log")
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

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P25 ready for drag-and-drop checks")
    }
}

@main
@HotReloadable
struct P25DragAndDropApp: App {
    var body: some Scene {
        WindowGroup("P25 drag and drop") {
            #hotReloadable {
                P25RootView()
            }
        }
        .defaultSize(width: 720, height: 520)
    }
}

struct P25RootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P25: drag and drop")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Drag a file from the file manager onto each area below.")

            HStack(spacing: 16) {
                // The accepting area offers files, so a file dragged onto it
                // highlights on hover and reports its payload on drop.
                // 接受區宣告接受檔案，因此拖入的檔案會在懸停時高亮，並於放下時回報其酬載。
                P25DropArea(
                    title: "Accepts files",
                    acceptedTypes: [.fileURL]
                )

                // The refusing area offers a type nothing will be dragged as, so
                // the backend accepts no matching gtype and the drag is refused:
                // it does not highlight and no drop is reported. The refusal is
                // visible only by contrast with the accepting area beside it --
                // a drop zone that silently swallows what it cannot handle and
                // one that rejects it look identical until put side by side.
                // 拒絕區宣告一種不會被拖入的型別，因此 backend 不接受任何相符的 gtype，拖曳被拒：
                // 它不會高亮，也不回報任何放置。此拒絕僅能藉由與旁邊接受區的對照而可見——一個
                // 「默默吞掉無法處理之物」的放置區，與一個「明確拒絕」的放置區，在並排之前看起來
                // 完全相同。
                P25DropArea(
                    title: "Refuses (offers an unused type)",
                    acceptedTypes: [DropType("application/x-p25-nothing")]
                )
            }
        }
        .padding(18)
        .onAppear {
            P25Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P25Diagnostics.renderComplete()
        }
    }
}

struct P25DropArea: View {
    var title: String
    var acceptedTypes: [DropType]

    // Four fields, each reported on its own line, because merging them would
    // hide which stage failed.
    // 四個欄位，各佔一行分別回報，因為合併顯示會掩蓋是哪一個階段失敗。
    @State var state = "idle"
    @State var received = "(nothing yet)"
    @State var payloadType = "-"
    @State var count = 0
    @State var hovering = false

    var body: some View {
        ZStack {
            // Colour tracks hover, so the feedback stage is visible before the
            // drop lands.
            // 顏色隨懸停變化，使回饋階段在放置抵達前即可見。
            Color(
                red: hovering ? 0.30 : 0.13,
                green: 0.42,
                blue: hovering ? 0.65 : 0.30
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14))
                Text("state    \(state)")
                Text("received \(received)")
                Text("type     \(payloadType)")
                Text("count    \(count)")
            }
            .padding(12)
        }
        .frame(width: 320, height: 200)
        .onDrop(of: acceptedTypes, isTargeted: $hovering) { (items: [DropItem]) in
            count = items.count
            payloadType = items.map(\.type.identifier).joined(separator: ", ")
            // Verbatim: whatever the backend delivered, decoded as text if it
            // can be, otherwise a byte count. Not tidied into a path or a URL.
            // 原樣呈現：backend 交付的內容，若能解為文字則解為文字，否則顯示位元組數。不整理成
            // 路徑或 URL。
            received = items
                .map { $0.text ?? "<\($0.data.count) bytes>" }
                .joined(separator: " | ")
            state = "accepted"
            P25Diagnostics.write(
                "drop on '\(title)': count=\(count) type=[\(payloadType)] received=[\(received)]"
            )
            return true
        }
        .onChange(of: hovering) {
            // `hovering` already holds the new value here; onChange's action
            // takes no argument. Only overwrite the state line while
            // idle/hovering, so an "accepted" result stays readable after the
            // pointer leaves.
            // 此處 `hovering` 已是新值；onChange 的 action 不帶參數。僅在 idle/hovering 時覆寫
            // state 行，讓「accepted」結果在指標離開後仍可讀。
            if hovering {
                state = "hovering"
                P25Diagnostics.write("hover enter on '\(title)'")
            } else if state == "hovering" {
                state = "idle"
                P25Diagnostics.write("hover leave on '\(title)'")
            }
        }
    }
}
