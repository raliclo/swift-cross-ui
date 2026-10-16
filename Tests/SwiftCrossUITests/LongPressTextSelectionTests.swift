import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Long-press drag selection without a backend: the anchor/extent ordering
/// every toolkit is given, GTK's scalar-to-UTF-16 conversion, and the
/// long-press decision the AppKit, GTK and WinUI backends share.
///
/// 不需要 backend 的長按拖曳選取：交給每個 toolkit 的錨點/延伸點排序、GTK 的 scalar 轉 UTF-16,以及 AppKit、
/// GTK、WinUI backend 共用的長按判斷。
@Suite("Long-press text selection")
struct LongPressTextSelectionTests {
    typealias Tracker = LongPressSelectionTracker

    @Test("forward drag: range from anchor to extent")
    func forward() {
        let selection = TextDragSelection(caretAt: 4).extended(to: 9)
        #expect(selection.range == 4..<9)
        #expect(!selection.isBackward)
        #expect(!selection.isEmpty)
    }

    @Test("backward drag: range ordered, anchor kept, direction reported")
    func backward() {
        let selection = TextDragSelection(caretAt: 9).extended(to: 2)
        #expect(selection.range == 2..<9)
        #expect(selection.anchor == 9)
        #expect(selection.isBackward)
    }

    @Test("the caret alone is empty")
    func caret() {
        let selection = TextDragSelection(caretAt: 5)
        #expect(selection.isEmpty)
        #expect(selection.range == 5..<5)
    }

    @Test("clamped to the text, both ends")
    func clamped() {
        #expect(TextDragSelection(anchor: -3, extent: 40).clamped(toLength: 10) == TextDragSelection(anchor: 0, extent: 10))
        #expect(TextDragSelection(anchor: 12, extent: 3).clamped(toLength: 10).range == 3..<10)
        #expect(TextDragSelection(anchor: 2, extent: 3).clamped(toLength: -1) == TextDragSelection(anchor: 0, extent: 0))
    }

    @Test("GTK scalar offsets to UTF-16: ASCII, CJK, an emoji outside the BMP")
    func scalarOffsets() {
        #expect(TextDragSelection.utf16Offset(ofScalarOffset: 3, in: "hello") == 3)
        #expect(TextDragSelection.utf16Offset(ofScalarOffset: 2, in: "中文字") == 2)
        // U+1F600 is one scalar and two UTF-16 code units.
        #expect(TextDragSelection.utf16Offset(ofScalarOffset: 2, in: "a\u{1F600}b") == 3)
        #expect(TextDragSelection.utf16Offset(ofScalarOffset: 99, in: "a\u{1F600}b") == 4)
        #expect(TextDragSelection.utf16Offset(ofScalarOffset: 0, in: "abc") == 0)
    }

    @Test("held still: the timer selects at the press point, then moves extend")
    func longPressThenDrag() {
        var tracker = Tracker()
        tracker.press(at: SIMD2(10, 10), time: 0)
        #expect(tracker.elapse(to: 0.3) == .none)
        #expect(tracker.move(to: SIMD2(13, 12), time: 0.35) == .none)
        #expect(tracker.elapse(to: 0.5) == .select(anchor: SIMD2(10, 10), extent: SIMD2(10, 10)))
        #expect(tracker.isSelecting)
        #expect(tracker.move(to: SIMD2(80, 12), time: 0.8) == .extend(to: SIMD2(80, 12)))
        #expect(tracker.move(to: SIMD2(-40, 12), time: 0.9) == .extend(to: SIMD2(-40, 12)))
        #expect(tracker.release(at: SIMD2(-40, 12), time: 1.0) == [.extend(to: SIMD2(-40, 12)), .finish])
        #expect(!tracker.isSelecting)
    }

    @Test("moved before the delay: an ordinary drag, the toolkit's from then on")
    func earlyMovePassesThrough() {
        var tracker = Tracker()
        tracker.press(at: SIMD2(10, 10), time: 0)
        #expect(tracker.move(to: SIMD2(30, 10), time: 0.2) == .passThrough)
        #expect(tracker.elapse(to: 0.6) == .none)
        #expect(tracker.move(to: SIMD2(90, 10), time: 0.7) == .none)
        #expect(tracker.release(at: SIMD2(90, 10), time: 0.8) == [])
    }

    @Test("released before the delay: a tap")
    func tap() {
        var tracker = Tracker()
        tracker.press(at: SIMD2(10, 10), time: 0)
        #expect(tracker.release(at: SIMD2(10, 10), time: 0.1) == [.passThrough])
        #expect(tracker.elapse(to: 0.6) == .none)
    }

    @Test("no timer: the first event after the delay starts the selection")
    func timerless() {
        var tracker = Tracker()
        tracker.press(at: SIMD2(10, 10), time: 0)
        #expect(tracker.move(to: SIMD2(60, 10), time: 0.7) == .select(anchor: SIMD2(10, 10), extent: SIMD2(60, 10)))
        #expect(tracker.move(to: SIMD2(70, 10), time: 0.8) == .extend(to: SIMD2(70, 10)))

        var still = Tracker()
        still.press(at: SIMD2(10, 10), time: 0)
        #expect(still.release(at: SIMD2(11, 10), time: 0.9) == [.select(anchor: SIMD2(10, 10), extent: SIMD2(11, 10)), .finish])
    }

    @Test("a cancel ends a selection and forgets a pending press")
    func cancel() {
        var tracker = Tracker()
        tracker.press(at: SIMD2(0, 0), time: 0)
        #expect(tracker.cancel() == .none)
        #expect(tracker.elapse(to: 1) == .none)
        tracker.press(at: SIMD2(0, 0), time: 2)
        #expect(tracker.elapse(to: 2.5) == .select(anchor: SIMD2(0, 0), extent: SIMD2(0, 0)))
        #expect(tracker.cancel() == .finish)
        #expect(!tracker.isSelecting)
    }

    @Test("off by default; the modifier turns it on for everything below")
    @MainActor
    func environmentDefault() {
        let environment = EnvironmentValues(backend: DummyBackend())
        #expect(environment.isLongPressTextSelectionEnabled == false)
        #expect(environment.with(\.isLongPressTextSelectionEnabled, true).isLongPressTextSelectionEnabled)
    }
}
