/// Content that can be shown or hidden by its own header row.
///
/// Composed from `Button`, `VStack` and a conditional, so it needs nothing from
/// any backend. See ``Stepper`` for why that decided the order of this work.
///
/// The expansion state can be owned here or by the caller. Both initialisers
/// exist because SwiftUI has both, and because the difference is not
/// cosmetic: a group that owns its state collapses again whenever the view
/// identity changes, which is the wrong behaviour for a list row that scrolls
/// out and back.
///
/// 一段可由自身標題列展開或收合的內容。
///
/// 由 `Button`、`VStack` 與一個條件式組合而成，不需要任何 backend 支援。這為何決定了本批工作的
/// 順序，見 ``Stepper``。
///
/// 展開狀態可以由它自己擁有，也可以由呼叫端擁有。兩種初始化器都提供，因為 SwiftUI 兩種都有，
/// 也因為兩者的差別**不是外觀問題**：一個自己持有狀態的 group，會在 view identity 改變時再次
/// 收合——對於一個捲出畫面又捲回來的清單列而言，那是錯的行為。
public struct DisclosureGroup<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    /// Owned when the caller passed no binding.
    /// 呼叫端未傳入 binding 時，由此處持有。
    @State private var internalIsExpanded: Bool
    private let externalIsExpanded: Binding<Bool>?

    private var isExpanded: Bool {
        externalIsExpanded?.wrappedValue ?? internalIsExpanded
    }

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(binding: isExpanded, initiallyExpanded: isExpanded.wrappedValue, content: content(), label: label())
    }

    public init(
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(binding: nil, initiallyExpanded: initiallyExpanded, content: content(), label: label())
    }

    /// Takes both views as VALUES, and folds the two public initialisers into
    /// one. See ``Stepper``'s equivalent for why the convenience initialisers
    /// cannot go through the `@ViewBuilder` form.
    ///
    /// 以**值**的形式接收兩個 view，並把兩個 public 建構式收攏為一。便利建構式為何不能走
    /// `@ViewBuilder` 那一版，見 ``Stepper`` 中的對應說明。
    private init(
        binding: Binding<Bool>?,
        initiallyExpanded: Bool,
        content: Content,
        label: Label
    ) {
        self.externalIsExpanded = binding
        self._internalIsExpanded = State(wrappedValue: initiallyExpanded)
        self.content = content
        self.label = label
    }

    private func toggle() {
        if let externalIsExpanded {
            externalIsExpanded.wrappedValue.toggle()
        } else {
            internalIsExpanded.toggle()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The marker is part of the button, not beside it, so the whole
            // header row is the hit target rather than a glyph the user has to
            // aim at.
            // 標記屬於按鈕的一部分，而非置於其旁，因此整個標題列都是命中目標，而不是一個必須瞄準
            // 的字元。
            Button(isExpanded ? "\u{25BE}" : "\u{25B8}") { toggle() }
            label
            if isExpanded {
                content
            }
        }
    }
}

extension DisclosureGroup where Label == Text {
    public init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            binding: isExpanded,
            initiallyExpanded: isExpanded.wrappedValue,
            content: content(),
            label: Text(title)
        )
    }

    public init(
        _ title: String,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            binding: nil,
            initiallyExpanded: initiallyExpanded,
            content: content(),
            label: Text(title)
        )
    }
}
