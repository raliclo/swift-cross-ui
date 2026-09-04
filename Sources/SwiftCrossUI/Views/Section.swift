/// A titled group of views, with an optional footer.
///
/// Composed from `VStack`, `Text` and `Divider`, so it needs nothing from any
/// backend. See ``Stepper`` for why this batch was chosen.
///
/// **This is a grouping, not a `Form` row style.** SwiftUI's `Section` looks
/// different inside a `Form` or a `List` than it does on its own, because the
/// container styles it. Nothing here does that yet, so a `Section` renders the
/// same wherever it is put. That is stated rather than left to be discovered:
/// the shape is right and the platform styling is absent, which is exactly the
/// distinction this project asks to be spelled out instead of quietly shipped.
///
/// 一組帶標題的 view，並可選擇性附上頁尾。
///
/// 由 `VStack`、`Text` 與 `Divider` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，
/// 見 ``Stepper``。
///
/// **這是一種分組，而不是 `Form` 的列樣式。** SwiftUI 的 `Section` 放在 `Form` 或 `List` 內時，
/// 外觀與單獨使用時不同，因為是容器在為它上樣式。此處尚無任何東西這麼做，因此 `Section` 不論放在
/// 哪裡都畫成同一個樣子。這一點明說而不留給人自己發現：**形狀是對的、平台樣式是缺的**——而那正是
/// 本專案要求寫明、而非默默出貨的那種區別。
public struct Section<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(content: content(), header: header(), footer: footer())
    }

    /// Takes all three views as VALUES. See ``Stepper``'s equivalent for why the
    /// convenience initialisers cannot go through the `@ViewBuilder` form.
    /// 以**值**的形式接收三個 view。便利建構式為何不能走 `@ViewBuilder` 那一版，見 ``Stepper``
    /// 中的對應說明。
    private init(content: Content, header: Header, footer: Footer) {
        self.content = content
        self.header = header
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            content
            footer
        }
    }
}

extension Section where Footer == EmptyView {
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        self.init(content: content(), header: header(), footer: EmptyView())
    }
}

extension Section where Header == Text, Footer == EmptyView {
    /// The common case, matching SwiftUI's `Section("Title") { … }`.
    /// 常見情形，對應 SwiftUI 的 `Section("Title") { … }`。
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content(), header: Text(title), footer: EmptyView())
    }
}

extension Section where Header == EmptyView, Footer == EmptyView {
    /// Untitled, which is a real SwiftUI shape and not just a convenience --
    /// a `Section` with no header still separates its content from what
    /// precedes it.
    /// 無標題，這是 SwiftUI 中真實存在的形式，而非只是便利建構式——沒有標題的 `Section` 仍然會把
    /// 它的內容與其前方的東西分隔開。
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content(), header: EmptyView(), footer: EmptyView())
    }
}
