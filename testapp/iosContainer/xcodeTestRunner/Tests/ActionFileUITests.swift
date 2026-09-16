import Foundation
import XCTest

final class ActionFileUITests: XCTestCase {
    private let bundleIdentifier = "dev.swiftcrossui.testapp.debugTarget"

    /// How far one notch of the wheel drags the content.
    ///
    /// 40 points, which is what the GTK and AppKit synthesisers deliver per
    /// notch, so a file written for one platform scrolls a comparable distance
    /// on this one. It is a convention rather than a measurement -- a touch
    /// screen has no notch to measure -- and it is here rather than inline so
    /// there is one place to change it when a file needs a different feel.
    ///
    /// 一格滾輪帶動內容的距離。
    ///
    /// 40 點，與 GTK 及 AppKit 的 synthesiser 每一格所送出的距離相同，因此為某個平台撰寫的檔案在
    /// 此處會捲動相當的距離。這是一個約定而非量測值——觸控螢幕上沒有「一格」可量——並且放在此處而非
    /// 內嵌，使得日後若有檔案需要不同手感時，只有一個地方要改。
    private static let pointsPerNotch: CGFloat = 40

    /// The modifier a `keydown`/`keyup` names, or `nil` if it is not a modifier.
    ///
    /// The left/right distinction the format carries is dropped: XCUITest has
    /// one flag per modifier and no side. Dropped rather than rejected, because
    /// a file saying `rightCommand` means "Command is held" on every platform
    /// and only macOS can tell the two apart -- refusing it would fail files
    /// that are correct everywhere else.
    ///
    /// `command` is Command here, matching `EventModifiers.command` and the
    /// AppKit synthesiser.
    ///
    /// 某個 `keydown`/`keyup` 所指名的 modifier;若它不是 modifier 則為 `nil`。
    ///
    /// 格式中帶有的左右之分在此被捨棄:XCUITest 每個 modifier 只有一個旗標,沒有左右。是**捨棄**而
    /// 不是拒絕,因為一個寫著 `rightCommand` 的檔案,在每個平台上的意思都是「Command 被按著」,而
    /// 只有 macOS 分得出兩者——拒絕它會讓一份在別處都正確的檔案失敗。
    ///
    /// `command` 在此就是 Command,與 `EventModifiers.command` 及 AppKit synthesiser 一致。
    private static func modifierFlag(for key: String) -> XCUIElement.KeyModifierFlags? {
        switch key {
            case "command", "rightCommand": return .command
            case "shift", "rightShift": return .shift
            case "option", "rightOption": return .option
            case "control", "rightControl": return .control
            case "capsLock": return .capsLock
            default: return nil
        }
    }

    /// What `typeKey` should be given for a `key` action.
    ///
    /// A single character goes through as itself; the named keys map to
    /// `XCUIKeyboardKey`. `nil` means the format names a key XCUITest has no
    /// constant for, and the caller throws rather than substituting one --
    /// typing the wrong key is worse than refusing.
    ///
    /// `delete` is Backspace, which is Mac's meaning and the format's; the
    /// README warns that this surprises people who learned the names elsewhere,
    /// and getting it backwards here would erase the wrong character silently.
    ///
    /// 一個 `key` 動作該交給 `typeKey` 什麼。
    ///
    /// 單一字元原樣通過;具名按鍵映射到 `XCUIKeyboardKey`。`nil` 代表格式指名了一個 XCUITest 沒有
    /// 常數的按鍵,而呼叫端會 throw、不會拿另一個頂替——打錯鍵比拒絕更糟。
    ///
    /// `delete` 是 Backspace,那是 Mac 的語意、也是本格式的語意;README 警告過這會讓在別處學過這些
    /// 名字的人意外,而在此處弄反,會**靜默地**刪掉錯誤的字元。
    private static func typedKey(for key: String) -> String? {
        if key.count == 1 { return key }
        switch key {
            case "return": return XCUIKeyboardKey.return.rawValue
            case "tab": return XCUIKeyboardKey.tab.rawValue
            case "space": return XCUIKeyboardKey.space.rawValue
            case "escape": return XCUIKeyboardKey.escape.rawValue
            case "delete": return XCUIKeyboardKey.delete.rawValue
            case "forwardDelete": return XCUIKeyboardKey.forwardDelete.rawValue
            case "leftArrow": return XCUIKeyboardKey.leftArrow.rawValue
            case "rightArrow": return XCUIKeyboardKey.rightArrow.rawValue
            case "upArrow": return XCUIKeyboardKey.upArrow.rawValue
            case "downArrow": return XCUIKeyboardKey.downArrow.rawValue
            case "home": return XCUIKeyboardKey.home.rawValue
            case "end": return XCUIKeyboardKey.end.rawValue
            case "pageUp": return XCUIKeyboardKey.pageUp.rawValue
            case "pageDown": return XCUIKeyboardKey.pageDown.rawValue
            default: return nil
        }
    }

