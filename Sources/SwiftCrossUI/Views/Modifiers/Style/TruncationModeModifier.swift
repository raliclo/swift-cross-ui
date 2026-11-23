extension Text {
    /// Where text that does not fit is cut short, as SwiftUI's `Text.TruncationMode`.
    /// 放不下的文字從哪裡截斷，即 SwiftUI 的 `Text.TruncationMode`。
    public enum TruncationMode: Hashable, Sendable {
        /// At the start: "…end of the text". / 從開頭:「…文字的結尾」。
        case head
        /// At the end: "Start of the…". / 從結尾:「文字的開…」。
        case tail
        /// In the middle: "Start…end". / 從中間:「開頭…結尾」。
        case middle
    }
}

extension EnvironmentValues {
    /// Where text in this scope is cut short when it does not fit. Set by
    /// ``View/truncationMode(_:)``.
    /// 此範圍內的文字放不下時從哪裡截斷。由 ``View/truncationMode(_:)`` 設定。
    @Entry public var truncationMode: Text.TruncationMode = .tail
}

extension View {
    /// Sets where the text in this view is cut short when it does not fit, as
    /// SwiftUI's `truncationMode(_:)`.
    /// 設定此 view 中的文字放不下時從哪裡截斷，即 SwiftUI 的 `truncationMode(_:)`。
    public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }
}
