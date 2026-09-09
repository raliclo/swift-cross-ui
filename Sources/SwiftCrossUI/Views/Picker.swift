import DebugFeatures

/// A control for selecting from a set of values.
public struct Picker<Value: Equatable>: View {
    /// The options to be offered by the picker.
    private var options: [Value]
    /// A binding to the picker's selected option.
    private var value: Binding<Value?>
    /// Text shown beside the control, or nil for a picker with no label.
    ///
    /// Composed rather than given a backend protocol of its own, and unlike
    /// ``Slider`` that is a real statement rather than a hopeful one: `Picker`
    /// already has a `body`, so a label is an `HStack` around what it was
    /// already returning. `Slider` is an `ElementaryView`, whose `Content` must
    /// be `EmptyView`, and adding a label there means making the type generic
    /// and demoting its leaf -- a different job that is still open under #126.
    ///
    /// A DIVERGENCE WORTH NAMING: SwiftUI shows this label on macOS and uses it
    /// only for accessibility on iOS. This shows it everywhere, because this
    /// project has no accessibility layer at all (#123) and a label that is
    /// invisible AND unreadable is a label that does nothing. When #123 lands,
    /// revisit this rather than assuming it still reads correctly.
    ///
    /// 顯示在控制項旁的文字;nil 表示不帶標籤的 picker。
    ///
    /// 以組合實作而非另立 backend protocol,而**與 ``Slider`` 不同,這裡是一項有依據的陳述、而非
    /// 一廂情願**:`Picker` 本來就有 `body`,因此標籤只是在它原本回傳的東西外面套一個 `HStack`。
    /// `Slider` 是 `ElementaryView`,其 `Content` 必須為 `EmptyView`,在該處加標籤意味著把型別泛型化
    /// 並降級它的葉節點——那是另一件事,仍在 #126 之下待辦。
    ///
    /// **一項值得指名的分歧**:SwiftUI 在 macOS 上顯示此標籤,而在 iOS 上僅供無障礙使用。此處在所有
    /// 平台上都顯示它,因為本專案**完全沒有無障礙層**(#123),而一個既看不見、又讀不到的標籤,
    /// 是一個什麼都不做的標籤。待 #123 落地時請重新檢視此處,不要假設它仍然成立。
    private var label: String?
    /// One display string per option, or nil when the options display
    /// themselves.
    ///
    /// **This is what lets `.tag()` separate the label from the value, without
    /// touching a single backend.** `_BuiltinPickerStyle.makeView` reduces its
    /// options with `options.map { "\($0)" }` and hands the backend `[String]`
    /// -- so for `Picker(of:selection:)` the label IS the value's own
    /// description, and the two cannot differ. A tagged picker needs them to
    /// differ: `Text("Vanilla").tag(Flavour.vanilla)` shows one thing and
    /// selects another.
    ///
    /// Rather than widen the `PickerStyle` protocol -- which would land on every
    /// custom style anyone has written -- the labelled path wraps each value in
    /// ``_LabelledPickerValue``, whose `description` is the label and whose
    /// equality is the value. The existing `"\($0)"` then produces the label by
    /// itself and nothing downstream knows the difference.
    ///
    /// 每個選項一個顯示字串;若選項自己就是顯示內容則為 nil。
    ///
    /// **這正是讓 `.tag()` 把標籤與值分開、而完全不必碰任何 backend 的東西。**
    /// `_BuiltinPickerStyle.makeView` 以 `options.map { "\($0)" }` 化簡選項,交給 backend 的是
    /// `[String]` ——因此對 `Picker(of:selection:)` 而言,**標籤就是值自己的描述**,兩者不可能不同。
    /// 而帶標籤的 picker 需要它們不同:`Text("Vanilla").tag(Flavour.vanilla)` 顯示一個東西、
    /// 選取另一個。
    ///
    /// 與其放寬 `PickerStyle` 協定——那會落到任何人寫過的每一個自訂 style 上——帶標籤的路徑改為把
    /// 每個值包進 ``_LabelledPickerValue``:它的 `description` 是標籤,而它的相等性是值。
    /// 於是既有的 `"\($0)"` 自己就會產出標籤,下游沒有任何東西察覺得到差別。
    private var optionLabels: [String]?

    @Environment(\.self) var environment

    /// Creates a new picker with the given options and a binding for the
    /// selected value.
    ///
    /// - Parameters:
    ///   - options: The options to be offered by the picker.
    ///   - value: A binding to the picker's selected option.
    public init(of options: [Value], selection value: Binding<Value?>) {
        self.options = options
        self.value = value
    }

