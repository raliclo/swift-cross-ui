extension View {
    /// Underlines the text in this view, as SwiftUI's `underline(_:pattern:color:)`.
    /// 為此 view 中的文字加上底線，即 SwiftUI 的 `underline(_:pattern:color:)`。
    public func underline(
        _ isActive: Bool = true,
        pattern: Text.LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> some View {
        environment(
            \.underlineStyle,
            isActive ? Text.LineStyle(pattern: pattern, color: color) : nil
        )
    }

    /// Strikes through the text in this view, as SwiftUI's
    /// `strikethrough(_:pattern:color:)`.
    /// 為此 view 中的文字加上刪除線，即 SwiftUI 的 `strikethrough(_:pattern:color:)`。
    public func strikethrough(
        _ isActive: Bool = true,
        pattern: Text.LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> some View {
        environment(
            \.strikethroughStyle,
            isActive ? Text.LineStyle(pattern: pattern, color: color) : nil
        )
    }

    /// Adds `kerning` points between character pairs of the text in this view.
    /// 在此 view 文字的字元對之間加上 `kerning` 點的間距。
    public func kerning(_ kerning: Double) -> some View {
        environment(\.kerning, kerning)
    }

    /// Adds `tracking` points after every character of the text in this view.
    /// When both are set, tracking wins over kerning, as in SwiftUI.
    /// 在此 view 文字的每個字元之後加上 `tracking` 點的間距。兩者都設定時以 tracking 為準，與 SwiftUI 相同。
    public func tracking(_ tracking: Double) -> some View {
        environment(\.tracking, tracking)
    }

    /// Raises the text in this view `baselineOffset` points above its baseline.
    /// 把此 view 中的文字從基線上移 `baselineOffset` 點。
    public func baselineOffset(_ baselineOffset: Double) -> some View {
        environment(\.baselineOffset, baselineOffset)
    }

    /// Adds `lineSpacing` points between the lines of wrapped text in this view.
    /// 在此 view 換行文字的各行之間加上 `lineSpacing` 點的間距。
    public func lineSpacing(_ lineSpacing: Double) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }
}