    /// Names the held modifiers for the log line.
    /// 為紀錄行寫出目前按著的 modifier。
    private static func describe(_ flags: XCUIElement.KeyModifierFlags) -> String {
        var names: [String] = []
        if flags.contains(.command) { names.append("command") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.capsLock) { names.append("capsLock") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    func testActionFile() throws {
        guard let path = ProcessInfo.processInfo.environment["IOS_ACTION_FILE"] else {
            XCTFail("IOS_ACTION_FILE is required")
            return
        }

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        let actions = try ActionFile.load(at: path)
        var pointer: XCUICoordinate?
        var dragStart: XCUICoordinate?
        /// Modifiers currently held by `keydown`, spent by the next `key`.
        /// 目前由 `keydown` 按住、將被下一個 `key` 花掉的 modifier。
        var heldModifiers: XCUIElement.KeyModifierFlags = []

        // Say what is about to be replayed, and afterwards say that it was.
        //
        // Every other platform ends a replay with `-actionfile: replayed <name>`
        // on stderr, and a run is judged on that line. iOS had nothing: the
        // replay happens in this XCUITest process, not in the app, so the app's
        // unified log never mentions it. Measured 2026-09-07 -- of the 47 iOS
        // run logs in testapp/output, **none** contains a completed-replay line,
        // which is why the coverage matrix carries iOS as `unverified` rather
        // than `pass` for all 45 apps.
        //
        // The count is here because a file that parsed to zero actions replays
        // successfully and does nothing, and those two are the same line
        // otherwise. `stderr` rather than `print`, so it lands beside
        // xcodebuild's own output whichever way the runner is invoked.
        //
        // 先說出將要重放什麼,之後再說它確實被重放了。
        //
        // 其他每一個平台的重放都以 stderr 上的 `-actionfile: replayed <名稱>` 作結,而一次執行正是
        // 依那一行判定的。iOS 上什麼都沒有:重放發生在這個 XCUITest 行程中,而非在 app 內,因此
        // app 的 unified log 從不提及它。2026-09-07 實測——testapp/output 中的 47 份 iOS 執行日誌
        // 裡,**沒有任何一份**含有「重放完成」的行,這正是涵蓋矩陣把 iOS 的全部 45 支記為
        // `unverified` 而非 `pass` 的原因。
        //
        // 此處輸出動作數量,是因為「一個解析出零個動作的檔案」會成功重放且什麼都不做,而若不寫出數量,
        // 那兩者就是同一行字。使用 `stderr` 而非 `print`,好讓它與 xcodebuild 自身的輸出並排,
        // 無論這個 runner 是以哪種方式被呼叫的。
        let fileName = (path as NSString).lastPathComponent
        FileHandle.standardError.write(
            Data("-actionfile: replaying \(fileName) with \(actions.count) actions\n".utf8)
        )

        for action in actions {
            switch action.kind {
            case "sleep":
                Thread.sleep(forTimeInterval: action.microseconds / 1_000_000)
            case "move":
                pointer = try coordinate(for: action, in: app)
            case "click":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                target.tap()
                pointer = target
            case "doubleclick":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                target.doubleTap()
                pointer = target
            case "mousedown":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                pointer = target
                dragStart = target
            case "mouseup":
                let target = try coordinateIfPresent(for: action, current: pointer, in: app)
                if let start = dragStart {
                    start.press(forDuration: 0.1, thenDragTo: target)
                    dragStart = nil
                } else {
                    target.tap()
                }
                pointer = target
            case "scroll":
                // A wheel notch becomes a drag, because a touch screen has no
                // wheel.
                //
                // The sign inverts, and that is the part to get right. In the
                // action-file format a positive `dy` scrolls *down* -- the
                // viewport moves further down the content. A finger does that by
                // moving *up*. Same for `dx`: scrolling right means dragging
                // left. Getting this backwards produces a scroll that works,
                // moves the right distance, and goes the wrong way, which reads
                // as the app scrolling oddly rather than as the runner being
                // wrong.
                //
                // Until this existed the runner threw `unsupported` on every
                // scroll row, so P8, P27 and P38 -- the three apps whose whole
                // subject is scrolling -- had no iOS action file at all.
                //
                // 一格滾輪變成一次拖曳，因為觸控螢幕沒有滾輪。
                //
                // 符號要反過來，而那正是必須弄對的地方。在動作檔格式中，`dy` 為正代表向**下**捲動
                // ——視口沿著內容往下移。手指要達成這件事，是往**上**移動。`dx` 亦然：向右捲動意味著
                // 向左拖曳。若把方向弄反，會得到一個「能運作、距離正確、方向相反」的捲動，那讀起來
                // 像是 app 的捲動行為古怪，而不像是 runner 寫錯了。
                //
                // 在此之前，runner 對每一列 scroll 都會拋出 `unsupported`，因此 P8、P27 與 P38
                // ——那三支整個主題就是捲動的 app——在 iOS 上完全沒有動作檔。
                let origin = pointer ?? app.windows.firstMatch.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                )
                let destination = origin.withOffset(CGVector(
                    dx: -action.x * Self.pointsPerNotch,
                    dy: -action.y * Self.pointsPerNotch
                ))
                // A brief press before the drag, as the mouseup case does. A
                // drag with no press is delivered as a flick, whose momentum
                // carries the content past where the row asked for and leaves
                // the next row measuring a position nobody chose.
                // 拖曳前先短暫按住，與 mouseup 的處理相同。沒有按住的拖曳會被視為快速滑動，其慣性
                // 會把內容帶過該列所要求的位置，使下一列量到的是一個沒有人選擇過的位置。
                origin.press(forDuration: 0.05, thenDragTo: destination)
            case "keydown":
                // A MODIFIER is held; anything else cannot be.
                //
                // XCUITest has no press-and-hold for an ordinary key: the unit
                // is `typeKey(_:modifierFlags:)`, one press with whatever
                // modifiers are down. So `keydown command` accumulates a flag
                // and `key s` spends it. `keydown s` has no expression here and
                // throws rather than quietly typing an `s` -- a held key that
                // silently became a tap is the kind of difference a test is
                // supposed to notice.
                //
                // **按住的必須是 modifier;其他任何鍵都不行。**
                //
                // XCUITest 沒有「按住一個普通按鍵」這種動作:它的單位是
                // `typeKey(_:modifierFlags:)`——一次按下,連同當時按著的那些 modifier。因此
                // `keydown command` 累積一個旗標,而 `key s` 把它花掉。`keydown s` 在此處無法表達,
                // 於是 throw,而不是安靜地打出一個 `s`——一個「被靜默變成單擊的長按」,正是測試本該
                // 察覺的那種差別。
                guard let flag = Self.modifierFlag(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "keydown \(action.key) (only modifiers can be held on iOS)",
                        action.line
                    )
                }
                heldModifiers.insert(flag)
            case "keyup":
                guard let flag = Self.modifierFlag(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "keyup \(action.key) (only modifiers can be held on iOS)",
                        action.line
                    )
                }
                heldModifiers.remove(flag)
            case "key":
                guard let typed = Self.typedKey(for: action.key) else {
                    throw ActionFileError.unsupported(
                        "key \(action.key) (no XCUIKeyboardKey for it)",
                        action.line
                    )
                }
                // Reported before it is sent, and with the modifiers spelled
                // out, because a shortcut that does nothing is otherwise
                // indistinguishable from one that was never sent -- the same
                // reason the coordinate line above exists.
                // 在送出之前先回報,而且把 modifier 明列出來;否則「一個什麼都沒做的快捷鍵」與
                // 「一個從未被送出的快捷鍵」無從分辨——與上方那行座標紀錄存在的理由相同。
                FileHandle.standardError.write(
                    Data(
                        ("-actionfile: line \(action.line) key '\(action.key)' "
                            + "modifiers=\(Self.describe(heldModifiers))\n").utf8
                    )
                )
                app.typeKey(typed, modifierFlags: heldModifiers)
            default:
                throw ActionFileError.unsupported(action.kind, action.line)
            }
        }

