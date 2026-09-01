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

    @Test("a platform column rejects a file verified for another backend")
    func platformIsValidated() throws {
        let file = """
            action,x,y,origin,button,key,micros,note,platform
            click,10,20,,left,,,,macos
            """
        #expect(try ActionFile.parse(file, platform: .macos).count == 1)
        #expect(throws: ActionFileError.wrongPlatform("macos", expected: .gtk, line: 2)) {
            try ActionFile.parse(file, platform: .gtk)
        }
    }

    @Test("a platform column accepts any matching platform in a pipe-separated list")
    func multiplePlatformsAreAccepted() throws {
        let file = """
            action,x,y,origin,button,key,micros,note,platform
            click,10,20,,left,,,,macos|gtk
            """
        #expect(try ActionFile.parse(file, platform: .gtk).count == 1)
        #expect(try ActionFile.parse(file, platform: .macos).count == 1)
        #expect(throws: ActionFileError.wrongPlatform("macos|gtk", expected: .ios, line: 2)) {
            try ActionFile.parse(file, platform: .ios)
        }
    }

    @Test("an unknown platform is rejected with its line")
    func unknownPlatformIsRejected() {
        #expect(throws: ActionFileError.unknownPlatform("solaris", line: 2)) {
            try ActionFile.parse(
                "action,x,y,origin,button,key,micros,note,platform\nclick,1,2,,left,,,,solaris"
            )
        }
    }

    /// Every action file in the tree parses.
    ///
    /// The parser is RFC 4180 and handles a quoted comma correctly; what it
    /// cannot do is guess that an *unquoted* comma inside a note was meant as
    /// text. Such a row splits into ten fields, the platform column reads the
    /// note's second half, and the whole file is rejected with
    /// `unknownPlatform` -- so one stray comma in a comment silently disables
    /// every action in the file, including the ones nobody touched.
    ///
    /// Eight rows across five files were in exactly that state when this test
    /// was written. They had been reviewed, committed and referenced by name in
    /// the coverage matrix; nothing in the tree read them until a replay tried
    /// to, and a replay only runs on the platform the file names. This test
    /// reads all of them on every platform.
    ///
    /// 樹中的每一份動作檔都能被解析。
    ///
    /// 解析器遵循 RFC 4180，能正確處理加了引號的逗號；它做不到的，是猜出 note 中**未加引號**的
    /// 逗號原本是文字。這樣的一列會被切成十欄，platform 欄讀到的是 note 的後半段，於是整個檔案
    /// 以 `unknownPlatform` 被拒絕——因此註解裡的一個多餘逗號，會靜默地讓該檔中每一個動作失效，
    /// 包括沒有人動過的那些。
    ///
    /// 撰寫本測試時，五個檔案中共有八列正處於這個狀態。它們都經過審閱、提交，並在涵蓋率矩陣中
    /// 被指名引用；在有人嘗試重放之前，樹中沒有任何東西讀過它們，而重放只會在該檔所指名的平台上
    /// 執行。本測試在每一個平台上都讀取全部檔案。
    @Test("every tracked action file parses")
    func everyTrackedActionFileParses() throws {
        // The repository root, from this file's own path. A test's working
        // directory is SwiftPM's business, not something to depend on.
        // 由本檔自身的路徑推得儲存庫根目錄。測試的工作目錄是 SwiftPM 的事，不該被依賴。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // InputEventTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
        let actions = root.appendingPathComponent("testapp/actions")

        let platforms: [String: ActionFilePlatform] = [
            "android": .android,
            "ios": .ios,
            "mac": .macos,
            "win": .windows,
            "wsl": .gtk,
        ]

        var parsed = 0
        for (directory, platform) in platforms.sorted(by: { $0.key < $1.key }) {
            let folder = actions.appendingPathComponent(directory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names.sorted() where name.hasSuffix(".csv") {
                let path = folder.appendingPathComponent(name)
                let text = try String(contentsOf: path, encoding: .utf8)
                #expect(throws: Never.self, "\(directory)/\(name)") {
                    _ = try ActionFile.parse(text, platform: platform)
                }
                parsed += 1
            }
        }

        // A directory that stops matching -- renamed, moved -- would otherwise
        // make this test pass by reading nothing at all.
        // 若某個目錄不再相符——被改名、被搬移——本測試否則會因為什麼都沒讀而通過。
        #expect(parsed > 20, "expected the action files to be found; parsed \(parsed)")
    }
}
