// A small XML reader for SVG files.
//
// Written here rather than taken from Foundation's `XMLParser` on purpose.
// `FoundationXML` does exist on all five shipped platforms (checked
// 2026-10-09: the swift.org 6.4.0 Android SDK carries `libFoundationXML.so`
// and `libxml2`), but using it would make every app that shows an image link
// libxml2 and ship one more shared library -- on Android and Windows that is
// a packaging change per app, and the Windows side cannot be checked from the
// Mac where this was written. SVG needs elements, attributes, text, comments,
// CDATA and the five predefined entities; that is a few hundred lines, and the
// same lines then run on every backend.
//
// 一個給 SVG 用的小型 XML 讀取器。刻意不使用 Foundation 的 `XMLParser`:`FoundationXML` 在五個
// 已發布平台上確實都有(2026-10-09 查過:swift.org 6.4.0 Android SDK 帶有 `libFoundationXML.so`
// 與 `libxml2`),但用它會讓每一支顯示影像的 app 連結 libxml2、多帶一個共享函式庫——在 Android 與
// Windows 上那是每支 app 的打包變更，而 Windows 那一側無法從寫這段程式的 Mac 上查證。SVG 只需要
// 元素、屬性、文字、註解、CDATA 與五個預先定義的實體；那是幾百行，而且同樣的這幾百行會在每一個
// backend 上執行。

/// One element of a parsed XML document.
///
/// 已解析 XML 文件中的一個元素。
final class SVGXMLElement {
    /// The qualified name as written, prefix included (`svg`, `inkscape:label`).
    /// 原樣的限定名稱，包含前綴。
    let name: String
    /// Attributes in document order.
    /// 依文件順序排列的屬性。
    var attributes: [(name: String, value: String)]
    var children: [SVGXMLElement] = []
    /// Character data directly inside this element, concatenated.
    /// 直接位於此元素內的字元資料，串接而成。
    var text: String = ""

    init(name: String, attributes: [(name: String, value: String)]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(attribute name: String) -> String? {
        for attribute in attributes where attribute.name == name {
            return attribute.value
        }
        return nil
    }

    /// The name without its namespace prefix.
    /// 去掉命名空間前綴的名稱。
    var localName: String {
        if let colon = name.lastIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }

    /// The namespace prefix, or `nil` when there is none.
    /// 命名空間前綴；沒有時為 `nil`。
    var prefix: String? {
        if let colon = name.firstIndex(of: ":") {
            return String(name[..<colon])
        }
        return nil
    }
}

/// Why an XML document could not be read.
///
/// XML 文件無法讀取的原因。
public struct SVGParseError: Error, Sendable, CustomStringConvertible {
    /// Byte offset into the input where the problem was found.
    /// 發現問題之處在輸入中的位元組位移。
    public var offset: Int
    public var message: String

    public var description: String {
        "SVG parse error at byte \(offset): \(message)"
    }
}

/// Reads bytes into an element tree. Only the root element is returned.
///
/// 將位元組讀成元素樹，只回傳根元素。
struct SVGXMLReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func parse(_ bytes: [UInt8]) throws -> SVGXMLElement {
        var reader = SVGXMLReader(bytes)
        return try reader.parseDocument()
    }

    private func error(_ message: String) -> SVGParseError {
        SVGParseError(offset: index, message: message)
    }

    private func peek(_ offset: Int = 0) -> UInt8? {
        let position = index + offset
        return position < bytes.count ? bytes[position] : nil
    }

    private func hasPrefix(_ literal: String) -> Bool {
        let utf8 = Array(literal.utf8)
        guard index + utf8.count <= bytes.count else { return false }
        for (offset, byte) in utf8.enumerated() where bytes[index + offset] != byte {
            return false
        }
        return true
    }

    /// Advances past `terminator`; throws if it never appears.
    /// 前進越過 `terminator`;若它從未出現則拋出錯誤。
    private mutating func skip(past terminator: String, what: String) throws {
        let utf8 = Array(terminator.utf8)
        while index + utf8.count <= bytes.count {
            if hasPrefix(terminator) {
                index += utf8.count
                return
            }
            index += 1
        }
        throw error("unterminated \(what)")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        // Letters, digits, `_ - . :` and every non-ASCII byte (UTF-8 names).
        // 字母、數字、`_ - . :` 與所有非 ASCII 位元組(UTF-8 名稱)。
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F || byte == 0x2D
            || byte == 0x2E || byte == 0x3A || byte >= 0x80
    }

    private mutating func skipSpaces() {
        while let byte = peek(), Self.isSpace(byte) {
            index += 1
        }
    }

