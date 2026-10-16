import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.LongPressTextSelection {
    /// A held press in a field or editor, then a drag, through AppKit's own
    /// text hit-testing: `NSTextView.characterIndexForInsertion(at:)` on the
    /// editor itself, or on the field editor for a `TextField`.
    ///
    /// The press is taken in `mouseDown`, before `NSTextView` starts its own
    /// tracking loop, and held in a loop of the same kind
    /// (`nextEvent(matching:until:inMode: .eventTracking)`). If the pointer
    /// moves more than 10 points or is released before 0.5 s, the events read
    /// so far are put back at the head of the queue and the press is handed to
    /// AppKit as if nothing had looked at it -- a click, a double click and an
    /// ordinary drag-select are AppKit's. Otherwise the caret goes under the
    /// pointer as the anchor and every drag event moves the extent, with no
    /// `autoscroll(with:)`, so nothing scrolls.
    ///
    /// 一個在欄位或編輯器裡按住、然後拖曳的動作，透過 AppKit 自己的文字命中測試:對編輯器本身、或對
    /// `TextField` 的 field editor 呼叫 `NSTextView.characterIndexForInsertion(at:)`。按壓在 `mouseDown`
    /// 被接下——在 `NSTextView` 開始它自己的追蹤迴圈之前——並在同一種迴圈裡持有。若指標在 0.5 秒前移動
    /// 超過 10 點或放開，已讀到的事件會被放回佇列最前端，按壓交還 AppKit,如同沒有人看過它——點擊、雙擊、
    /// 一般的拖曳選取都屬於 AppKit。否則插入點放到指標底下作為錨點，之後每個拖曳事件移動延伸點，且不呼叫
    /// `autoscroll(with:)`,所以不會捲動。
    public func setLongPressTextSelection(
        ofTextInput textInput: Widget,
        enabled: Bool,
        onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    ) {
        let handler = enabled ? onChange.map { AppKitLongPressSelection(onChange: $0) } : nil
        if let field = textInput as? NSObservableTextField {
            field.longPressSelection = handler
        } else if let editor = textInput as? NSObservableTextView {
            editor.longPressSelection = handler
        }
    }
}

/// The long-press loop, for a field or an editor. / 長按迴圈，給欄位或編輯器使用。
@MainActor
final class AppKitLongPressSelection {
    let onChange: @MainActor (TextDragSelection, TextDragSelectionPhase) -> Void

    init(onChange: @escaping @MainActor (TextDragSelection, TextDragSelectionPhase) -> Void) {
        self.onChange = onChange
    }