    /// Creates a picker whose selection is always one of the options.
    ///
    /// SwiftUI's `selection` is not optional, and an application that always has
    /// a chosen value should not have to unwrap one. The optional initialiser
    /// above stays, because a picker that genuinely starts with nothing chosen
    /// is a real thing this framework already supports.
    ///
    /// **A nil written back is IGNORED, not forced.** The style layer's binding
    /// is `Binding<Value?>`, so it is allowed to clear the selection -- and this
    /// caller has nowhere to put a nil. Dropping it leaves the last real choice
    /// in place, which is what a non-optional selection means. Substituting
    /// `options.first` instead would silently move the user's selection on a
    /// transient clear, and WinUI's combo box is documented in
    /// `WinUIBackend.createPicker` as briefly reporting -1 while it rebuilds its
    /// dropdown -- so that substitution would fire in practice, not in theory.
    ///
    /// 建立一個「選取值必定為選項之一」的 picker。
    ///
    /// SwiftUI 的 `selection` 並非 optional,而一個永遠都有選定值的應用程式,不該被迫去解包一個
    /// optional。上方的 optional 版建構式保留,因為「確實一開始什麼都沒選」的 picker 是本框架
    /// 早已支援的真實情況。
    ///
    /// **寫回的 nil 會被忽略,而不是被替換。** 樣式層的 binding 是 `Binding<Value?>`,因此它有權
    /// 清除選取——而此處的呼叫端無處可放 nil。**丟棄它**會讓上一個真實選擇留在原地,那正是
    /// 「非 optional 的 selection」所代表的意思。改為代入 `options.first` 則會在一次短暫的清除中
    /// **悄悄改動使用者的選擇**;而 WinUI 的 combo box 在 `WinUIBackend.createPicker` 中已載明
    /// 「重建下拉選單時會短暫回報 -1」——因此那種代入會在實務上觸發,不是理論上。
    public init(of options: [Value], selection value: Binding<Value>) {
        self.options = options
        self.value = Binding<Value?>(
            get: { value.wrappedValue },
            set: { newValue in
                guard let newValue else { return }
                value.wrappedValue = newValue
            }
        )
    }

    /// Creates a labelled picker whose selection is always one of the options.
    /// 建立一個帶標籤、且選取值必定為選項之一的 picker。
    public init(_ label: String, of options: [Value], selection value: Binding<Value>) {
        self.init(of: options, selection: value)
        self.label = label
    }

    /// Creates a labelled picker.
    /// 建立一個帶標籤的 picker。
    public init(_ label: String, of options: [Value], selection value: Binding<Value?>) {
        self.init(of: options, selection: value)
        self.label = label
    }

    /// Creates a picker from tagged views.
    ///
    /// ```swift
    /// Picker("Flavour", selection: $flavour) {
    ///     Text("Vanilla").tag(Flavour.vanilla)
    ///     Text("Chocolate").tag(Flavour.chocolate)
    /// }
    /// ```
    ///
    /// **A tag whose type does not match `Value` is REPORTED and skipped, not
    /// silently dropped.** Tags are type-erased through the walk (see
    /// ``PickerOption``), so a mismatch cannot be a compile error -- and a
    /// picker quietly missing one of its options is the worst possible
    /// outcome, because the remaining ones still work and nothing looks wrong.
    ///
    /// Only text can be tagged, and the same reason: backends take option
    /// labels as strings. ``_TaggedView/_asPickerOptions`` logs and contributes
    /// nothing for anything else.
    ///
    /// 由帶標籤的 view 建立一個 picker。
    ///
    /// **型別與 `Value` 不符的 tag 會被回報並跳過,不會靜默丟棄。** tag 在走訪過程中被型別抹除
    /// (見 ``PickerOption``),因此不符無法成為編譯錯誤——而**一個安靜地少了某個選項的 picker
    /// 是最糟的結果**,因為其餘選項照樣能用,而看起來一點問題都沒有。
    ///
    /// 只有文字能被加標籤,理由相同:backend 收的選項標籤是字串。
    /// ``_TaggedView/_asPickerOptions`` 對其他任何東西會記錄一行並且不貢獻選項。
    public init<Content: View>(
        _ label: String,
        selection value: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) {
        var values: [Value] = []
        var labels: [String] = []
        for option in content()._asPickerOptions {
            guard let typed = option.tag as? Value else {
                DebugFeatures.log(
                    "Picker: a .tag() of type \(type(of: option.tag)) does not match the "
                        + "selection type \(Value.self), so the option '\(option.label)' was "
                        + "skipped"
                )
                continue
            }
            values.append(typed)
            labels.append(option.label)
        }

        self.init(of: values, selection: value)
        self.label = label
        self.optionLabels = labels
    }

