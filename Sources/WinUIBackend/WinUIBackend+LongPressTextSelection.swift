import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI

extension WinUIBackend: BackendFeatures.LongPressTextSelection {
    /// A held press in a `TextBox`, then a drag, through `TextBox`'s own
    /// overrides: `createTextField` and `createTextEditor` make a
    /// ``LongPressTextBox``, whose `onPointerPressed`/`Moved`/`Released` run
    /// before the template's handling -- `addHandler(_:_:handledEventsToo:)`
    /// is not used, because this backend has measured it calling nothing (see
    /// the slider note in WinUIBackend.swift).
    ///
    /// Written against swift-winui's generated bindings and first built on
    /// Windows on 2026-10-19: `Control.onPointerPressed(_:)` and friends are
    /// `open`, `TextBox.getRectFromCharacterIndex(_:_:)` and `select(_:_:)`
    /// exist with those shapes, `UIElement.capturePointer(_:)` returns `Bool`.
    ///
    /// 在 `TextBox` 裡按住再拖曳，透過 `TextBox` 自己的覆寫:`createTextField` 與 `createTextEditor` 建立
    /// ``LongPressTextBox``,它的 `onPointerPressed`/`Moved`/`Released` 在 template 處理之前執行——不用
    /// `addHandler(_:_:handledEventsToo:)`,因為本 backend 已量到它什麼都不呼叫(見 WinUIBackend.swift 的 slider
    /// 註解)。依 swift-winui 產生的 binding 寫成,2026-10-19 首次在 Windows 上建置。
    public func setLongPressTextSelection(
        ofTextInput textInput: Widget,
        enabled: Bool,
        onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    ) {
        guard let textBox = textInput as? LongPressTextBox else { return }
        textBox.longPressSelection = enabled ? onChange : nil
    }
}

/// A `TextBox` that can select by long press and drag.
///
/// **Timerless**: the press is the template's until a move or the release
/// says otherwise, through ``LongPressSelectionTracker``'s rule for backends
/// without a timer -- a move or release after 0.5 s that never went past 10
/// pixels starts the selection there. The caret already sits under the
/// finger by then, because the template placed it on the press.
///
/// **Hit-tested by `GetRectFromCharacterIndex`, calibrated by the press.**
/// The anchor is the template's own answer: the caret the press put down
/// (`selectionStart` after `super.onPointerPressed`). The difference between
/// the press point and that caret's rectangle is the offset between pointer
/// coordinates and the rectangles' (padding, border, the text's own
/// scrolling), so the extent is the character whose rectangle, moved by that
/// offset, is nearest the pointer -- vertical distance first, so a point
/// beside a line picks that line.
///
/// `Select(start, length)` has no direction, so a backward drag shows the
/// same range as a forward one; the reported selection keeps the direction
/// from the anchor.
///
/// 可以長按拖曳選取的 `TextBox`。**沒有計時器**:按壓屬於 template,直到某次移動或放開另有表示——採用
/// ``LongPressSelectionTracker`` 給沒有計時器的 backend 的規則:0.5 秒後、從未超過 10 像素的移動或放開，就在
/// 那裡開始選取。那時插入點已經在手指底下，因為 template 在按下時就放好了。**以 `GetRectFromCharacterIndex`
/// 命中測試，並以按壓校正。** 錨點是 template 自己的答案：按壓放下的插入點(`super.onPointerPressed` 之後的
/// `selectionStart`)。按壓點與那個插入點矩形之間的差，就是指標座標與矩形座標之間的位移(padding、邊框、文字自己的
/// 捲動),所以延伸點是「矩形移動那個位移後最接近指標」的字元——先看垂直距離，所以在某一行旁邊的點會選那一行。
/// `Select(start, length)` 沒有方向，所以反向拖曳顯示的範圍與正向相同;回報的選取仍保留相對錨點的方向。
final class LongPressTextBox: TextBox {
    var longPressSelection: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?

    private var tracker = LongPressSelectionTracker()
    private var anchor = 0
    private var extent = 0
    /// Pointer coordinates minus rectangle coordinates, from the press.
    /// 指標座標減去矩形座標，由按壓得出。
    private var calibration = SIMD2<Double>(0, 0)

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    private func position(_ event: PointerRoutedEventArgs!) -> SIMD2<Double>? {
        guard let point = try? event.getCurrentPoint(self) else { return nil }
        return SIMD2(Double(point.position.x), Double(point.position.y))
    }

    override func onPointerPressed(_ e: PointerRoutedEventArgs!) throws {
        try super.onPointerPressed(e)
        guard longPressSelection != nil, let point = position(e) else { return }
        tracker.press(at: point, time: Self.now())
        // The template has placed the caret under the press by now.
        // template 此時已把插入點放在按壓底下。
        anchor = Int(selectionStart)
        if let rect = caretRect(anchor) {
            calibration = point - rect
        } else {
            calibration = SIMD2(0, 0)
        }
    }

    override func onPointerMoved(_ e: PointerRoutedEventArgs!) throws {
        guard longPressSelection != nil, let point = position(e) else {
            try super.onPointerMoved(e)
            return
        }
        let event = tracker.move(to: point, time: Self.now())
        if handle(event, pointer: e) {
            e.handled = true
            return
        }
        try super.onPointerMoved(e)
    }

