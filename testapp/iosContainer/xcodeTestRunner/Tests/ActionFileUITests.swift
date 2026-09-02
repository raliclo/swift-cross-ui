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

    func testActionFile() throws {
        guard let path = ProcessInfo.processInfo.environment["IOS_ACTION_FILE"] else {
            XCTFail("IOS_ACTION_FILE is required")
            return
        }

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        let actions = try ActionFile.load(at: path)
        var pointer: XCUICoordinate?
        var dragStart: XCUICoordinate?

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
            case "keydown", "keyup", "key":
                throw ActionFileError.unsupported(action.kind, action.line)
            default:
                throw ActionFileError.unsupported(action.kind, action.line)
            }
        }
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
                kind: fields[0], x: x, y: y,
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
