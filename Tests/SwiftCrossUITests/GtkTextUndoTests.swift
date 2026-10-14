// The steps GtkBackend's own undo history keeps for a text field and a text
// editor (`TextUndoSteps`), without a widget. GTK's history joined two pastes
// into one Undo; these pin the rule that replaced it.
// GtkBackend 為文字欄位與文字編輯器自己保存的復原歷史(`TextUndoSteps`)各步，不需要 widget。GTK 的歷史把兩次貼上
// 併成一次 Undo;這些測試釘住取代它的那條規則。
#if canImport(GtkBackend)
    import Foundation
    import Testing
    @testable import GtkBackend

    @Suite("GtkBackend text undo steps")
    struct GtkTextUndoTests {
        let start = Date(timeIntervalSince1970: 1_000_000)

        @Test("two pastes are two steps, the reason the history exists")
        func twoPastes() {
            var steps = TextUndoSteps("")
            steps.record("hello", at: start)
            steps.record("hellohello", at: start.addingTimeInterval(0.2))
            #expect(steps.undo() == "hello")
            #expect(steps.undo() == "")
            #expect(steps.undo() == nil)
        }

        @Test("single characters typed within a second of each other are one step")
        func typingRun() {
            var steps = TextUndoSteps("")
            steps.record("a", at: start)
            steps.record("ab", at: start.addingTimeInterval(0.3))
            steps.record("abc", at: start.addingTimeInterval(0.6))
            #expect(steps.current == "abc")
            #expect(steps.undo() == "")
        }

        @Test("a pause of a second or more starts a new step")
        func typingAfterAPause() {
            var steps = TextUndoSteps("")
            steps.record("a", at: start)
            steps.record("ab", at: start.addingTimeInterval(0.3))
            steps.record("abc", at: start.addingTimeInterval(1.5))
            #expect(steps.undo() == "ab")
            #expect(steps.undo() == "")
        }

        @Test("erasing one character at a time is a run as typing is")
        func erasingRun() {
            var steps = TextUndoSteps("")
            steps.record("hello", at: start)
            steps.record("hell", at: start.addingTimeInterval(2))
            steps.record("hel", at: start.addingTimeInterval(2.2))
            #expect(steps.undo() == "hello")
        }

        @Test("the first value the app sets is where the history starts")
        func baseline() {
            var steps = TextUndoSteps("")
            steps.record("from the app", fromApp: true, at: start)
            #expect(steps.undo() == nil)
            steps.record("from the app, edited", fromApp: true, at: start.addingTimeInterval(5))
            #expect(steps.undo() == "from the app")
        }

        @Test("redo goes forward again, and a new change drops what was undone")
        func redo() {
            var steps = TextUndoSteps("")
            steps.record("one", at: start)
            steps.record("one two", at: start.addingTimeInterval(2))
            #expect(steps.undo() == "one")
            #expect(steps.redo() == "one two")
            #expect(steps.redo() == nil)
            #expect(steps.undo() == "one")
            steps.record("one three", at: start.addingTimeInterval(4))
            #expect(steps.redo() == nil)
            #expect(steps.undo() == "one")
        }

        @Test("a character typed straight after an undo is its own step")
        func typingAfterUndo() {
            var steps = TextUndoSteps("")
            steps.record("a", at: start)
            steps.record("hello", at: start.addingTimeInterval(2))
            #expect(steps.undo() == "a")
            steps.record("ab", at: start.addingTimeInterval(2.1))
            #expect(steps.undo() == "a")
        }

        @Test("setting the same text again is not a step")
        func sameText() {
            var steps = TextUndoSteps("hello")
            steps.record("hello", at: start)
            #expect(steps.undo() == nil)
        }
    }
#endif
