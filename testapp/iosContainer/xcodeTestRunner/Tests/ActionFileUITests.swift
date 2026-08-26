import XCTest

final class ActionFileUITests: XCTestCase {
    private let bundleIdentifier = "dev.swiftcrossui.testapp.debugTarget"

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
            case "keydown", "keyup", "key", "scroll":
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

    var description: String {
        switch self {
        case .malformed(let line): return "Malformed action file row at line \(line)"
        case .invalidCoordinate(let line): return "Invalid iOS coordinate at line \(line)"
        case .unsupported(let action, let line): return "Unsupported iOS action '\(action)' at line \(line)"
        }
    }
}