    private mutating func readName() throws -> String {
        let start = index
        while let byte = peek(), Self.isNameByte(byte) {
            index += 1
        }
        guard index > start else {
            throw error("expected a name")
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseDocument() throws -> SVGXMLElement {
        // UTF-8 byte order mark.
        if hasPrefix("\u{FEFF}") {
            index += 3
        }
        var stack: [SVGXMLElement] = []
        var root: SVGXMLElement?

        while index < bytes.count {
            if peek() == UInt8(ascii: "<") {
                if hasPrefix("<!--") {
                    try skip(past: "-->", what: "comment")
                } else if hasPrefix("<![CDATA[") {
                    index += 9
                    let start = index
                    try skip(past: "]]>", what: "CDATA section")
                    stack.last?.text += String(
                        decoding: bytes[start..<(index - 3)], as: UTF8.self)
                } else if hasPrefix("<?") {
                    try skip(past: "?>", what: "processing instruction")
                } else if hasPrefix("<!") {
                    try skipDeclaration()
                } else if hasPrefix("</") {
                    index += 2
                    let name = try readName()
                    skipSpaces()
                    guard peek() == UInt8(ascii: ">") else {
                        throw error("expected '>' after </\(name)")
                    }
                    index += 1
                    guard let open = stack.popLast() else {
                        throw error("</\(name)> closes nothing")
                    }
                    guard open.name == name else {
                        throw error("</\(name)> closes <\(open.name)>")
                    }
                } else {
                    index += 1
                    let (element, isOpen) = try parseStartTag()
                    if let parent = stack.last {
                        parent.children.append(element)
                    } else if root == nil {
                        root = element
                    } else {
                        throw error("a second root element <\(element.name)>")
                    }
                    if isOpen {
                        stack.append(element)
                    }
                }
            } else {
                let start = index
                while let byte = peek(), byte != UInt8(ascii: "<") {
                    index += 1
                }
                if let current = stack.last {
                    current.text += Self.decodeEntities(
                        String(decoding: bytes[start..<index], as: UTF8.self))
                }
            }
        }

        if let open = stack.last {
            throw error("<\(open.name)> is never closed")
        }
        guard let root else {
            throw error("no root element")
        }
        return root
    }

    /// `<!DOCTYPE …>`, which may hold an internal subset in brackets.
    /// `<!DOCTYPE …>`,其中可能以中括號包含內部子集。
    private mutating func skipDeclaration() throws {
        var depth = 0
        var quote: UInt8? = nil
        while let byte = peek() {
            index += 1
            if let open = quote {
                if byte == open { quote = nil }
                continue
            }
            switch byte {
                case UInt8(ascii: "\""), UInt8(ascii: "'"):
                    quote = byte
                case UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "]"):
                    depth -= 1
                case UInt8(ascii: ">") where depth <= 0:
                    return
                default:
                    break
            }
        }
        throw error("unterminated declaration")
    }

    private mutating func parseStartTag() throws -> (element: SVGXMLElement, isOpen: Bool) {
        let name = try readName()
        var attributes: [(name: String, value: String)] = []
        while true {
            skipSpaces()
            guard let byte = peek() else {
                throw error("unterminated start tag <\(name)")
            }
            if byte == UInt8(ascii: "/") {
                guard peek(1) == UInt8(ascii: ">") else {
                    throw error("expected '/>' in <\(name)")
                }
                index += 2
                return (SVGXMLElement(name: name, attributes: attributes), false)
            }
            if byte == UInt8(ascii: ">") {
                index += 1
                return (SVGXMLElement(name: name, attributes: attributes), true)
            }
            let attributeName = try readName()
            skipSpaces()
            guard peek() == UInt8(ascii: "=") else {
                throw error("attribute \(attributeName) in <\(name)> has no value")
            }
            index += 1
            skipSpaces()
            guard let quote = peek(), quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'")
            else {
                throw error("attribute \(attributeName) in <\(name)> is not quoted")
            }
            index += 1
            let start = index
            while let byte = peek(), byte != quote {
                index += 1
            }
            guard index < bytes.count else {
                throw error("unterminated value of \(attributeName)")
            }
            let raw = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            attributes.append((attributeName, Self.decodeEntities(raw)))
        }
    }

    /// The five predefined entities and numeric character references. An
    /// unknown entity is kept as written.
    ///
    /// 五個預先定義的實體與數字字元參照。未知的實體依原樣保留。
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var rest = Substring(string)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            guard let semicolon = rest[afterAmpersand...].firstIndex(of: ";"),
                rest.distance(from: afterAmpersand, to: semicolon) <= 10
            else {
                result += "&"
                rest = rest[afterAmpersand...]
                continue
            }
            let entity = rest[afterAmpersand..<semicolon]
            var replacement: String? = nil
            switch entity {
                case "lt": replacement = "<"
                case "gt": replacement = ">"
                case "amp": replacement = "&"
                case "quot": replacement = "\""
                case "apos": replacement = "'"
                default:
                    if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                        if let value = UInt32(entity.dropFirst(2), radix: 16),
                            let scalar = Unicode.Scalar(value)
                        {
                            replacement = String(Character(scalar))
                        }
                    } else if entity.hasPrefix("#") {
                        if let value = UInt32(entity.dropFirst()),
                            let scalar = Unicode.Scalar(value)
                        {
                            replacement = String(Character(scalar))
                        }
                    }
            }
            if let replacement {
                result += replacement
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result += "&"
                rest = rest[afterAmpersand...]
            }
        }
        result += rest
        return result
    }
}
