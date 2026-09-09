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

    public var body: some View {
        let control = AnyView(
            environment.pickerStyle.makeView(
                options: options,
                selection: value,
                environment: environment
            )
        )

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
}
