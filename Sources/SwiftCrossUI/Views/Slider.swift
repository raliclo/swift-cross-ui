/// The track and thumb, without a label.
///
/// This is what ``Slider`` used to be, renamed and made internal rather than
/// rewritten -- every line below the declaration, including the `step:`
/// reasoning and the struck-through note in ``commit``, is untouched.
///
/// WHY THE SPLIT. `ElementaryView` requires `Content == EmptyView`
/// (Views/ElementaryView.swift:6), so a view that conforms to it cannot have a
/// label: it has no body to put one beside. A label therefore has to live one
/// level up, which is why ``Slider`` is now a generic shell over this.
///
/// This is exactly the difference that made ``Picker``'s label cheap and this
/// one not. `Picker` already had a `body`, so its label was an `HStack` around
/// what it already returned; `Slider` had no body at all. Both were recorded as
/// "pure view layer" in #126's original note and only one of them was.
///
/// 軌道與把手,不含標籤。
///
/// 這就是原本的 ``Slider``,經**改名並降為 internal**,而非重寫——宣告以下的每一行,包含 `step:`
/// 的推論與 ``commit`` 中那段被劃掉的註記,都原封不動。
///
/// **為何要拆。** `ElementaryView` 要求 `Content == EmptyView`
/// (Views/ElementaryView.swift:6),因此符合它的 view **不可能有標籤**:它沒有 body 可以把標籤
/// 放在旁邊。標籤因此必須住在上一層,那正是 ``Slider`` 現在成為本型別泛型外殼的原因。
///
/// 這正是「讓 ``Picker`` 的標籤便宜、而讓這個不便宜」的那個差別。`Picker` 本來就有 `body`,
/// 所以它的標籤只是在它原本回傳的東西外套一個 `HStack`;`Slider` 根本沒有 body。
/// 兩者在 #126 最初的記錄中都被寫成「純 view 層」,而**只有其中一個是**。
struct SliderControl: ElementaryView, View {
    /// The ideal width of a Slider.
    private static let idealWidth: Double = 100

    /// A binding to the current value.
    private var value: Binding<Double>?
    /// The slider's selectable range of values.
    private var range: ClosedRange<Double>
    /// The number of decimal places used when displaying the value.
    private var decimalPlaces: Int
    /// The distance between selectable values, or nil for a continuous slider.
    ///
    /// **Not a backend parameter, and that is a measurement rather than a
    /// preference.** The five shipped backends disagree about whether a slider
    /// can step at all: `GtkScale` has increments and `round-digits`,
    /// `WinUI.Slider` has `stepFrequency`, `NSSlider` needs tick marks plus
    /// `allowsTickMarkValuesOnly`, Android's is integer-stepped -- and `UISlider`
    /// has **no step API whatsoever**, so its value has to be snapped in the
    /// change handler regardless. Since one platform forces snapping in shared
    /// code, doing it there for all five is the only way every backend behaves
    /// the same, which is what the `step:` in an application's source is asking
    /// for.
    ///
    /// The thumb still snaps visually, and not by accident: ``commit`` pushes
    /// `value.wrappedValue` back into the widget with `setValue(ofSlider:to:)`,
    /// so once the binding holds a snapped value the widget is told to show it.
    /// A drag between steps therefore ends with the thumb on a step, on every
    /// backend, with no protocol method added to any of them.
    ///
    /// **An INITIAL value is left alone.** `step:` governs the values the user
    /// produces; the value an application starts with is its own. See the note
    /// in ``commit`` for the run that settled that, and for what snapping it
    /// there actually produced -- a printed value and a thumb that disagreed.
    ///
    /// **初始值不予變動。** `step:` 管的是**使用者所產生**的值;應用程式起始時所持有的值屬於它自己。
    /// 那次定案的執行,以及在該處吸附實際造成了什麼——一個印出的數值與一個把手互相矛盾——記於
    /// ``commit`` 中的註解。
    ///
    /// 可選值之間的間距;nil 代表連續滑桿。
    ///
    /// **不是一個 backend 參數,而這是量測的結果,不是偏好。** 五個已發布的 backend 對「滑桿究竟能不能
    /// 分段」意見分歧:`GtkScale` 有 increments 與 `round-digits`、`WinUI.Slider` 有 `stepFrequency`、
    /// `NSSlider` 需要刻度加上 `allowsTickMarkValuesOnly`、Android 的本來就是整數步進——而 `UISlider`
    /// **根本沒有任何 step API**,因此無論如何它的值都得在變更處理常式中吸附。既然有一個平台強迫我們
    /// 在共用程式碼中吸附,那麼為五個平台都在該處吸附,就是讓每個 backend 行為一致的唯一辦法——而那
    /// 正是應用程式原始碼裡那個 `step:` 所要求的東西。
    ///
    /// 滑桿的把手仍然會在視覺上吸附,而且不是碰巧:``commit`` 會以 `setValue(ofSlider:to:)` 把
    /// `value.wrappedValue` 推回 widget,因此一旦 binding 持有吸附後的值,widget 就會被告知顯示它。
    /// 於是一次落在兩步之間的拖曳,最終會讓把手停在某一步上——在每一個 backend 上皆然,且不需要為
    /// 任何一個 backend 新增協定方法。
    private var step: Double?