    override func onPointerReleased(_ e: PointerRoutedEventArgs!) throws {
        guard longPressSelection != nil, let point = position(e) else {
            try super.onPointerReleased(e)
            return
        }
        var taken = false
        for event in tracker.release(at: point, time: Self.now()) {
            taken = handle(event, pointer: e) || taken
        }
        if taken {
            try? releasePointerCapture(e.pointer)
            e.handled = true
            return
        }
        try super.onPointerReleased(e)
    }

    override func onPointerCaptureLost(_ e: PointerRoutedEventArgs!) throws {
        if tracker.cancel() == .finish {
            report(.ended)
        }
        try super.onPointerCaptureLost(e)
    }

    /// Ctrl+Shift+Z redoes, as Ctrl+Y does. TextBox knows only Ctrl+Y, so
    /// P94's Ctrl+Shift+Z did nothing here while GtkBackend redid on it.
    /// Ctrl+Shift+Z 與 Ctrl+Y 一樣是重做。TextBox 只認得 Ctrl+Y,所以 P94 的 Ctrl+Shift+Z 在這裡沒有作用，
    /// 而 GtkBackend 會重做。
    override func onKeyDown(_ e: KeyRoutedEventArgs!) throws {
        // 0x5A is VK_Z. 0x5A 是 VK_Z。
        if let e, e.key.rawValue == 0x5A {
            let modifiers = MainActor.assumeIsolated { WinUIBackend.currentModifiers() }
            if modifiers.contains(.control), modifiers.contains(.shift),
               !modifiers.contains(.option)
            {
                try redo()
                e.handled = true
                return
            }
        }
        try super.onKeyDown(e)
    }

    /// Returns whether the event was the selection's, and so not the template's.
    /// 回傳這個事件是否屬於選取、因此不屬於 template。
    private func handle(_ event: LongPressSelectionTracker.Event, pointer e: PointerRoutedEventArgs!) -> Bool {
        switch event {
            case .none, .passThrough:
                return tracker.isSelecting
            case .select(_, let extentPoint):
                // Captured, so the drag keeps coming here even off the box,
                // and handled, so no ScrollViewer above scrolls.
                // 捕捉指標，讓拖曳離開方框也照樣送到這裡;標記 handled,讓上層的 ScrollViewer 不會捲動。
                _ = try? capturePointer(e.pointer)
                extent = index(at: extentPoint)
                report(.began)
                return true
            case .extend(let point):
                extent = index(at: point)
                report(.changed)
                return true
            case .finish:
                report(.ended)
                return true
        }
    }

    /// The leading edge of the caret before `index`, in rectangle coordinates.
    /// `index` 之前插入點的前緣，以矩形座標表示。
    private func caretRect(_ index: Int) -> SIMD2<Double>? {
        let length = text.utf16.count
        if index < length, let rect = try? getRectFromCharacterIndex(Int32(index), false) {
            return SIMD2(Double(rect.x), Double(rect.y) + Double(rect.height) / 2)
        }
        if length > 0, let rect = try? getRectFromCharacterIndex(Int32(length - 1), true) {
            return SIMD2(Double(rect.x), Double(rect.y) + Double(rect.height) / 2)
        }
        return nil
    }

    private func index(at point: SIMD2<Double>) -> Int {
        let length = text.utf16.count
        let target = point - calibration
        var best = anchor
        var bestScore = Double.infinity
        for index in 0...length {
            guard let edge = try? caretEdge(index, length: length) else { continue }
            let dy = max(0, abs(target.y - edge.middle) - edge.halfHeight)
            let score = dy * 10_000 + abs(target.x - edge.x)
            if score < bestScore {
                bestScore = score
                best = index
            }
        }
        return best
    }

    private struct Edge {
        var x: Double
        var middle: Double
        var halfHeight: Double
    }

    private func caretEdge(_ index: Int, length: Int) throws -> Edge {
        let rect =
            index < length
            ? try getRectFromCharacterIndex(Int32(index), false)
            : try getRectFromCharacterIndex(Int32(length - 1), true)
        return Edge(
            x: Double(rect.x),
            middle: Double(rect.y) + Double(rect.height) / 2,
            halfHeight: Double(rect.height) / 2
        )
    }

    private func report(_ phase: TextDragSelectionPhase) {
        let requested = TextDragSelection(anchor: anchor, extent: extent)
            .clamped(toLength: text.utf16.count)
        let range = requested.range
        try? select(Int32(range.lowerBound), Int32(range.count))
        // Read back from the TextBox, not echoed. / 從 TextBox 讀回，而非照抄。
        let start = Int(selectionStart)
        let end = start + Int(selectionLength)
        let reported =
            requested.isBackward
            ? TextDragSelection(anchor: end, extent: start)
            : TextDragSelection(anchor: start, extent: end)
        // The handler is taken out of `self` first. Passing the closure
        // `{ longPressSelection?(...) }` sent `self` -- a TextBox, not Sendable --
        // into assumeIsolated, which Swift 6.4 refuses ("sending 'self' risks
        // causing data races"). Every event that reaches here is raised on
        // the UI thread.
        // 先把 handler 從 `self` 取出。原本的閉包 `{ longPressSelection?(...) }` 把 `self`(TextBox,非 Sendable)
        // 送進 assumeIsolated,Swift 6.4 拒絕(「sending 'self' risks causing data races」)。抵達此處的每個事件都在
        // UI 執行緒上引發。
        nonisolated(unsafe) let handler = longPressSelection
        MainActor.assumeIsolated { handler?(reported, phase) }
    }
}
