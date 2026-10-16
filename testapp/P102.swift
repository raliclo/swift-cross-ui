// P102: long-press drag selection in text fields -- longPressTextSelection(),
// on BackendFeatures.LongPressTextSelection.
//
// Three inputs, top to bottom, at fixed sizes:
//   FIELD    a TextField with .longPressTextSelection(), 360 wide.
//   EDITOR   a TextEditor with it, 360 x 110, three lines of text.
//   CONTROL  a TextField WITHOUT it. A long press here must log nothing.
//
// Every selection the backend reports is logged with the text it covers, read
// from the toolkit after it was set (the backend reads it back) and cut out of
// the bound string here:
//   FIELD began anchor A extent A ...            the caret went under the finger
//   FIELD ended anchor A extent E range ... 'sel' the selection that stayed
// Pass, driven by testapp/actions/<platform>/P102-*.actions or by hand:
//   - a long press then a drag to the right in FIELD: began with an empty
//     range, ended with a non-empty forward range;
//   - a long press then a drag up and left in EDITOR: ended "backward";
//   - a long press in CONTROL: no CONTROL line, and no new FIELD/EDITOR line.
// "settled" lines are written 0.7 s after each `ended`, and
// repeat the last entry: no further selection change was reported after the release. Whether the selection is still drawn is for the screenshot.
//
// P102:文字欄位中的長按拖曳選取——longPressTextSelection(),建立在 BackendFeatures.LongPressTextSelection
// 上。由上到下三個輸入框，大小固定:FIELD(有 modifier 的 TextField)、EDITOR(有 modifier 的 TextEditor)、
// CONTROL(沒有 modifier 的 TextField,在這裡長按必須什麼都不記錄)。backend 回報的每個選取都連同它涵蓋的文字
// 記錄下來——backend 設定後從 toolkit 讀回，再在這裡從綁定的字串切出來。通過條件見上方英文。每次 `ended` 後
// 0.7 秒寫一行 "settled",重複最後一筆紀錄：表示放開後再沒有回報任何選取變化;選取仍畫在畫面上，要看截圖。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P102Log {
    /// Appends a line to p102-select.log and stdout. / 在 p102-select.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P102] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p102-select.log")
        guard let data = "P102 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

@main
@HotReloadable
struct P102App: App {
    var body: some Scene {
        WindowGroup("P102 select") {
            #hotReloadable {
                P102RootView()
            }
        }
        .defaultSize(width: 440, height: 520)
    }
}

struct P102RootView: View {
    @State var field = "The quick brown fox jumps over the lazy dog"
    @State var editor = "Long press, then drag without lifting.\nThe selection follows the finger,\nand stays when you let go."
    @State var control = "No long-press selection in this one"
    @State var status = "waiting for a long press"
    @State var changes = 0

    func text(for kind: String) -> String {
        kind == "textField" ? field : editor
    }

    /// The UTF-16 range of `text`, as the backends report it.
    /// `text` 的 UTF-16 範圍，與 backend 回報的單位相同。
    static func slice(_ text: String, _ range: Range<Int>) -> String {
        let units = Array(text.utf16)
        let lower = min(max(range.lowerBound, 0), units.count)
        let upper = min(max(range.upperBound, lower), units.count)
        return String(decoding: units[lower..<upper], as: UTF16.self)
    }

    func record(_ entry: LongPressTextSelectionDiagnostics.Entry) {
        let name = entry.kind == "textField" ? "FIELD" : "EDITOR"
        let selected = Self.slice(text(for: entry.kind), entry.selection.range)
            .replacingOccurrences(of: "\n", with: "\\n")
        let line = "\(name) \(entry.phase.rawValue) \(entry.selection) '\(selected)'"
        switch entry.phase {
            case .began:
                changes = 0
                P102Log.write(line)
            case .changed:
                changes += 1
            case .ended:
                P102Log.write("\(line) after \(changes) changes")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    MainActor.assumeIsolated {
                        let count = LongPressTextSelectionDiagnostics.entries.count
                        P102Log.write("\(name) settled; \(count) entries; last \(LongPressTextSelectionDiagnostics.entries.last.map(String.init(describing:)) ?? "none")")
                    }
                }
        }
        status = line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P102: long-press drag selection")
                .font(.system(size: 16))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("FIELD (long press, then drag)")
                .font(.system(size: 11))
            TextField("field", text: $field)
                .frame(width: 360)
                .longPressTextSelection()
            Text("EDITOR (long press, then drag)")
                .font(.system(size: 11))
            TextEditor(text: $editor)
                .frame(width: 360, height: 110)
                .longPressTextSelection()
            Text("CONTROL (no modifier)")
                .font(.system(size: 11))
            TextField("control", text: $control)
                .frame(width: 360)
            Text(status)
                .font(.system(size: 11))
                .frame(width: 400, height: 60, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            P102Log.write("backend \(String(describing: DefaultBackend.self))")
            LongPressTextSelectionDiagnostics.onRecord = { entry in record(entry) }
            P102Log.write("RENDER COMPLETE -- P102 ready")
        }
    }
}