    /// `value` rounded to the nearest step, clamped to the range.
    ///
    /// Clamped last, and it matters: a range whose length is not a whole number
    /// of steps -- `0...1` by `0.3` -- has its top step at 0.9, and rounding a
    /// drag to the far end gives 1.2. Without the clamp the binding would take a
    /// value outside the range it was given, which nothing downstream checks.
    ///
    /// A non-positive step is treated as no step rather than trapped on. It
    /// would divide by zero or loop, and a slider is not worth crashing an
    /// application over; the value simply stays continuous.
    ///
    /// 將 `value` 四捨五入至最近的一步,並夾在範圍內。
    ///
    /// **夾限放在最後,而這是有意義的**:一個長度並非整數步的範圍——例如以 `0.3` 為步進的 `0...1`
    /// ——其最高的一步在 0.9,而把拖到底的值四捨五入會得到 1.2。少了夾限,binding 就會拿到一個
    /// 超出它被賦予之範圍的值,而下游沒有任何東西會檢查這件事。
    ///
    /// 非正數的步進被視為「沒有步進」,而不是讓它觸發 trap。那會除以零或造成迴圈,而一個滑桿不值得
    /// 讓整個應用程式崩潰;此時數值單純維持連續。
    private func snapped(_ value: Double) -> Double {
        guard let step, step > 0 else { return value }
        let steps = ((value - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + steps * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    @available(*, deprecated, renamed: "init(value:in:)")
    public init<T: BinaryInteger>(_ value: Binding<T>? = nil, minimum: T, maximum: T) {
        self.init(value: value, in: minimum...maximum)
    }

    @available(*, deprecated, renamed: "init(value:in:)")
    public init<T: BinaryFloatingPoint>(_ value: Binding<T>? = nil, minimum: T, maximum: T) {
        self.init(value: value, in: minimum...maximum)
    }

    /// Creates a slider to select a value in a range, in fixed increments.
    ///
    /// - Parameters:
    ///   - value: A binding to the current value.
    ///   - range: The slider's selectable range of values.
    ///   - step: The distance between selectable values.
    ///
    /// 建立一個在指定範圍內、以固定增量選值的滑桿。
    public init<T: BinaryInteger>(value: Binding<T>? = nil, in range: ClosedRange<T>, step: T) {
        self.init(value: value, in: range)
        self.step = Double(step)
    }

    /// Creates a slider to select a value in a range, in fixed increments.
    ///
    /// - Parameters:
    ///   - value: A binding to the current value.
    ///   - range: The slider's range of values.
    ///   - step: The distance between selectable values.
    ///
    /// 建立一個在指定範圍內、以固定增量選值的滑桿。
    public init<T: BinaryFloatingPoint>(
        value: Binding<T>? = nil, in range: ClosedRange<T>, step: T
    ) {
        self.init(value: value, in: range)
        self.step = Double(step)
    }

    /// Creates a slider to select a value in a range.
    ///
    /// - Parameters:
    ///   - value: A binding to the current value.
    ///   - range: The slider's selectable range of values.
    public init<T: BinaryInteger>(value: Binding<T>? = nil, in range: ClosedRange<T>) {
        if let value {
            self.value = Binding<Double>(
                get: {
                    return Double(value.wrappedValue)
                },
                set: { newValue in
                    value.wrappedValue = T(newValue.rounded())
                }
            )
        }
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        decimalPlaces = 0
    }

    /// Creates a slider to select a value in a range.
    ///
    /// - Parameters:
    ///   - value: A binding to the current value.
    ///   - range: The slider's range of values.
    public init<T: BinaryFloatingPoint>(value: Binding<T>? = nil, in range: ClosedRange<T>) {
        if let value {
            self.value = Binding<Double>(
                get: {
                    return Double(value.wrappedValue)
                },
                set: { newValue in
                    value.wrappedValue = T(newValue)
                }
            )
        }
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        decimalPlaces = 2
    }

    func asWidget<Backend: BaseAppBackend>(backend: Backend) -> Backend.Widget {
        return backend.createSlider()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // TODO: Don't rely on naturalSize for minimum size so that we can get Slider sizes without
        //   relying on the widget.
        let naturalSize = backend.naturalSize(of: widget)

        let size = ViewSize(
            max(Double(naturalSize.x), proposedSize.width ?? Self.idealWidth),
            Double(naturalSize.y)
        )

        // TODO: Allow backends to specify their own ideal slider widths.
        return ViewLayoutResult.leafView(size: size)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.updateSlider(
            widget,
            minimum: range.lowerBound,
            maximum: range.upperBound,
            decimalPlaces: decimalPlaces,
            environment: environment
        ) { newValue in
            // Snapped BEFORE the comparison, not after. Comparing the raw value
            // and snapping on the way in would write on every pixel of a drag,
            // since the raw value differs each time while the snapped one does
            // not -- so a stepped slider would fire its binding as often as a
            // continuous one and every `onChange` downstream would see the
            // repeats.
            // **先吸附,再比較**,而不是反過來。若拿原始值比較、在寫入時才吸附,拖曳過程中的每一個
            // 像素都會觸發寫入——因為原始值每次都不同,而吸附後的值不會——於是一個分段滑桿會與連續
            // 滑桿一樣頻繁地觸發它的 binding,下游每一個 `onChange` 都會看到那些重複。
            let newValue = snapped(newValue)
            if let value, value.wrappedValue != newValue {
                value.wrappedValue = newValue
            }
        }

        // NOT snapped, and the struck-through reasoning below is kept because it
        // was written, built, run, and refuted by the picture.
        //
        // ~~`setValue(ofSlider:to: snapped(value))`, so a slider created at a
        // value the step does not land on shows its thumb on a step rather than
        // between two.~~ Measured 2026-09-10 with P21, `in: 0...1, step: 0.25`
        // and an initial 0.3: the on-screen label read **0.30**. Of course it
        // did -- the `Text` reads the state, and snapping here only tells the
        // WIDGET a different number. The result is not "the step was applied on
        // launch"; it is the thumb and the printed value disagreeing, which is
        // worse than either of the things it was choosing between.
        //
        // So `step:` governs the values the USER produces, and an initial value
        // is the application's own. Rewriting a caller's binding from inside a
        // layout commit is a side effect at render time, and this framework has
        // no moment at which that is safe. The first drag snaps it; until then
        // the number and the thumb agree, which is the property that actually
        // matters.
        //
        // **不吸附**;下方被劃掉的推論予以保留,因為它曾被寫下、建置、執行,然後被那張圖推翻。
        //
        // ~~使用 `setValue(ofSlider:to: snapped(value))`,好讓初始值不落在步進上的滑桿,把手停在
        // 某一步上而非兩步之間。~~ 2026-09-10 以 P21 實測(`in: 0...1, step: 0.25`,初始值 0.3):
        // 畫面上的標籤讀作 **0.30**。這是當然的——`Text` 讀的是 state,而在此吸附只是告訴 **widget**
        // 一個不同的數字。其結果並不是「step 在啟動時就生效了」,而是**把手與印出的數值互相矛盾**,
        // 那比它原本要在兩者間做的選擇都更糟。
        //
        // 因此 `step:` 管的是**使用者所產生**的值,而初始值屬於應用程式自己。從一次 layout commit
        // 內部改寫呼叫端的 binding,是發生在算繪期的副作用,而本框架沒有任何一個「那樣做是安全的」
        // 時刻。第一次拖曳就會吸附它;在那之前,數字與把手是一致的——而那才是真正重要的性質。
        if let value = value?.wrappedValue {
            backend.setValue(ofSlider: widget, to: value)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }
}

/// A control for selecting a value from a bounded range of numerical values.
///
/// Generic over its label, the way SwiftUI's is, so that
/// `Slider(value:in:)` and `Slider("Speed", value:in:)` are the same type. The
/// label-less initialisers are constrained to `Label == EmptyView`, which is
/// what keeps every existing call site compiling unchanged -- Swift has no
/// default generic arguments, and a constrained extension is how SwiftUI solves
/// the same problem.
///
/// The track itself is ``SliderControl``; see its documentation for why the
/// split was necessary rather than tidy.
///
/// 用於在有界數值範圍中選值的控制項。
///
/// 與 SwiftUI 的一樣**泛型於它的標籤**,使 `Slider(value:in:)` 與 `Slider("Speed", value:in:)`
/// 是同一個型別。不帶標籤的建構式被限制在 `Label == EmptyView`,那正是讓**每一個現有呼叫點原封
/// 不動仍能編譯**的關鍵——Swift 沒有預設泛型引數,而以受限 extension 解決同一個問題,正是
/// SwiftUI 的做法。
///
/// 軌道本身是 ``SliderControl``;至於這次拆分為何是**必要**而非只求整齊,見該型別的文件。
public struct Slider<Label: View>: View {
    private var control: SliderControl
    private var label: Label
    /// Whether a label was supplied.
    ///
    /// A separate flag rather than `Label.self == EmptyView.self`, and rather
    /// than always wrapping in an `HStack`. Wrapping unconditionally would
    /// change the layout of every slider already in the project to buy a
    /// feature none of them asked for, without a single call site changing --
    /// the same trap ``Picker``'s label documents and avoids the same way.
    ///
    /// 是否提供了標籤。
    ///
    /// 使用獨立旗標,而非 `Label.self == EmptyView.self`,也非「總是包進 `HStack`」。無條件包裝會
    /// 在沒有任何呼叫點改動的情況下,為了一個沒有任何現有滑桿要求的功能,改變專案中每一個滑桿的
    /// 版面——那正是 ``Picker`` 的標籤所記載、並以相同方式避開的陷阱。
    private var hasLabel: Bool

    public var body: some View {
        Group {
            if hasLabel {
                HStack {
                    label
                    control
                }
            } else {
                control
            }
        }
    }
}

extension Slider where Label == EmptyView {
    @available(*, deprecated, renamed: "init(value:in:)")
    public init<T: BinaryInteger>(_ value: Binding<T>? = nil, minimum: T, maximum: T) {
        self.init(value: value, in: minimum...maximum)
    }

    @available(*, deprecated, renamed: "init(value:in:)")
    public init<T: BinaryFloatingPoint>(_ value: Binding<T>? = nil, minimum: T, maximum: T) {
        self.init(value: value, in: minimum...maximum)
    }

    /// Creates a slider to select a value in a range.
    /// 建立一個在指定範圍內選值的滑桿。
    public init<T: BinaryInteger>(value: Binding<T>? = nil, in range: ClosedRange<T>) {
        self.init(control: SliderControl(value: value, in: range))
    }

    /// Creates a slider to select a value in a range.
    /// 建立一個在指定範圍內選值的滑桿。
    public init<T: BinaryFloatingPoint>(value: Binding<T>? = nil, in range: ClosedRange<T>) {
        self.init(control: SliderControl(value: value, in: range))
    }

    /// Creates a slider to select a value in a range, in fixed increments.
    /// 建立一個在指定範圍內、以固定增量選值的滑桿。
    public init<T: BinaryInteger>(value: Binding<T>? = nil, in range: ClosedRange<T>, step: T) {
        self.init(control: SliderControl(value: value, in: range, step: step))
    }

    /// Creates a slider to select a value in a range, in fixed increments.
    /// 建立一個在指定範圍內、以固定增量選值的滑桿。
    public init<T: BinaryFloatingPoint>(
        value: Binding<T>? = nil, in range: ClosedRange<T>, step: T
    ) {
        self.init(control: SliderControl(value: value, in: range, step: step))
    }

    /// The one place `hasLabel` is set false, so the flag cannot drift from the
    /// generic constraint that justifies it.
    /// `hasLabel` 唯一被設為 false 的地方,使該旗標不可能與「為它提供正當性的那個泛型約束」脫節。
    private init(control: SliderControl) {
        self.control = control
        self.label = EmptyView()
        self.hasLabel = false
    }
}

extension Slider where Label == Text {
    /// Creates a labelled slider to select a value in a range.
    /// 建立一個帶標籤、在指定範圍內選值的滑桿。
    public init<T: BinaryInteger>(
        _ label: String, value: Binding<T>? = nil, in range: ClosedRange<T>
    ) {
        self.init(label, control: SliderControl(value: value, in: range))
    }

    /// Creates a labelled slider to select a value in a range.
    /// 建立一個帶標籤、在指定範圍內選值的滑桿。
    public init<T: BinaryFloatingPoint>(
        _ label: String, value: Binding<T>? = nil, in range: ClosedRange<T>
    ) {
        self.init(label, control: SliderControl(value: value, in: range))
    }

    /// Creates a labelled slider with fixed increments.
    /// 建立一個帶標籤、以固定增量選值的滑桿。
    public init<T: BinaryInteger>(
        _ label: String, value: Binding<T>? = nil, in range: ClosedRange<T>, step: T
    ) {
        self.init(label, control: SliderControl(value: value, in: range, step: step))
    }

    /// Creates a labelled slider with fixed increments.
    /// 建立一個帶標籤、以固定增量選值的滑桿。
    public init<T: BinaryFloatingPoint>(
        _ label: String, value: Binding<T>? = nil, in range: ClosedRange<T>, step: T
    ) {
        self.init(label, control: SliderControl(value: value, in: range, step: step))
    }

    private init(_ label: String, control: SliderControl) {
        self.control = control
        self.label = Text(label)
        self.hasLabel = true
    }
}
