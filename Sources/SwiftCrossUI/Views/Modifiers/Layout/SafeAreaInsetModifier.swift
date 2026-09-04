extension View {
    /// Places a view along one edge of this view and shrinks this view to make
    /// room for it.
    ///
    /// Composed from `VStack` and `HStack`, so no backend gains a requirement
    /// from it -- the property that decided the order of the parity work added
    /// alongside it. See ``Stepper``.
    ///
    /// **How this differs from SwiftUI, and it is not nothing.** SwiftUI also
    /// writes the inset into the environment's safe area, so a `ScrollView`
    /// *underneath* extends its content beneath the bar and merely pads its
    /// scroll range. This modifier stacks instead: the bar takes its space and
    /// the content ends where the bar begins. On a desktop toolkit with opaque
    /// bars the two look the same; with a translucent bar they do not, because
    /// nothing scrolls under this one.
    ///
    /// That difference is stated here rather than left to be met, because the
    /// symptom -- content stopping short of the edge -- reads as a layout bug
    /// rather than as a documented boundary.
    ///
    /// 沿著此 view 的某一邊放置另一個 view，並縮小此 view 以騰出空間。
    ///
    /// 由 `VStack` 與 `HStack` 組合而成，因此沒有任何 backend 因它而多出要求——這正是與它一同
    /// 新增的那批 parity 工作之所以如此排序的性質。見 ``Stepper``。
    ///
    /// **它與 SwiftUI 的差別何在，而那並非無關緊要。** SwiftUI 還會把該內縮寫入環境的 safe area，
    /// 因此**位於下方**的 `ScrollView` 會把內容延伸到那條列之下，只是把捲動範圍加上內距。此處的
    /// modifier 則是堆疊：那條列取走它的空間，內容就在列開始之處結束。在使用不透明列的桌面 toolkit
    /// 上，兩者看起來相同；若列是半透明的則不然，因為此處沒有任何東西會捲到它底下。
    ///
    /// 這項差別寫在此處而非留給人自己撞上，因為它的症狀——內容沒有延伸到邊緣——讀起來像是版面
    /// bug，而不像一條已寫明的界線。
    ///
    /// - Parameters:
    ///   - edge: Which edge to place `content` along.
    ///   - spacing: The gap between `content` and this view. Defaults to the
    ///     enclosing stack's usual spacing.
    ///   - content: The view to place along `edge`.
    public func safeAreaInset<Inset: View>(
        edge: Edge,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Inset
    ) -> some View {
        SafeAreaInsetContainer(edge: edge, spacing: spacing, inset: content(), body: self)
    }
}

/// The stack that does the work.
///
/// A view rather than a `@ViewBuilder`-returning expression in the extension
/// above, because the four edges produce two different stack types and one of
/// two orders. Writing that inline gives an opaque return type that changes
/// shape per edge, which does not compile; naming it puts the branch inside a
/// single `body`.
///
/// 真正做事的那個 stack。
///
/// 之所以寫成一個 view，而不是上方 extension 裡一個回傳 `@ViewBuilder` 的運算式，是因為四個邊
/// 會產生兩種不同的 stack 型別、以及兩種先後順序之一。把那寫成內聯會得到一個「形狀隨邊而變」的
/// opaque return type，那無法編譯；給它一個名字，就把分支收進單一個 `body` 之內。
struct SafeAreaInsetContainer<Inset: View, Content: View>: View {
    var edge: Edge
    var spacing: Int?
    var inset: Inset
    var body_: Content

    init(edge: Edge, spacing: Int?, inset: Inset, body: Content) {
        self.edge = edge
        self.spacing = spacing
        self.inset = inset
        self.body_ = body
    }

    var body: some View {
        switch edge {
            case .top:
                VStack(spacing: spacing) {
                    inset
                    body_
                }
            case .bottom:
                VStack(spacing: spacing) {
                    body_
                    inset
                }
            case .leading:
                HStack(spacing: spacing) {
                    inset
                    body_
                }
            case .trailing:
                HStack(spacing: spacing) {
                    body_
                    inset
                }
        }
    }
}
