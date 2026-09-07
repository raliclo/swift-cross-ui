/// A box that visually groups a set of related views under an optional title.
///
/// Composed from `VStack`, `padding` and `border`, so it needs nothing from any
/// backend. See ``Stepper`` for why this batch was chosen.
///
/// **This is the box, not the platform's group-box chrome.** SwiftUI's
/// `GroupBox` draws whatever the platform's own grouping container looks like --
/// a rounded, filled, slightly recessed panel on macOS, a plain inset block on
/// iOS -- and it takes its title's font and colour from there too. This draws a
/// one-point rectangle around padded content and nothing else, so a `GroupBox`
/// looks the same on all five backends and its title is ordinary body text.
/// Said plainly rather than left to be found: the shape is right, the platform
/// styling is absent. ``Form`` and ``Section`` carry the same note for the same
/// reason.
///
/// The border is drawn *outside* the padding, not inside it, because
/// ``View/border(_:width:)`` does not change layout. Putting `.padding` first is
/// therefore what separates the content from the line; the opposite order draws
/// the line straight through the content's edge.
///
/// 一個帶有可選標題、用來在視覺上把一組相關 view 圈起來的方框。
///
/// 由 `VStack`、`padding` 與 `border` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，
/// 見 ``Stepper``。
///
/// **這是那個方框，而不是平台自身的 group box 外觀。** SwiftUI 的 `GroupBox` 畫的是該平台自身分組
/// 容器的樣子——macOS 上是圓角、帶填色、略微內凹的面板，iOS 上則是單純的內縮區塊——連標題的字體與
/// 顏色也取自那裡。此處只在加了內距的內容外畫一個一點寬的矩形，別無其他，因此 `GroupBox` 在五個
/// backend 上看起來完全一樣，其標題也就是一般的內文文字。這一點明說而不留給人自己發現：**形狀是
/// 對的、平台樣式是缺的**。``Form`` 與 ``Section`` 帶有同樣的說明，理由相同。
///
/// 邊框畫在內距的**外側**而非內側，因為 ``View/border(_:width:)`` 不會改變版面配置。因此先套用
/// `.padding` 正是讓內容與線條分開的原因；順序相反的話，線會直接畫過內容的邊緣。
public struct GroupBox<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(content: content(), label: label())
    }

    /// Takes both views as VALUES, which the convenience initialisers need. See
    /// ``Stepper``'s equivalent for why they cannot go through the
    /// `@ViewBuilder` form.
    ///
    /// 以**值**的形式接收兩個 view，這是便利建構式所需要的。它們為何不能走 `@ViewBuilder` 那一版，
    /// 見 ``Stepper`` 中的對應說明。
    private init(content: Content, label: Label) {
        self.content = content
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            content
        }
        .padding(12)
        .border(Color.gray)
    }
}

extension GroupBox where Label == Text {
    /// The common case, matching SwiftUI's `GroupBox("Title") { … }`.
    /// 常見情形，對應 SwiftUI 的 `GroupBox("Title") { … }`。
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content(), label: Text(title))
    }
}

extension GroupBox where Label == EmptyView {
    /// Untitled, which is a real SwiftUI shape rather than only a convenience --
    /// an untitled `GroupBox` still draws the box, which is the whole reason
    /// somebody reaches for one.
    ///
    /// 無標題，這是 SwiftUI 中真實存在的形式，而不只是便利建構式——沒有標題的 `GroupBox` 仍然會把
    /// 方框畫出來，而那正是有人會用它的全部理由。
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content(), label: EmptyView())
    }
}
