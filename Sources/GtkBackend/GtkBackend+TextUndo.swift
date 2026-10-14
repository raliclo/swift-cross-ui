import CGtk
import Foundation
import Gtk
import SwiftCrossUI

/// The steps of a text's undo history: what Undo and Redo move through.
///
/// Every change is a step, except that a run of single characters typed or
/// erased within a second of each other is one. It holds no widget, so the rule
/// can be tested without GTK (`GtkTextUndoTests`).
///
/// 一段文字的復原歷史中的各步:Undo 與 Redo 就在其間移動。每次變更是一步，只有彼此相隔不到一秒、一次一個字元的
/// 輸入或刪除算同一步。它不持有任何 widget,所以這條規則不需要 GTK 就能測(`GtkTextUndoTests`)。
struct TextUndoSteps {
    private(set) var steps: [String]
    private(set) var index = 0
    private var lastChange = Date.distantPast
    private var lastWasTyping = false
    /// The first value set from the app is where the history starts, not a step.
    /// app 第一次設定的值是歷史的起點，不是一步。
    private var hasBaseline = false

    init(_ text: String) {
        steps = [text]
    }

    var current: String { steps[index] }

    mutating func record(_ text: String, fromApp: Bool = false, at now: Date = Date()) {
        guard text != steps[index] else { return }
        if fromApp, !hasBaseline {
            hasBaseline = true
            steps = [text]
            index = 0
            return
        }
        hasBaseline = true
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

    /// The text one step back, or nil at the start.
    /// 往回一步的文字;已在起點時為 nil。
    mutating func undo() -> String? {
        guard index > 0 else { return nil }
        index -= 1
        lastWasTyping = false
        return steps[index]
    }

    /// The text one step forward, or nil at the end.
    /// 往前一步的文字;已在終點時為 nil。
    mutating func redo() -> String? {
        guard index < steps.count - 1 else { return nil }
        index += 1
        lastWasTyping = false
        return steps[index]
    }
}

/// Undo and redo for a text field and for a text editor, kept by the framework.
///
/// GTK's own history joins inserts that follow one another without a space:
/// paste "hello" twice and one Undo takes both away, where macOS and Android
/// take one (P92, 2026-10-13). The rule is in `gtktexthistory.c`
/// (`action_chain`) and the barrier that would stop it is not public for a
/// `GtkText`. So the history is kept here instead (`TextUndoSteps`) and GTK's is
/// switched off: for a `GtkEntry` since 2026-10-13, and for a `GtkTextView` --
/// whose buffer uses the same `gtktexthistory.c` -- since 2026-10-14.
///
/// Control-Z and Control-Shift-Z (Command on macOS) go to this history too, since
/// GTK's own binding has nothing left to undo.
///
/// 由框架保存的文字欄位與文字編輯器的復原與重做。GTK 自己的歷史會把彼此相接、中間沒有空白的插入合併:貼上兩次「hello」,
/// 一次 Undo 就把兩次都拿掉，而 macOS 與 Android 只拿掉一次。規則在 `gtktexthistory.c`(`action_chain`),能阻止合併的
/// barrier 對 `GtkText` 並不公開。所以歷史改存在這裡(`TextUndoSteps`),並關掉 GTK 自己的:`GtkEntry` 自 2026-10-13 起，
/// `GtkTextView`(它的 buffer 用的是同一份 `gtktexthistory.c`)自 2026-10-14 起。
/// Control-Z 與 Control-Shift-Z(macOS 上是 Command)也交給這份歷史，因為 GTK 自己的綁定已經沒有東西可復原。
@MainActor
final class TextUndoHistory {
    static var byPointer: [UnsafeMutableRawPointer: TextUndoHistory] = [:]

    private var steps: TextUndoSteps
    /// Puts a step's text into the widget and the caret at its end.
    /// 把某一步的文字放進 widget,並把游標移到結尾。
    private let show: (String) -> Void
    private var applying = false

    private init(text: String, show: @escaping (String) -> Void) {
        steps = TextUndoSteps(text)
        self.show = show
    }

    static func install(on entry: Entry) {
        let history = TextUndoHistory(text: entry.text) { [weak entry] text in
            guard let entry else { return }
            entry.text = text
            gtk_editable_set_position(OpaquePointer(entry.widgetPointer), -1)
        }
        gtk_editable_set_enable_undo(OpaquePointer(entry.widgetPointer), 0)
        history.attach(to: entry)
    }

    static func install(on textView: Gtk.TextView) {
        let history = TextUndoHistory(text: textView.buffer.text) { [weak textView] text in
            guard let textView else { return }
            textView.buffer.text = text
            let buffer: UnsafeMutablePointer<GtkTextBuffer> = textView.buffer.gobjectPointer.cast()
            var end = GtkTextIter()
            gtk_text_buffer_get_end_iter(buffer, &end)
            gtk_text_buffer_place_cursor(buffer, &end)
        }
        gtk_text_buffer_set_enable_undo(textView.buffer.gobjectPointer.cast(), 0)
        history.attach(to: textView)
    }

    /// Registers the history under the widget that takes the focus, and takes
    /// the undo and redo keys before GTK's own binding sees them.
    /// 以取得焦點的那個 widget 為鍵登記這份歷史，並在 GTK 自己的綁定看到之前接走復原與重做的按鍵。
    private func attach(to widget: Widget) {
        Self.byPointer[UnsafeMutableRawPointer(widget.widgetPointer)] = self
        let keys = EventControllerKey()
        gtk_event_controller_set_propagation_phase(keys.opaquePointer, GTK_PHASE_CAPTURE)
        keys.keyPressed = { [weak self] _, keyval, _, state in
            guard let self,
                  state.rawValue & (GDK_CONTROL_MASK.rawValue | GDK_META_MASK.rawValue) != 0,
                  Int32(keyval) == GDK_KEY_z || Int32(keyval) == GDK_KEY_Z
            else { return false }
            if state.rawValue & GDK_SHIFT_MASK.rawValue != 0 {
                self.redo()
            } else {
                self.undo()
            }
            return true
        }
        widget.addEventController(keys)
    }

    /// The history of the field or editor that holds `widget`, the focused widget.
    /// 持有 `widget`(聚焦的 widget)的那個欄位或編輯器的歷史。
    static func containing(_ widget: UnsafeMutablePointer<GtkWidget>) -> TextUndoHistory? {
        var current: UnsafeMutablePointer<GtkWidget>? = widget
        while let pointer = current {
            if let history = byPointer[UnsafeMutableRawPointer(pointer)] { return history }
            current = gtk_widget_get_parent(pointer)
        }
        return nil
    }

    func record(_ text: String, fromApp: Bool = false) {
        guard !applying else { return }
        steps.record(text, fromApp: fromApp)
    }

    func undo() {
        if let text = steps.undo() { apply(text) }
    }

    func redo() {
        if let text = steps.redo() { apply(text) }
    }

    private func apply(_ text: String) {
        applying = true
        show(text)
        applying = false
    }
}
