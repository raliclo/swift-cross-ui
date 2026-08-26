import Foundation

/// Reads an action file into ``InputAction`` values.
///
/// The format is in this module's README: RFC 4180 CSV, one header row, nine
/// columns `action,x,y,origin,button,key,micros,note,platform`.
public enum ActionFile {
    public static func load(contentsOf url: URL) throws -> [InputAction] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    public static func parse(
        _ text: String,
        platform: ActionFilePlatform = .current
    ) throws -> [InputAction] {
        // Split on `isNewline` rather than the literal "\n". Swift treats
        // "\r\n" as a single extended grapheme cluster, so it is one Character
        // and it is not equal to "\n" -- a CRLF file split on the literal
        // returns one enormous element and every row silently disappears. This
        // has cost this project two separate debugging sessions.
        //
        // `omittingEmptySubsequences: false` because the offset is the line
        // number reported in errors. Dropping blank lines shifted every number
        // after the first one, so an error on line 4 was reported as line 3 --
        // caught by the test that puts a blank line above a bad row, which is
        // what that test is for.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        var actions: [InputAction] = []
        for (offset, line) in lines.enumerated() {
            let number = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let fields = splitCSVRow(String(line))
            // The header, recognised by its first field rather than by being
            // first: a file that starts with a comment would otherwise have its
            // header treated as data.
            if fields.first == "action" { continue }

            guard let action = try parseRow(fields, line: number, platform: platform) else { continue }
            actions.append(action)
        }
        return actions
    }

    /// RFC 4180: fields may be quoted, and a doubled quote inside a quoted
    /// field is one literal quote. Written out rather than split on commas
    /// because the `note` column is free text and will contain them.
    private static func splitCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(row)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseRow(
        _ fields: [String],
        line: Int,
        platform: ActionFilePlatform
    ) throws -> InputAction? {
        guard let verb = fields.first, !verb.isEmpty else { return nil }

        func value(_ index: Int) -> String? {
            guard index < fields.count, !fields[index].isEmpty else { return nil }
            return fields[index]
        }

        if let rawPlatform = value(8), !rawPlatform.isEmpty {
            let labels = rawPlatform.split(separator: "|").map(String.init)
            guard !labels.isEmpty else {
                throw ActionFileError.unknownPlatform(rawPlatform, line: line)
            }
            let platforms = try labels.map { label in
                guard let actionPlatform = ActionFilePlatform(rawValue: label) else {
                    throw ActionFileError.unknownPlatform(label, line: line)
                }
                return actionPlatform
            }
            guard platforms.contains(where: { $0.matches(platform) }) else {
                throw ActionFileError.wrongPlatform(rawPlatform, expected: platform, line: line)
            }
        }

        let origin: Origin
        if let raw = value(3) {
            guard let parsed = Origin(rawValue: raw) else {
                throw ActionFileError.unknownOrigin(raw, line: line)
            }
            origin = parsed
        } else {
            origin = .client
        }

        // A position is optional for the click and button verbs and required
        // for `move`. Partially given -- an x with no y -- is an error rather
        // than a default, because a silently assumed zero would click in the
        // corner and look like a missed target.
        let point: Point?
        switch (value(1), value(2)) {
            case let (rawX?, rawY?):
                guard let x = Double(rawX), let y = Double(rawY) else {
                    throw ActionFileError.badNumber("\(rawX),\(rawY)", line: line)
                }
                point = Point(x: x, y: y, origin: origin)
            case (nil, nil):
                point = nil
            default:
                throw ActionFileError.incompletePosition(line: line)
        }

        func button() throws -> MouseButton {
            guard let raw = value(4) else {
                throw ActionFileError.missingButton(verb: verb, line: line)
            }
            guard let parsed = MouseButton(rawValue: raw) else {
                throw ActionFileError.unknownButton(raw, line: line)
            }
            return parsed
        }

        func key() throws -> Key {
            guard let raw = value(5) else {
                throw ActionFileError.missingKey(verb: verb, line: line)
            }
            // Rejected, not skipped. A key name this table does not know is
            // almost always a name borrowed from X11 or Win32, and skipping the
            // row would run the file to completion having quietly done less
            // than it says.
            guard let parsed = Key(rawValue: raw) else {
                throw ActionFileError.unknownKey(raw, line: line)
            }
            return parsed
        }

        switch verb {
            case "move":
                guard let point else { throw ActionFileError.missingPosition(verb: verb, line: line) }
                return .move(point)
            case "click": return .click(try button(), at: point)
            case "doubleclick": return .doubleClick(try button(), at: point)
            case "mousedown": return .mouseDown(try button(), at: point)
            case "mouseup": return .mouseUp(try button(), at: point)
            case "scroll":
                // x and y are wheel notches here, not a position. The verb
                // scrolls wherever the pointer already is -- see InputAction --
                // so `origin` is meaningless for it and a `frame` on a scroll
                // row is a sign the writer expected it to move the pointer.
                // 此處的 x 與 y 是滾輪格數而非位置。此動作作用於指標當下所在之處（見 InputAction），
                // 因此 `origin` 對它毫無意義；scroll 列上出現 `frame` 即代表撰寫者誤以為它會移動指標。
                guard let point else {
                    throw ActionFileError.missingPosition(verb: verb, line: line)
                }
                return .scroll(dx: Int(point.x), dy: Int(point.y))
            case "keydown": return .keyDown(try key())
            case "keyup": return .keyUp(try key())
            case "key": return .key(try key())
            case "sleep":
                guard let raw = value(6), let micros = Int(raw) else {
                    throw ActionFileError.badNumber(value(6) ?? "", line: line)
                }
                return .sleep(microseconds: micros)
            default:
                throw ActionFileError.unknownAction(verb, line: line)
        }
    }
}

/// Every case names the offending line, because a file is edited by hand and a
/// parse error without a line number sends the reader to the top of it.
public enum ActionFileError: Error, Equatable, CustomStringConvertible {
    case unknownAction(String, line: Int)
    case unknownKey(String, line: Int)
    case unknownButton(String, line: Int)
    case unknownOrigin(String, line: Int)
    case unknownPlatform(String, line: Int)
    case wrongPlatform(String, expected: ActionFilePlatform, line: Int)
    case missingKey(verb: String, line: Int)
    case missingButton(verb: String, line: Int)
    case missingPosition(verb: String, line: Int)
    case incompletePosition(line: Int)
    case badNumber(String, line: Int)

    public var description: String {
        switch self {
            case .unknownAction(let name, let line):
                "line \(line): unknown action '\(name)'"
            case .unknownKey(let name, let line):
                "line \(line): unknown key '\(name)'; names follow macOS, see the InputEvent README"
            case .unknownButton(let name, let line):
                "line \(line): unknown button '\(name)'; expected left, right or middle"
            case .unknownOrigin(let name, let line):
                "line \(line): unknown origin '\(name)'; expected client or frame"
            case .unknownPlatform(let name, let line):
                "line \(line): unknown platform '\(name)'; expected any, macos, windows, gtk, ios or android"
            case .wrongPlatform(let actual, let expected, let line):
                "line \(line): action file is for \(actual), current backend is \(expected.rawValue)"
            case .missingKey(let verb, let line):
                "line \(line): '\(verb)' needs a key"
            case .missingButton(let verb, let line):
                "line \(line): '\(verb)' needs a button"
            case .missingPosition(let verb, let line):
                "line \(line): '\(verb)' needs x and y"
            case .incompletePosition(let line):
                "line \(line): x given without y, or y without x"
            case .badNumber(let raw, let line):
                "line \(line): '\(raw)' is not a number"
        }
    }
}
