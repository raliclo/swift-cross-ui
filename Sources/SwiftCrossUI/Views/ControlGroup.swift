/// A cluster of related controls, presented together as one unit.
///
/// Composed from `VStack` and `HStack`, so it needs nothing from any backend.
/// See ``Stepper`` for why this batch was chosen.
///
/// **This is the grouping, not the segmented control.** SwiftUI's
/// `ControlGroup` hands its children to the platform's own segmented container:
/// on macOS and iOS the buttons lose their individual borders and become
/// sections of a single joined bar, and in a toolbar the whole group collapses
/// into an overflow menu when space runs short. Neither happens here. This is an
/// `HStack` with no spacing, so the children keep whatever appearance they
/// already had and sit flush against one another -- close to the segmented
/// picture on backends whose buttons draw their own border, and merely tight on
/// the rest. Nothing collapses when space runs short. Said plainly rather than
/// left to be found: the shape is right, the platform styling is absent.
/// ``Form``, ``Section`` and ``GroupBox`` carry the same note for the same
/// reason.
///
/// The spacing is `0` deliberately rather than by omission. A ``ControlGroup``
/// whose children are separated look like several unrelated controls, which is
/// the one thing the view exists to avoid; the segmented chrome is missing
/// either way, so butting them together is the closer of the two wrong answers.
///
/// 一組相關的控制項，作為單一單位一併呈現。
///
/// 由 `VStack` 與 `HStack` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，見
/// ``Stepper``。
///
/// **這是那個分組，而不是分段控制項（segmented control）。** SwiftUI 的 `ControlGroup` 會把子項交給
/// 平台自身的分段容器：在 macOS 與 iOS 上，按鈕會失去各自的邊框，成為單一長條的一個個區段；而在
/// 工具列中，當空間不足時整組會收合成一個溢位選單。這兩件事此處都不會發生。此處就是一個間距為零的
/// `HStack`，子項維持它們原本的外觀並彼此緊貼——在按鈕會自行繪製邊框的 backend 上，這已相當接近
/// 分段的樣子；在其餘 backend 上則只是排得很緊。空間不足時也不會收合任何東西。這一點明說而不留給
/// 人自己發現：**形狀是對的、平台樣式是缺的**。``Form``、``Section`` 與 ``GroupBox`` 帶有同樣的
/// 說明，理由相同。
///
/// 間距為 `0` 是刻意設定，而非疏漏。子項彼此分開的 ``ControlGroup`` 看起來就像好幾個互不相干的
/// 控制項，而那正是這個 view 存在所要避免的唯一一件事；分段外觀無論如何都是缺的，所以把它們緊貼
/// 在一起，是兩個錯誤答案中比較接近的那一個。
public struct ControlGroup<Label: View, Content: View>: View {
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
        VStack(alignment: .leading, spacing: 4) {
            label
            HStack(spacing: 0) {
                content
            }
        }
    }
}

extension ControlGroup where Label == Text {
    /// Matches SwiftUI's `ControlGroup("Title") { … }`.
    /// 對應 SwiftUI 的 `ControlGroup("Title") { … }`。
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content(), label: Text(title))
    }
}

extension ControlGroup where Label == EmptyView {
    /// The common case, matching SwiftUI's `ControlGroup { … }`. Unlike
    /// ``GroupBox``, this is the *usual* spelling rather than the unusual one --
    /// a control group is normally identified by what it contains, not by a
    /// caption above it.
    ///
    /// 常見情形，對應 SwiftUI 的 `ControlGroup { … }`。與 ``GroupBox`` 不同，這是**慣常**的寫法而
    /// 非特例——一組控制項通常是靠它所包含的內容來辨識，而不是靠上方的一行標題。
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content(), label: EmptyView())
    }
}