        FileHandle.standardError.write(
            Data("-actionfile: replayed \(fileName)\n".utf8)
        )
    }

    private func coordinate(
        for action: Action,
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        guard action.origin != "frame" else {
            throw ActionFileError.unsupported("frame origin on iOS", action.line)
        }

        let window = app.windows.firstMatch
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else {
            throw ActionFileError.invalidCoordinate(action.line)
        }

        // Says which window it resolved against and where the point landed.
        //
        // **Without this the failure is silent in both directions**: a tap that
        // misses looks exactly like a tap the app ignored, and the wrong window
        // looks exactly like wrong coordinates in the file. Both were live
        // hypotheses for P60 on 2026-09-09 and neither could be told from the
        // other by a screenshot or by the app's own log -- the log proved only
        // that the button never fired.
        //
        // 說出它是相對哪一個視窗解析的，以及那個點落在哪裡。
        //
        // **少了這一行，失敗在兩個方向上都是靜默的**：一次沒打中的點擊，看起來與一次被 app 忽略的
        // 點擊完全相同；而選錯視窗，看起來又與檔案裡座標寫錯完全相同。2026-09-09 的 P60 正是如此，
        // 而無論看截圖或看 app 自己的 log 都分辨不出來——那份 log 只能證明「那顆按鈕從未被觸發」。
        let message = "-actionfile: line \(action.line) point (\(action.x), \(action.y)) "
            + "windows=\(app.windows.count) frame=\(frame) "
            + "normalized=(\(action.x / frame.width), \(action.y / frame.height))\n"
        FileHandle.standardError.write(Data(message.utf8))

        return window.coordinate(withNormalizedOffset: CGVector(
            dx: action.x / frame.width,
            dy: action.y / frame.height
        ))
    }

    private func coordinateIfPresent(
        for action: Action,
        current: XCUICoordinate?,
        in app: XCUIApplication
    ) throws -> XCUICoordinate {
        if action.hasPosition {
            return try coordinate(for: action, in: app)
        }
        guard let current else {
            throw ActionFileError.invalidCoordinate(action.line)
        }
        return current
    }
}

