import CGtk
import Foundation
import Gtk
import SwiftCrossUI

/// Undo and redo for a text field, kept by the framework.
///
/// GTK's own history joins inserts that follow one another without a space:
/// paste "hello" twice and one Undo takes both away, where macOS and Android
/// take one (P92, 2026-10-13). The rule is in `gtktexthistory.c`
/// (`action_chain`) and the barrier that would stop it is not public for a
/// `GtkText`. So a field's history is kept here instead and GTK's is switched
/// off for it: every change is a step, except that a run of single characters
/// typed or erased within a second of each other is one.
///
/// Control-Z and Control-Shift-Z (Command on macOS) go to this history too, since
/// GTK's own binding has nothing left to undo.
///
/// 由框架保存的文字欄位復原與重做。GTK 自己的歷史會把彼此相接、中間沒有空白的插入合併:貼上兩次「hello」,一次 Undo 就把
/// 兩次都拿掉，而 macOS 與 Android 只拿掉一次。規則在 `gtktexthistory.c`(`action_chain`),能阻止合併的 barrier 對
/// `GtkText` 並不公開。所以欄位的歷史改存在這裡，並關掉 GTK 自己的:每次變更是一步，只有彼此相隔不到一秒、一次一個字元的
/// 輸入或刪除算同一步。Control-Z 與 Control-Shift-Z(macOS 上是 Command)也交給這份歷史，因為 GTK 自己的綁定已經沒有東西可復原。
@MainActor
final class EntryUndoHistory {
    static var byPointer: [UnsafeMutableRawPointer: EntryUndoHistory] = [:]

    private weak var entry: Entry?
    private var steps: [String]
    private var index = 0
    private var lastChange = Date.distantPast
    private var lastWasTyping = false
    private var applying = false
    /// The first value set from the app is where the history starts, not a step.
    /// app 第一次設定的值是歷史的起點，不是一步。
    private var hasBaseline = false

    init(entry: Entry) {
        self.entry = entry
        steps = [entry.text]
    }

    static func install(on entry: Entry) {
        let pointer = UnsafeMutableRawPointer(entry.widgetPointer)
        let history = EntryUndoHistory(entry: entry)
        byPointer[pointer] = history
        gtk_editable_set_enable_undo(OpaquePointer(entry.widgetPointer), 0)
        let keys = EventControllerKey()
        gtk_event_controller_set_propagation_phase(keys.opaquePointer, GTK_PHASE_CAPTURE)
        keys.keyPressed = { [weak history] _, keyval, _, state in
            guard let history,
                  state.rawValue & (GDK_CONTROL_MASK.rawValue | GDK_META_MASK.rawValue) != 0,
                  Int32(keyval) == GDK_KEY_z || Int32(keyval) == GDK_KEY_Z
            else { return false }
            if state.rawValue & GDK_SHIFT_MASK.rawValue != 0 {
                history.redo()
            } else {
                history.undo()
            }
            return true
        }
        entry.addEventController(keys)
    }

    /// The history of the field that holds `widget`, the focused widget.
    /// 持有 `widget`(聚焦的 widget)的那個欄位的歷史。
    static func containing(_ widget: UnsafeMutablePointer<GtkWidget>) -> EntryUndoHistory? {
        var current: UnsafeMutablePointer<GtkWidget>? = widget
        while let pointer = current {
            if let history = byPointer[UnsafeMutableRawPointer(pointer)] { return history }
            current = gtk_widget_get_parent(pointer)
        }
        return nil
    }

    func record(_ text: String, fromApp: Bool = false) {
        guard !applying, text != steps[index] else { return }
        if fromApp, !hasBaseline {
            hasBaseline = true
            steps = [text]
            index = 0
            return
        }
        hasBaseline = true
        let now = Date()
        let typing = abs(text.count - steps[index].count) == 1
        if typing, lastWasTyping, index == steps.count - 1, index > 0,
           now.timeIntervalSince(lastChange) < 1
        {
            steps[index] = text
        } else {
            steps.removeSubrange((index + 1)...)
            steps.append(text)
            index += 1
        }
        lastWasTyping = typing
        lastChange = now
    }

    func undo() {
        guard index > 0 else { return }
        index -= 1
        apply()
    }

    func redo() {
        guard index < steps.count - 1 else { return }
        index += 1
        apply()
    }

    private func apply() {
        guard let entry else { return }
        lastWasTyping = false
        applying = true
        entry.text = steps[index]
        gtk_editable_set_position(OpaquePointer(entry.widgetPointer), -1)
        applying = false
    }
}
