extension View {
    /// Lets the text in this view shrink to `factor` of its size, as SwiftUI's
    /// `minimumScaleFactor(_:)`, when it would not otherwise fit its proposed size
    /// or line limit. `factor` is clamped to 0.01...1.
    ///
    /// 讓此 view 中的文字在放不下提議的尺寸或行數限制時縮小，最小到原本大小的 `factor`,即 SwiftUI 的
    /// `minimumScaleFactor(_:)`。`factor` 會被限制在 0.01...1。
    public func minimumScaleFactor(_ factor: Double) -> some View {
        environment(\.minimumScaleFactor, min(max(factor, 0.01), 1))
    }
}

extension EnvironmentValues {
    /// How far text may shrink to fit, as a fraction of its size; 1 never shrinks it.
    /// Set by ``View/minimumScaleFactor(_:)``.
    /// 文字為了放得下可以縮小到的比例；1 表示不縮小。由 ``View/minimumScaleFactor(_:)`` 設定。
    @Entry public var minimumScaleFactor: Double = 1

    /// The scale ``Text`` chose to fit, applied to the resolved font's size and line
    /// height. Set only by Text's own layout.
    /// ``Text`` 為了放得下而選擇的倍率，套用在解析後字型的大小與行高上。只由 Text 自己的排版設定。
    @Entry var textScale: Double = 1
}