private struct Action {
    let kind: String
    /// The `key` column, which the parser used to drop.
    ///
    /// It was dropped because nothing read it: `keydown`, `keyup` and `key` all
    /// threw `unsupported`. Carrying it is the first half of not throwing.
    /// `key` 欄位;parser 過去會把它丟掉。
    ///
    /// 之所以丟掉,是因為沒有人讀它:`keydown`、`keyup`、`key` 三者都 throw `unsupported`。
    /// 把它帶上,是「不再 throw」的前半。
    let key: String
    let x: CGFloat
    let y: CGFloat
    let origin: String
    let microseconds: TimeInterval
    let line: Int
    let hasPosition: Bool
}

private enum ActionFile {
    static func load(at path: String) throws -> [Action] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try text.split(whereSeparator: \.isNewline).enumerated().compactMap { index, raw in
            let line = index + 1
            let fields = parseCSV(String(raw))
            guard !fields.isEmpty, !fields[0].isEmpty, fields[0].first != "#" else { return nil }
            guard fields[0] != "action" else { return nil }
            guard fields.count >= 7 else { throw ActionFileError.malformed(line) }
            if fields.count > 8, !fields[8].isEmpty,
                fields[8] != "any", fields[8] != "ios"
            {
                throw ActionFileError.wrongPlatform(fields[8], line)
            }

            let hasPosition = !fields[1].isEmpty || !fields[2].isEmpty
            let x = CGFloat(Double(fields[1]) ?? 0)
            let y = CGFloat(Double(fields[2]) ?? 0)
            let micros = Double(fields[6]).map(TimeInterval.init) ?? 0
            return Action(
                kind: fields[0], key: fields[5], x: x, y: y,
                origin: fields[3].isEmpty ? "client" : fields[3],
                microseconds: micros, line: line, hasPosition: hasPosition
            )
        }
    }

    private static func parseCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(line)
        characters.append(",")

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == "," && !quoted {
                fields.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        return fields
    }
}

private enum ActionFileError: Error, CustomStringConvertible {
    case malformed(Int)
    case invalidCoordinate(Int)
    case unsupported(String, Int)
    case wrongPlatform(String, Int)

    var description: String {
        switch self {
        case .malformed(let line): return "Malformed action file row at line \(line)"
        case .invalidCoordinate(let line): return "Invalid iOS coordinate at line \(line)"
        case .unsupported(let action, let line): return "Unsupported iOS action '\(action)' at line \(line)"
        case .wrongPlatform(let platform, let line):
            return "Action file platform '\(platform)' is not valid for iOS at line \(line)"
        }
    }
}
