/// A label paired with a value, with the value pushed to the trailing edge.
///
/// Composed from `HStack`, `Text` and `Spacer`, so it needs nothing from any
/// backend. See ``Stepper`` for why that property decided the order this batch
/// of parity work was done in.
///
/// The `Spacer` is the whole difference from writing the two views side by
/// side, and it is what `testapp/P33.swift`'s hand-built approximation left
/// out: without it the value sits against the label instead of against the
/// trailing edge, and a column of these does not line up.
///
/// 一個標籤配上一個值，值被推到尾端邊緣。
///
/// 由 `HStack`、`Text` 與 `Spacer` 組合而成，不需要任何 backend 支援。這項性質為何決定了這批
/// parity 工作的先後順序，見 ``Stepper``。
///
/// 那個 `Spacer` 正是它與「把兩個 view 並排寫」的全部差別，也正是 `testapp/P33.swift` 手工近似
/// 版本所遺漏的東西：少了它，值會貼著標籤而不是貼著尾端邊緣，而一整欄這樣的項目就不會對齊。
public struct LabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(content: content(), label: label())
    }

    /// Takes both views as VALUES. See ``Stepper``'s equivalent for why the
    /// convenience initialisers cannot go through the `@ViewBuilder` form.
    /// 以**值**的形式接收兩個 view。便利建構式為何不能走 `@ViewBuilder` 那一版，見 ``Stepper``
    /// 中的對應說明。
    private init(content: Content, label: Label) {
        self.content = content
        self.label = label
    }

    public var body: some View {
        HStack {
            label
            Spacer()
            content
        }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    /// The common case: two strings.
    /// 常見情形：兩個字串。
    public init(_ title: String, value: String) {
        self.init(content: Text(value), label: Text(title))
    }
}

extension LabeledContent where Label == Text {
    /// A titled row whose value is any view.
    /// 一個帶標題的列，其值可以是任何 view。
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content(), label: Text(title))
    }
}
