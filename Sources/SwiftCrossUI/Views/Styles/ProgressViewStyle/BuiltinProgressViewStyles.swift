/// Leaves the choice to the initialiser, which is what the default has to mean.
///
/// **Not "a bar when there is a value, a spinner when there is not".** That rule
/// is nearly right and would have changed behaviour: `ProgressView(value: nil)`
/// constructs a BAR with no value -- an indeterminate linear indicator, which is
/// a real thing -- and deriving the kind from the progress would silently turn
/// it into a spinner. The initialiser knows something the value does not.
///
/// So `.automatic` overrides nothing, and every `ProgressView` written before
/// this protocol existed draws exactly what it drew before.
///
/// 把選擇交還給建構式，而那正是「預設」必須代表的意思。
///
/// **不是「有值用長條、沒值用轉圈」。** 那條規則幾乎是對的，而它會改變既有行為:
/// `ProgressView(value: nil)` 建構出來的是一根**沒有值的長條**——一個不定量的線性指示器，那是真實
/// 存在的東西——而「由 progress 推導種類」會靜默地把它變成轉圈。建構式知道一件「值本身不知道」的事。
///
/// 因此 `.automatic` 不覆寫任何東西，而每一支在本協定存在之前寫成的 `ProgressView`，畫出來的都與
/// 從前完全相同。
public struct AutomaticProgressViewStyle: ProgressViewStyle, _BuiltinProgressViewStyle {
    public nonisolated init() {}

    public func _indicator(default defaultKind: _ProgressIndicatorKind)
        -> _ProgressIndicatorKind
    {
        defaultKind
    }
}

extension ProgressViewStyle where Self == AutomaticProgressViewStyle {
    public static nonisolated var automatic: Self { Self() }
}

/// Always a bar, even with no value to show.
///
/// An indeterminate linear indicator is a real thing on every one of the five
/// platforms -- a bar that animates without reporting a fraction -- so this is
/// not a request the backends cannot honour. What it does mean is that
/// ``ProgressBarView`` receives `nil`, and how a backend animates that is the
/// backend's own answer.
///
/// 一律使用長條，即使沒有值可顯示。
///
/// 「不定量的線性指示器」在五個平台上都是真實存在的東西——一根會動、但不回報比例的長條——因此這並不是
/// 一項 backend 無法滿足的要求。它實際的意思是 ``ProgressBarView`` 會收到 `nil`，而某個 backend 如何
/// 為此製作動畫，那是該 backend 自己的答案。
public struct LinearProgressViewStyle: ProgressViewStyle, _BuiltinProgressViewStyle {
    public nonisolated init() {}

    public func _indicator(default defaultKind: _ProgressIndicatorKind)
        -> _ProgressIndicatorKind
    {
        .bar
    }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static nonisolated var linear: Self { Self() }
}

/// Always a spinner, and a value handed to it is discarded.
///
/// Discarded rather than approximated. The backends' spinners are
/// indeterminate -- ``BackendFeatures/ProgressSpinners`` has no value parameter
/// -- so a determinate circular indicator is not something any of the five can
/// draw today. Naming that here rather than quietly rendering a spinner beside
/// a number that means nothing.
///
/// 一律使用轉圈，而傳給它的值會被丟棄。
///
/// 是「丟棄」而不是「近似」。各 backend 的轉圈是不定量的——``BackendFeatures/ProgressSpinners``
/// 沒有值的參數——因此「定量的環形指示器」是五者今天都畫不出來的東西。此處把這件事講明，而不是默默
/// 畫出一個轉圈、旁邊擺一個沒有意義的數字。
public struct CircularProgressViewStyle: ProgressViewStyle, _BuiltinProgressViewStyle {
    public nonisolated init() {}

    public func _indicator(default defaultKind: _ProgressIndicatorKind)
        -> _ProgressIndicatorKind
    {
        .spinner
    }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static nonisolated var circular: Self { Self() }
}
