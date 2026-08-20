import Foundation
import Testing

@testable import InputEvent

@Suite("Action file parsing")
struct ActionFileTests {
    /// The example from the module README, so the documentation cannot drift
    /// away from what the parser accepts without a test noticing.
    static let readmeExample = """
        action,x,y,origin,button,key,micros,note
        # P21 test plan steps 1 and 2
        click,60,181,,left,,,press Enabled under Button
        sleep,,,,,,500000,let the click register
        click,157,181,,left,,,press Disabled; clicks must not rise
        sleep,,,,,,500000,
        key,,,,,tab,,move focus to the next control
        keydown,,,,,shift,,hold shift
        key,,,,,tab,,shift-tab moves focus back
        keyup,,,,,shift,,release shift
        """

    static let dragExample = """
        action,x,y,origin,button,key,micros,note
        mousedown,200,18,frame,left,,,grab the title bar
        move,400,300,frame,,,,drag
        sleep,,,,,,100000,let the window manager follow
        move,600,400,frame,,,,keep dragging
        mouseup,600,400,frame,left,,,let go
        """

    @Test("the README's click and key example parses to what it reads as")
    func readmeExampleParses() throws {
        let actions = try ActionFile.parse(Self.readmeExample)
        #expect(
            actions == [
                .click(.left, at: Point(x: 60, y: 181)),
                .sleep(microseconds: 500_000),
                .click(.left, at: Point(x: 157, y: 181)),
                .sleep(microseconds: 500_000),
                .key(.tab),
                .keyDown(.shift),
                .key(.tab),
                .keyUp(.shift),
            ]
        )
    }

    @Test("the drag example keeps its frame origin on every row that has one")
    func dragExampleParses() throws {
        let actions = try ActionFile.parse(Self.dragExample)
        #expect(
            actions == [
                .mouseDown(.left, at: Point(x: 200, y: 18, origin: .frame)),
                .move(Point(x: 400, y: 300, origin: .frame)),
                .sleep(microseconds: 100_000),
                .move(Point(x: 600, y: 400, origin: .frame)),
                .mouseUp(.left, at: Point(x: 600, y: 400, origin: .frame)),
            ]
        )
    }

    @Test("an omitted origin means client, which is the safe default")
    func originDefaultsToClient() throws {
        let actions = try ActionFile.parse(
            """
            action,x,y,origin,button,key,micros,note
            move,10,20,,,,,
            """
        )
        #expect(actions == [.move(Point(x: 10, y: 20, origin: .client))])
    }

    /// The point of the whole key table. A name borrowed from X11 or Win32 must
    /// stop the file rather than be skipped, because a skipped row runs to
    /// completion having quietly done less than the file says.
    @Test("an unknown key name is rejected, not skipped")
    func unknownKeyIsRejected() {
        #expect(throws: ActionFileError.unknownKey("Return", line: 2)) {
            try ActionFile.parse(
                """
                action,x,y,origin,button,key,micros,note
                key,,,,,Return,,X11 spells it this way; we do not
                """
            )
        }
    }

    @Test("every verb is rejected when the argument it needs is absent")
    func missingArgumentsAreRejected() {
        #expect(throws: ActionFileError.missingKey(verb: "key", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nkey,,,,,,,")
        }
        #expect(throws: ActionFileError.missingButton(verb: "click", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nclick,,,,,,,")
        }
        #expect(throws: ActionFileError.missingPosition(verb: "move", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nmove,,,,,,,")
        }
    }

    /// Half a position is an error rather than a defaulted zero, which would
    /// click in the corner and read as a missed target.
    @Test("x without y is an error, not a zero")
    func halfAPositionIsRejected() {
        #expect(throws: ActionFileError.incompletePosition(line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nmove,10,,,,,,")
        }
    }

    @Test("unknown verbs, buttons and origins each name their line")
    func unknownValuesAreRejected() {
        #expect(throws: ActionFileError.unknownAction("wiggle", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nwiggle,,,,,,,")
        }
        #expect(throws: ActionFileError.unknownButton("thumb", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nclick,,,,thumb,,,")
        }
        #expect(throws: ActionFileError.unknownOrigin("screen", line: 2)) {
            try ActionFile.parse("action,x,y,origin,button,key,micros,note\nmove,1,2,screen,,,,")
        }
    }

    /// A note containing a comma is the ordinary case, not an edge case: the
    /// column exists to hold a sentence.
    @Test("a quoted note may contain commas and doubled quotes")
    func quotedNotesSurvive() throws {
        let actions = try ActionFile.parse(
            """
            action,x,y,origin,button,key,micros,note
            click,1,2,,left,,,"press it, then wait for the ""ready"" line"
            """
        )
        #expect(actions == [.click(.left, at: Point(x: 1, y: 2))])
    }

    /// CRLF is what a file edited on Windows will have. Swift treats "\\r\\n" as
    /// one Character, so splitting on the literal "\\n" finds no separator at
    /// all and the whole file arrives as a single line -- a trap this project
    /// has hit twice elsewhere.
    @Test("a CRLF file parses the same as an LF one")
    func crlfParsesTheSame() throws {
        let lf = "action,x,y,origin,button,key,micros,note\nkey,,,,,space,,\nsleep,,,,,,1000,"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(try ActionFile.parse(crlf) == (try ActionFile.parse(lf)))
        #expect(try ActionFile.parse(crlf) == [.key(.space), .sleep(microseconds: 1000)])
    }

    @Test("blank rows and comments are skipped without shifting line numbers")
    func commentsAreSkipped() {
        #expect(throws: ActionFileError.unknownKey("Escape", line: 4)) {
            try ActionFile.parse(
                """
                action,x,y,origin,button,key,micros,note
                # a comment

                key,,,,,Escape,,
                """
            )
        }
    }
}
