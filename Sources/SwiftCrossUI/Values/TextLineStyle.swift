extension Text {
    /// How an underline or a strikethrough is drawn, as SwiftUI's `Text.LineStyle`.
    ///
    /// 底線或刪除線的畫法，即 SwiftUI 的 `Text.LineStyle`。
    public struct LineStyle: Hashable, Sendable {
        /// The dash pattern of a line. / 線的虛線樣式。
        public enum Pattern: Hashable, Sendable {
            case solid
            case dot
            case dash
            case dashDot
            case dashDotDot
        }

        /// The dash pattern. / 虛線樣式。
        public var pattern: Pattern
        /// The line's colour; `nil` draws it in the text's colour.
        /// 線的顏色;`nil` 時使用文字的顏色。
        public var color: Color?

        /// A line with `pattern` in `color`. / 以 `color` 畫出的 `pattern` 線。
        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// A solid line in the text's colour. / 文字顏色的實線。
        public static let single = LineStyle()
    }
}

extension EnvironmentValues {
    /// The underline of text in this scope, or `nil` for none. Set by
    /// ``View/underline(_:pattern:color:)``.
    /// 此範圍內文字的底線，`nil` 表示沒有。由 ``View/underline(_:pattern:color:)`` 設定。
    @Entry public var underlineStyle: Text.LineStyle? = nil

    /// The strikethrough of text in this scope, or `nil` for none. Set by
    /// ``View/strikethrough(_:pattern:color:)``.
    /// 此範圍內文字的刪除線，`nil` 表示沒有。由 ``View/strikethrough(_:pattern:color:)`` 設定。
    @Entry public var strikethroughStyle: Text.LineStyle? = nil

    /// Extra space between character pairs, in points. Set by ``View/kerning(_:)``.
    /// 字元對之間額外的間距(點)。由 ``View/kerning(_:)`` 設定。
    @Entry public var kerning: Double = 0

    /// Extra space after every character, in points. Set by ``View/tracking(_:)``.
    /// 每個字元之後額外的間距(點)。由 ``View/tracking(_:)`` 設定。
    @Entry public var tracking: Double = 0

    /// How far text is raised above its baseline, in points; negative lowers
    /// it. Set by ``View/baselineOffset(_:)``.
    /// 文字相對於基線上移的距離(點);負值為下移。由 ``View/baselineOffset(_:)`` 設定。
    @Entry public var baselineOffset: Double = 0

    /// Extra space between the lines of wrapped text, in points. Set by
    /// ``View/lineSpacing(_:)``.
    /// 換行文字各行之間額外的間距(點)。由 ``View/lineSpacing(_:)`` 設定。
    @Entry public var lineSpacing: Double = 0

    /// The letter spacing for a backend with one setting for both kerning and
    /// tracking: tracking when set, as SwiftUI gives it precedence, else kerning.
    ///
    /// 給「kerning 與 tracking 只有一個設定」的 backend 使用的字距：有設定 tracking 時用它
    /// (SwiftUI 以它為優先),否則用 kerning。
    public var resolvedLetterSpacing: Double {
        tracking != 0 ? tracking : kerning
    }
}
