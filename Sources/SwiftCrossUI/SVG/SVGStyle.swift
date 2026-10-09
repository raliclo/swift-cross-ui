import Foundation

// CSS for SVG: the `style` attribute and simple `<style>` sheets.
// SVG 用的 CSS:`style` 屬性與簡單的 `<style>` 樣式表。

/// One `<style>` rule after parsing. Only simple selectors are kept --
/// `*`, `tag`, `.class`, `#id` and compounds of them such as `path.track`.
///
/// 解析後的一條 `<style>` 規則。只保留簡單選擇器——`*`、`tag`、`.class`、`#id` 及其複合，例如
/// `path.track`。
struct SVGStyleRule {
    struct Selector {
        var tag: String?
        var id: String?
        var classes: [String]

        /// (ids, classes, tags), compared lexicographically.
        /// (id 數、class 數、tag 數),依字典序比較。
        var specificity: (Int, Int, Int) {
            (id == nil ? 0 : 1, classes.count, tag == nil ? 0 : 1)
        }

        func matches(tag elementTag: String, id elementID: String?, classes elementClasses: [String])
            -> Bool
        {
            if let tag, tag != elementTag { return false }
            if let id, id != elementID { return false }
            for name in classes where !elementClasses.contains(name) {
                return false
            }
            return true
        }
    }

    var selector: Selector
    var declarations: [(name: String, value: String)]
    var order: Int
}

enum SVGCSS {
    /// Splits `a: b; c: d` into declarations. Names are lowercased;
    /// `!important` is dropped (it is read as an ordinary declaration).
    ///
    /// 把 `a: b; c: d` 切成宣告。名稱轉成小寫；`!important` 會被去掉(視為一般宣告)。
    static func declarations(_ text: String) -> [(name: String, value: String)] {
        var result: [(name: String, value: String)] = []
        for part in splitOutsideParentheses(text, separator: ";") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let name = part[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = part[part.index(after: colon)...].trimmingCharacters(
                in: .whitespacesAndNewlines)
            if let bang = value.range(of: "!important", options: .caseInsensitive) {
                value = value[..<bang.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !name.isEmpty {
                result.append((name, value))
            }
        }
        return result
    }

    private static func splitOutsideParentheses(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(0, depth - 1) }
            if character == separator && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    /// Parses a style sheet. Rules whose selectors this reader does not
    /// understand are returned in `unsupported` so they can be reported.
    ///
    /// 解析樣式表。本讀取器看不懂其選擇器的規則會放在 `unsupported` 中回傳，以便回報。
    static func parseSheet(_ sheet: String, firstOrder: Int) -> (
        rules: [SVGStyleRule], unsupported: [String]
    ) {
        var text = sheet
        // Comments.
        while let start = text.range(of: "/*") {
            if let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                text.removeSubrange(start.lowerBound..<text.endIndex)
            }
        }
        var rules: [SVGStyleRule] = []
        var unsupported: [String] = []
        var order = firstOrder
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            let selectorText = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            // Find the matching brace (at-rules such as @media nest blocks).
            // 找到對應的右大括號(@media 這類 at-rule 會巢狀包含區塊)。
            var depth = 0
            var close = open
            var index = open
            while index < rest.endIndex {
                if rest[index] == "{" { depth += 1 }
                if rest[index] == "}" {
                    depth -= 1
                    if depth == 0 {
                        close = index
                        break
                    }
                }
                index = rest.index(after: index)
            }
            if close == open {
                unsupported.append("unterminated rule '\(selectorText)'")
                break
            }
            let body = String(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]

            if selectorText.hasPrefix("@") {
                unsupported.append("at-rule '\(selectorText)'")
                continue
            }
            let declarations = Self.declarations(body)
            for selectorPart in selectorText.split(separator: ",") {
                let trimmed = selectorPart.trimmingCharacters(in: .whitespacesAndNewlines)
                if let selector = parseSelector(trimmed) {
                    rules.append(
                        SVGStyleRule(selector: selector, declarations: declarations, order: order))
                    order += 1
                } else {
                    unsupported.append("selector '\(trimmed)'")
                }
            }
        }
        return (rules, unsupported)
    }

    static func parseSelector(_ text: String) -> SVGStyleRule.Selector? {
        guard !text.isEmpty else { return nil }
        if text == "*" {
            return SVGStyleRule.Selector(tag: nil, id: nil, classes: [])
        }
        var tag: String? = nil
        var id: String? = nil
        var classes: [String] = []
        var index = text.startIndex
        func readIdentifier() -> String? {
            let start = index
            while index < text.endIndex,
                text[index].isLetter || text[index].isNumber || text[index] == "-"
                    || text[index] == "_"
            {
                index = text.index(after: index)
            }
            return start == index ? nil : String(text[start..<index])
        }
        while index < text.endIndex {
            let character = text[index]
            if character == "." {
                index = text.index(after: index)
                guard let name = readIdentifier() else { return nil }
                classes.append(name)
            } else if character == "#" {
                index = text.index(after: index)
                guard id == nil, let name = readIdentifier() else { return nil }
                id = name
            } else if character == "*" && index == text.startIndex {
                index = text.index(after: index)
            } else if tag == nil && index == text.startIndex,
                let name = readIdentifier()
            {
                tag = name
            } else {
                // Combinators, attribute selectors, pseudo-classes.
                // 組合子、屬性選擇器、偽類別。
                return nil
            }
        }
        return SVGStyleRule.Selector(tag: tag, id: id, classes: classes)
    }
}
