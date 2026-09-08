/// How a ``ProgressView`` presents its progress.
///
/// Shaped like ``ToggleStyle`` rather than like ``ButtonStyle``, and the two
/// shapes in this tree are not interchangeable: `ButtonStyle` is a concrete
/// value naming three appearances a backend already knows how to draw, while a
/// style protocol lets an application supply its own view. SwiftUI's
/// `ProgressViewStyle` is the second kind, so this is too.
///
/// **What a backend gets from this is a choice between two widgets it already
/// has, not a new requirement.** Every backend implements
/// ``BackendFeatures/ProgressSpinners`` and ``BackendFeatures/ProgressBars``
/// already -- ``ProgressView`` picks between them from its initialiser today,
/// and a style overrides that pick. So this adds no conformance anywhere and
/// cannot leave a backend behind.
///
/// ``ProgressView`` 如何呈現它的進度。
///
/// 形狀比照 ``ToggleStyle`` 而非 ``ButtonStyle``,而這棵樹裡的這兩種形狀並不可互換:`ButtonStyle`
/// 是一個具體的值，指名三種 backend 本來就知道怎麼畫的外觀;而樣式**協定**則讓應用程式能提供自己的
/// view。SwiftUI 的 `ProgressViewStyle` 屬於後者，因此此處亦然。
///
/// **backend 從這裡得到的，是「在它已經擁有的兩個 widget 之間做選擇」，而不是一項新的需求。**
/// 每一個 backend 都已實作 ``BackendFeatures/ProgressSpinners`` 與 ``BackendFeatures/ProgressBars``
/// ——``ProgressView`` 今天就是在它的建構式中於兩者之間挑選的，而樣式覆寫的正是那個選擇。因此這裡
/// 不會為任何地方新增 conformance，也就不可能落下任何一個 backend。
@MainActor
public protocol ProgressViewStyle: Sendable {
    associatedtype Body: View

    /// Builds the progress indicator itself. The label is not passed: a
    /// ``ProgressView`` draws its own label beside whatever this returns, so a
    /// style that also drew one would draw it twice.
    /// 建構進度指示器本身。此處不傳入 label:``ProgressView`` 會在此函式所回傳之物的旁邊自行繪製
    /// 它的 label，因此若樣式也畫一個，就會畫兩次。
    func makeView(
        progress: Double?,
        environment: EnvironmentValues
    ) -> Body
}

/// The styles that resolve to a widget the backend already has.
///
/// Separate from ``ProgressViewStyle`` for the reason ``_BuiltinToggleStyle``
/// is separate: a built-in style does not build a view tree, it names one of
/// the backend's own controls, and the two cannot share an implementation
/// without one of them pretending.
///
/// 那些會解析為「backend 已經擁有之 widget」的樣式。
///
/// 之所以與 ``ProgressViewStyle`` 分開，理由與 ``_BuiltinToggleStyle`` 分開的理由相同:內建樣式
/// 並不建構 view 樹，它指名的是 backend 自身的某個控制項;若兩者共用實作，其中一方就必須假裝。
public protocol _BuiltinProgressViewStyle {
    /// Which of the two indicators this style means, given the progress it was
    /// handed.
    ///
    /// `defaultKind` is what the ``ProgressView``'s initialiser chose, and
    /// ``ProgressViewStyle/automatic`` returns it unchanged. Passing it rather
    /// than deriving the answer from the progress value is deliberate: those
    /// two are not the same, because `ProgressView(value: nil)` is a bar with
    /// no value and deriving would make it a spinner.
    ///
    /// `defaultKind` 是該 ``ProgressView`` 的建構式所做的選擇，而
    /// ``ProgressViewStyle/automatic`` 原樣回傳它。傳入它、而不是由 progress 值推導答案，是刻意的:
    /// 兩者並不相同，因為 `ProgressView(value: nil)` 是一根沒有值的長條，而推導會把它變成轉圈。
    @MainActor
    func _indicator(default defaultKind: _ProgressIndicatorKind) -> _ProgressIndicatorKind
}

public enum _ProgressIndicatorKind: Sendable {
    case spinner
    case bar
}

extension ProgressViewStyle where Self: _BuiltinProgressViewStyle {
    public func makeView(
        progress: Double?,
        environment: EnvironmentValues
    ) -> _BuiltinProgressViewImplementation {
        _BuiltinProgressViewImplementation(
            kind: _indicator(default: environment.progressViewDefaultKind),
            progress: progress,
            isSpinnerResizable: environment.progressSpinnerIsResizable
        )
    }
}

/// Draws whichever of the backend's two indicators the style resolved to.
/// 繪製樣式所解析出的那一個 backend 指示器。
public struct _BuiltinProgressViewImplementation: View {
    var kind: _ProgressIndicatorKind
    var progress: Double?
    var isSpinnerResizable: Bool

    public var body: some View {
        switch kind {
            case .spinner:
                ProgressSpinnerView(isResizable: isSpinnerResizable)
            case .bar:
                ProgressBarView(value: progress)
        }
    }
}
