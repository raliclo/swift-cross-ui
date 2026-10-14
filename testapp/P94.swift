// P94: Undo and Redo in a TextEditor, one change at a time (2026-10-14).
//
// A TextEditor that starts as "hello", and under it the text the app holds, so a run can read
// what each key left there. Every change is also a line "editor <text>" in p94-undo.log.
// `--p94-menu` or SCUI_P94_MENU=1 calls .enableMenu(), which adds Edit > Undo and Redo where the
// platform has no menus of its own.
//
// Why it exists: GTK's own history joins inserts that follow one another without a space, so
// two pastes were one Undo. GtkBackend kept its own history for a text field from 2026-10-13
// (P92) and a TextEditor still used GTK's; from 2026-10-14 both use `TextUndoHistory`.
//
// Pass, with the keys of testapp/actions/<platform>/P94-undo*.actions:
//   1 Select All, Cut, Paste, Paste leave "", "hello", "hellohello"
//   2 Undo takes one paste away at a time: "hello", "", and then the starting "hello"
//   3 one more Undo changes nothing
//   4 Redo goes forward again: "", "hello"
// Fail: one Undo that takes both pastes away, an Undo that does nothing, or a Redo that does
// not bring back what Undo took.
//
// P94:TextEditor 的 Undo 與 Redo,一次一個變更(2026-10-14)。TextEditor 起始為 hello,下方顯示 app 持有的文字，
// 讓一次執行讀得到每個按鍵之後留下什麼;每次變更也在 p94-undo.log 寫一行「editor <文字>」。`--p94-menu` 或
// SCUI_P94_MENU=1 會呼叫 .enableMenu(),在平台沒有自己選單的地方加上 Edit > Undo 與 Redo。
// 緣由:GTK 自己的歷史把彼此相接的插入合併，貼上兩次只算一次 Undo。GtkBackend 自 2026-10-13 起為文字欄位自己保存歷史
// (P92),TextEditor 當時仍用 GTK 的;自 2026-10-14 起兩者都用 `TextUndoHistory`。
// 通過:Select All、Cut、Paste、Paste 之後依序為 ""、hello、hellohello;Undo 一次拿掉一次貼上:hello、""、再來是起始的
// hello;再一次 Undo 沒有變化;Redo 往前:""、hello。失敗:一次 Undo 拿掉兩次貼上、Undo 沒有作用，或 Redo 帶不回 Undo 拿走的。

import DefaultBackend
import Foundation
import SwiftCrossUI

@MainActor
enum P94Log {
    static let menuEnabled =
        ProcessInfo.processInfo.environment["SCUI_P94_MENU"] == "1"
            || CommandLine.arguments.contains("--p94-menu")

    /// Appends a line to p94-undo.log, where a run can read what the editor held.
    /// 在 p94-undo.log 加一行，讓一次執行可以讀到編輯器裡有什麼。
    static func log(_ line: String) {
        print("[P94] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p94-undo.log")
        let data = Data((line + "\n").utf8)
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
struct P94App: App {
    var body: some Scene {
        WindowGroup("P94 editor undo") {
            #hotReloadable {
                P94View()
            }
        }
        .defaultSize(width: 420, height: 360)
        .enableMenu(P94Log.menuEnabled)
    }
}

struct P94View: View {
    @State var editor = "hello"
    @State var changes = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P94: TextEditor undo")
            Text("enableMenu: \(P94Log.menuEnabled ? "on" : "off")")
            TextEditor(text: $editor)
                .frame(width: 300, height: 90)
                .border(.gray)
            Text("editor: \(editor)")
            Text("changes: \(changes)")
        }
        .padding(16)
        .onChange(of: editor) {
            changes += 1
            P94Log.log("editor \(editor)")
        }
    }
}
