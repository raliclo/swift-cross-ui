/// A value shown against the range it lies in.
///
/// Composed from `VStack`, `HStack` and ``ProgressView``'s bar, so it needs
/// nothing from any backend. See ``Stepper`` for why this batch was chosen.
///
/// **Linear only.** SwiftUI also has circular and accessory styles, which are
/// drawn shapes rather than arrangements of existing views; those belong with
/// `GaugeStyle` and are not claimed here. What is present is SwiftUI's
/// `.automatic` gauge on a desktop, which is the linear one.
///
/// 一個相對於其所在範圍呈現的數值。
///
/// 由 `VStack`、`HStack` 與 ``ProgressView`` 的長條組合而成，不需要任何 backend 支援。本批工作
/// 為何如此挑選，見 ``Stepper``。
///
/// **僅有線性樣式。** SwiftUI 另有圓形與 accessory 樣式，那些是繪製出來的形狀，而非既有 view 的
/// 排列；它們屬於 `GaugeStyle` 的範疇，此處不宣稱擁有。此處提供的是桌面上 SwiftUI 的 `.automatic`
/// gauge，也就是線性那一種。
public struct Gauge<Label: View, CurrentValueLabel: View>: View {
    private let value: Double
    private let bounds: ClosedRange<Double>
    private let label: Label
    private let currentValueLabel: CurrentValueLabel

    public init<Value: BinaryFloatingPoint>(
        value: Value,
        in bounds: ClosedRange<Value> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.init(
            value: Double(value),
            in: Double(bounds.lowerBound)...Double(bounds.upperBound),
            label: label(),
            currentValueLabel: currentValueLabel()
        )
    }

    /// Takes both views as VALUES. See ``Stepper``'s equivalent for why the
    /// convenience initialisers cannot go through the `@ViewBuilder` form.
    /// 以**值**的形式接收兩個 view。便利建構式為何不能走 `@ViewBuilder` 那一版，見 ``Stepper``
    /// 中的對應說明。
    private init(
        value: Double,
        in bounds: ClosedRange<Double>,
        label: Label,
        currentValueLabel: CurrentValueLabel
    ) {
        self.value = value
        self.bounds = bounds
        self.label = label
        self.currentValueLabel = currentValueLabel
    }

    /// The value as a 0...1 fraction of the range.
    ///
    /// The zero-width guard is the whole reason this is a computed property
    /// rather than an expression in `body`. `Gauge(value: 5, in: 5...5)` is legal
    /// -- a `ClosedRange` may be a single point -- and dividing by that span
    /// gives NaN, which the bar would then draw as an arbitrary width with no
    /// error anywhere. A collapsed range means "there is nowhere to be but the
    /// end", so it reports 1.
    ///
    /// 該數值在範圍內所佔的 0...1 比例。
    ///
    /// 那個「寬度為零」的防護，正是此處寫成計算屬性而非直接寫在 `body` 裡的全部理由。
    /// `Gauge(value: 5, in: 5...5)` 是合法的——`ClosedRange` 允許只有一個點——而除以那個跨距
    /// 會得到 NaN，長條接著就會把它畫成某個任意寬度，且沿途不會有任何錯誤。範圍塌縮代表「除了終點
    /// 之外無處可去」，因此回報 1。
    private var fraction: Double {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 1 }
        return min(max((value - bounds.lowerBound) / span, 0), 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            label
            ProgressView(value: fraction)
            currentValueLabel
        }
    }
}

extension Gauge where CurrentValueLabel == EmptyView {
    public init<Value: BinaryFloatingPoint>(
        value: Value,
        in bounds: ClosedRange<Value> = 0...1,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            value: Double(value),
            in: Double(bounds.lowerBound)...Double(bounds.upperBound),
            label: label(),
            currentValueLabel: EmptyView()
        )
    }
}

extension Gauge where Label == Text, CurrentValueLabel == EmptyView {
    /// The common case, matching SwiftUI's `Gauge(value:in:) { Text(…) }`
    /// written with a string.
    /// 常見情形，對應 SwiftUI 的 `Gauge(value:in:) { Text(…) }` 以字串書寫的版本。
    public init<Value: BinaryFloatingPoint>(
        _ title: String,
        value: Value,
        in bounds: ClosedRange<Value> = 0...1
    ) {
        self.init(
            value: Double(value),
            in: Double(bounds.lowerBound)...Double(bounds.upperBound),
            label: Text(title),
            currentValueLabel: EmptyView()
        )
    }
}
