/// A control that increments and decrements a value.
///
/// Composed from `Button` and `Text`, so it needs nothing from any backend and
/// works on all five the moment it compiles. That is the whole reason this and
/// its neighbours were written before the protocol-level parity items: a view
/// that is only a rearrangement of existing primitives cannot be "implemented
/// on GTK but not on Android".
///
/// `testapp/P33.swift` built this shape by hand -- two buttons and a label in an
/// `HStack` -- under a comment calling `Stepper` a compile-time gap. The
/// approximation was correct; it was just in the wrong place.
///
/// 一個用來遞增與遞減數值的控制項。
///
/// 由 `Button` 與 `Text` 組合而成，因此不需要任何 backend 的支援，一旦編譯通過就在五個 backend
/// 上同時成立。這正是它與它的鄰居先於協定層級的 parity 項目被實作的全部理由：一個「只是把既有
/// 原語重新排列」的 view，不可能發生「在 GTK 上實作了、在 Android 上沒有」的情況。
///
/// `testapp/P33.swift` 曾以手工搭出這個形狀——`HStack` 裡兩顆按鈕加一個標籤——並在註解中把
/// `Stepper` 列為編譯期的缺口。那個近似做法本身是對的，只是放錯了地方。
public struct Stepper<Label: View>: View {
    /// Bound so the caller sees every change, which is what separates this from
    /// two buttons that each mutate their own copy.
    /// 使用 binding，讓呼叫端看得到每一次變動；這正是它與「兩顆各自改自己副本的按鈕」的差別。
    private let value: Binding<Int>
    private let bounds: ClosedRange<Int>?
    private let step: Int
    private let label: Label

    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int>? = nil,
        step: Int = 1,
        @ViewBuilder label: () -> Label
    ) {
        self.init(value: value, in: bounds, step: step, label: label())
    }

    /// Takes the label as a VALUE, which the convenience initialisers need.
    ///
    /// `@ViewBuilder` wraps even a single view, so `{ Text(title) }` produces
    /// `TupleView1<Text>` and cannot satisfy `Label == Text`. Routing the
    /// convenience initialisers through here instead of through the builder is
    /// what lets `Stepper("Quantity", value:)` be a `Stepper<Text>`.
    ///
    /// 以**值**的形式接收標籤，這是便利建構式所需要的。
    ///
    /// `@ViewBuilder` 連單一 view 也會包裝，因此 `{ Text(title) }` 產出的是 `TupleView1<Text>`，
    /// 無法滿足 `Label == Text`。讓便利建構式改走此處而非走 builder，正是
    /// `Stepper("Quantity", value:)` 得以成為 `Stepper<Text>` 的原因。
    private init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int>?,
        step: Int,
        label: Label
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.label = label
    }

    /// Whether a press in each direction would change anything.
    ///
    /// Checked rather than clamped-after-the-fact so a press at the limit is a
    /// no-op that LOOKS like one. Clamping silently would leave a button that
    /// depresses and does nothing, which reads as an unresponsive control.
    ///
    /// 檢查按下之後是否真的會改變什麼。
    ///
    /// 採「事前檢查」而非「事後夾限」，使位於邊界的按壓成為一個**看起來就像 no-op** 的 no-op。
    /// 靜默夾限會留下一顆「按得下去卻毫無反應」的按鈕，那讀起來像是控制項沒有回應。
    private var canDecrement: Bool {
        guard let bounds else { return true }
        return value.wrappedValue - step >= bounds.lowerBound
    }

    private var canIncrement: Bool {
        guard let bounds else { return true }
        return value.wrappedValue + step <= bounds.upperBound
    }

    public var body: some View {
        HStack(spacing: 8) {
            label
            Button("-") {
                if canDecrement { value.wrappedValue -= step }
            }
            .disabled(!canDecrement)
            Button("+") {
                if canIncrement { value.wrappedValue += step }
            }
            .disabled(!canIncrement)
        }
    }
}

extension Stepper where Label == Text {
    /// The common case, matching SwiftUI's `Stepper("Quantity", value: $n)`.
    /// 常見情形，對應 SwiftUI 的 `Stepper("Quantity", value: $n)`。
    public init(_ title: String, value: Binding<Int>, in bounds: ClosedRange<Int>? = nil, step: Int = 1) {
        self.init(value: value, in: bounds, step: step, label: Text(title))
    }
}