    /// Runs the press that `event` began. Returns `false` when it was not a
    /// long press and AppKit should handle `event` after all; the events read
    /// meanwhile have been put back.
    ///
    /// `textView` is asked for the `NSTextView` to select in only once the
    /// long press has fired, because for a field that means making it first
    /// responder.
    ///
    /// 執行 `event` 開始的那次按壓。不是長按時回傳 `false`,AppKit 應照常處理 `event`;期間讀到的事件已經放回去。
    /// 長按成立後才向 `textView` 要選取用的 `NSTextView`,因為對欄位而言那代表讓它成為 first responder。
    func track(_ event: NSEvent, textView: () -> NSTextView?) -> Bool {
        guard event.type == .leftMouseDown, event.clickCount == 1,
            event.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty,
            let window = event.window
        else { return false }

        var tracker = LongPressSelectionTracker()
        tracker.press(at: Self.point(event.locationInWindow), time: event.timestamp)
        let deadline = Date(timeIntervalSinceNow: tracker.minimumDuration)
        var drained: [NSEvent] = []
        var start: (anchor: SIMD2<Double>, extent: SIMD2<Double>)?

        while start == nil {
            guard
                let next = window.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp],
                    until: deadline,
                    inMode: .eventTracking,
                    dequeue: true
                )
            else {
                // The delay passed with the pointer still down and near.
                // 延遲已過，指標仍按著且在附近。
                if case .select(let anchor, let extent) = tracker.elapse(
                    to: event.timestamp + tracker.minimumDuration
                ) {
                    start = (anchor, extent)
                }
                break
            }
            drained.append(next)
            let point = Self.point(next.locationInWindow)
            if next.type == .leftMouseUp {
                // Released early: a click. / 提早放開：一次點擊。
                _ = tracker.release(at: point, time: next.timestamp)
                return putBack(drained)
            }
            switch tracker.move(to: point, time: next.timestamp) {
                case .passThrough:
                    return putBack(drained)
                case .select(let anchor, let extent):
                    start = (anchor, extent)
                default:
                    break
            }
        }
        guard let start, let textView = textView() else { return putBack(drained) }

        let anchor = index(at: start.anchor, in: textView)
        var selection = TextDragSelection(caretAt: anchor).extended(to: index(at: start.extent, in: textView))
        apply(selection, to: textView, phase: .began)

        while let next = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            selection = selection.extended(to: index(at: Self.point(next.locationInWindow), in: textView))
            if next.type == .leftMouseUp {
                apply(selection, to: textView, phase: .ended)
                break
            }
            apply(selection, to: textView, phase: .changed)
        }
        return true
    }

    private func putBack(_ events: [NSEvent]) -> Bool {
        for event in events.reversed() {
            NSApp.postEvent(event, atStart: true)
        }
        return false
    }

    private static func point(_ location: NSPoint) -> SIMD2<Double> {
        SIMD2(Double(location.x), Double(location.y))
    }

    /// The insertion index under a point in window coordinates.
    /// 視窗座標中某一點底下的插入位置。
    private func index(at point: SIMD2<Double>, in textView: NSTextView) -> Int {
        let local = textView.convert(NSPoint(x: point.x, y: point.y), from: nil)
        return textView.characterIndexForInsertion(at: local)
    }

    private func apply(_ selection: TextDragSelection, to textView: NSTextView, phase: TextDragSelectionPhase) {
        let length = (textView.string as NSString).length
        let clamped = selection.clamped(toLength: length)
        let range = clamped.range
        textView.setSelectedRange(NSRange(location: range.lowerBound, length: range.count))
        // Read back from AppKit, not echoed: the range the view now holds.
        // 從 AppKit 讀回，而非照抄：視圖此刻持有的範圍。
        let held = textView.selectedRange()
        let reported =
            clamped.isBackward
            ? TextDragSelection(anchor: held.location + held.length, extent: held.location)
            : TextDragSelection(anchor: held.location, extent: held.location + held.length)
        onChange(reported, phase)
    }
}

/// The field editor a long-press `TextField` edits through, so that a press on
/// a field that is already being edited -- which AppKit delivers to the field
/// editor, not to the field -- reaches the same loop.
/// 長按 `TextField` 所用的 field editor,好讓「按在已在編輯中的欄位上」的按壓——AppKit 把它交給 field editor
/// 而非欄位——也進入同一個迴圈。
final class LongPressFieldEditor: NSTextView {
    weak var owner: NSObservableTextField?
    /// Set while the field hands AppKit a press it has already tracked.
    /// 欄位把一個已追蹤過的按壓交給 AppKit 時設定。
    var passesNextPress = false

    override func mouseDown(with event: NSEvent) {
        if passesNextPress {
            passesNextPress = false
            super.mouseDown(with: event)
            return
        }
        if let handler = owner?.longPressSelection, handler.track(event, textView: { self }) {
            return
        }
        super.mouseDown(with: event)
    }
}

/// Gives a long-press field its own field editor; any other field the window's.
/// 給長按欄位它自己的 field editor;其他欄位用視窗的。
final class LongPressTextFieldCell: NSTextFieldCell {
    private var editor: LongPressFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        guard let field = controlView as? NSObservableTextField, field.longPressSelection != nil else {
            return super.fieldEditor(for: controlView)
        }
        if let editor { return editor }
        let editor = LongPressFieldEditor()
        editor.isFieldEditor = true
        // As the window's own field editor is: plain text, with undo.
        // 與視窗自己的 field editor 相同：純文字、可復原。
        editor.isRichText = false
        editor.allowsUndo = true
        editor.owner = field
        self.editor = editor
        return editor
    }
}