    public var body: some View {
        let control = optionLabels.map(labelledControl) ?? plainControl

        // An `if let`, so a picker with no label is EXACTLY what it was before
        // this initialiser existed -- not an HStack holding an empty Text.
        // Wrapping unconditionally would change the layout of every existing
        // picker in the project to buy a feature none of them asked for, and it
        // would do it without any call site changing.
        // 使用 `if let`,好讓**沒有標籤的 picker 與這個建構式存在之前完全相同**——而不是一個裝著空
        // `Text` 的 HStack。無條件包裝會為了一個沒有任何現有 picker 要求的功能,改變專案中每一個
        // picker 的版面,而且是在沒有任何呼叫點改動的情況下發生。
        return AnyView(
            Group {
                if let label {
                    HStack {
                        Text(label)
                        control
                    }
                } else {
                    control
                }
            }
        )
    }

    /// The control for a picker whose options display themselves.
    /// 選項自己就是顯示內容時的控制項。
    private var plainControl: AnyView {
        AnyView(
            environment.pickerStyle.makeView(
                options: options,
                selection: value,
                environment: environment
            )
        )
    }

    /// The control for a picker whose options carry their own labels.
    ///
    /// The zip is a `prefix` guard as much as a pairing: `optionLabels` is built
    /// alongside `options` in the tagged initialiser and the two are always the
    /// same length, but `zip` makes a future divergence produce fewer options
    /// rather than a crash on an index.
    ///
    /// 選項自帶標籤時的控制項。
    ///
    /// 這裡的 `zip` 既是配對、也是一道長度防護:`optionLabels` 是在帶標籤的建構式中與 `options`
    /// 一同建立的,兩者長度永遠相同;但用 `zip` 可讓未來若真的不一致時**產生較少的選項**,
    /// 而不是在某個索引上崩潰。
    private func labelledControl(_ labels: [String]) -> AnyView {
        let wrapped = zip(options, labels).map { value, label in
            _LabelledPickerValue(value: value, label: label)
        }

        // The label on the way OUT does not matter and is left empty, because
        // `_LabelledPickerValue`'s equality ignores it -- `firstIndex(of:)`
        // inside `makeView` therefore still finds the right option. Looking the
        // real label up here would work too and would be one more place for the
        // two sides to disagree.
        // **往外送的那個 label 無關緊要,故留空**,因為 `_LabelledPickerValue` 的相等性會忽略它
        // ——於是 `makeView` 內部的 `firstIndex(of:)` 仍然找得到正確的選項。在此把真正的標籤查出來
        // 同樣可行,卻會多一個「讓兩邊產生分歧」的地方。
        let wrappedSelection = Binding<_LabelledPickerValue<Value>?>(
            get: {
                value.wrappedValue.map { _LabelledPickerValue(value: $0, label: "") }
            },
            set: { newValue in
                value.wrappedValue = newValue?.value
            }
        )

        return AnyView(
            environment.pickerStyle.makeView(
                options: wrapped,
                selection: wrappedSelection,
                environment: environment
            )
        )
    }
}

/// A picker option that displays a label but compares as its value.
///
/// Exists so that `.tag()` can separate the two without a `PickerStyle`
/// protocol change -- see ``Picker/optionLabels``. `description` is what
/// `_BuiltinPickerStyle.makeView`'s `"\($0)"` picks up, and `==` deliberately
/// ignores the label so that a value looked up without one still matches.
///
/// 一個「顯示標籤、但以值比較」的 picker 選項。
///
/// 它的存在使 `.tag()` 能在不改動 `PickerStyle` 協定的前提下把兩者分開——見
/// ``Picker/optionLabels``。`description` 正是 `_BuiltinPickerStyle.makeView` 中 `"\($0)"`
/// 會取用的東西,而 `==` **刻意忽略標籤**,使一個在沒有標籤的情況下被查找的值仍然能夠相符。
struct _LabelledPickerValue<Value: Equatable>: Equatable, CustomStringConvertible {
    var value: Value
    var label: String

    var description: String { label }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}
