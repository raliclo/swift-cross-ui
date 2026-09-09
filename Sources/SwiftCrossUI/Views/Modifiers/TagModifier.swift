import DebugFeatures

/// One option offered to a ``Picker`` by a tagged view.
///
/// The tag is type-erased, and that is not laziness -- it is forced. A stored
/// protocol requirement (``View/_asPickerOptions``) cannot be generic over the
/// value the caller happens to be selecting, so the walk has to carry `Any` and
/// the cast has to happen at the ``Picker``, which is the one place that knows
/// what `Value` is. SwiftUI erases tags internally for the same reason.
///
/// The label is a `String` rather than a view because that is what the backends
/// take: `_BuiltinPickerStyle.makeView` reduces its options with
/// `options.map { "\($0)" }` and hands the backend `[String]`. A picker whose
/// options were arbitrary views would need a different backend protocol
/// entirely, so tagging a non-text view is honestly not supported rather than
/// quietly half-supported -- see ``_TaggedView/_asPickerOptions``.
///
/// 由一個帶標籤的 view 提供給 ``Picker`` 的單一選項。
///
/// **tag 被型別抹除,而那不是偷懶——是被迫的。** 一個儲存式協定需求
/// (``View/_asPickerOptions``)無法泛型於「呼叫端恰好正在選取的那個值」,因此走訪必須攜帶
/// `Any`,而轉型必須發生在 ``Picker`` ——唯一知道 `Value` 是什麼的地方。SwiftUI 內部出於相同
/// 理由也對 tag 做型別抹除。
///
/// label 是 `String` 而非 view,因為那正是各 backend 所接受的東西:
/// `_BuiltinPickerStyle.makeView` 以 `options.map { "\($0)" }` 化簡它的選項,交給 backend 的是
/// `[String]`。一個選項為任意 view 的 picker 會需要**完全不同的** backend 協定,因此為非文字
/// view 加標籤是**老實地不支援**,而不是安靜地半支援——見 ``_TaggedView/_asPickerOptions``。
public struct PickerOption {
    /// The value this option selects, type-erased. See the type's documentation.
    /// 此選項所選取的值,已型別抹除。見本型別的文件。
    public var tag: Any
    /// The text shown for this option.
    /// 此選項所顯示的文字。
    public var label: String

    public init(tag: Any, label: String) {
        self.tag = tag
        self.label = label
    }
}

extension View {
    /// Associates a value with this view, for use as a ``Picker`` option.
    ///
    /// ```swift
    /// Picker("Flavour", selection: $flavour) {
    ///     Text("Vanilla").tag(Flavour.vanilla)
    ///     Text("Chocolate").tag(Flavour.chocolate)
    /// }
    /// ```
    ///
    /// The tag's type must match the picker's selection, and a mismatch is
    /// reported rather than silently dropping the option -- see
    /// ``Picker/init(_:selection:content:)``.
    ///
    /// 將一個值與此 view 關聯,以作為 ``Picker`` 的選項使用。
    ///
    /// tag 的型別必須與 picker 的 selection 相符,而**不相符會被回報,不會靜默丟棄該選項**
    /// ——見 ``Picker/init(_:selection:content:)``。
    public func tag<Value>(_ tag: Value) -> _TaggedView<Self> {
        _TaggedView(content: self, tag: tag)
    }
}

/// A view carrying a ``Picker`` tag.
///
/// Underscored because it is a return type callers name only by accident, the
/// same convention `_TaggedView`'s neighbours in this directory follow.
///
/// 一個攜帶 ``Picker`` 標籤的 view。
///
/// 加底線前綴,因為它是呼叫端只會偶然指名的回傳型別,與本目錄中鄰近型別遵循相同的慣例。
public struct _TaggedView<Content: View>: View {
    /// STORED, not computed, and that is not a style choice.
    ///
    /// `View.body` is `@ViewBuilder`, so `var body: Content { content }` is
    /// wrapped and the compiler rejects it with
    /// *"cannot convert return expression of type 'TupleView1<Content>' to
    /// return type 'Content'"* -- an error about a type the source never
    /// mentions. `RowView` in Views/Table.swift stores its body for the same
    /// reason.
    ///
    /// **改用 stored 而非 computed,而這不是風格選擇。**
    ///
    /// `View.body` 帶有 `@ViewBuilder`,因此 `var body: Content { content }` 會被包裝起來,
    /// 而編譯器以*「cannot convert return expression of type 'TupleView1<Content>' to return
    /// type 'Content'」*拒絕它——一個關於「原始碼從未提及之型別」的錯誤。
    /// Views/Table.swift 中的 `RowView` 出於相同理由也把它的 body 存起來。
    public var body: Content
    var tag: Any

    init(content: Content, tag: Any) {
        self.body = content
        self.tag = tag
    }

    /// The one option this view contributes, if its content is text.
    ///
    /// **A non-text content contributes NOTHING, and says so.** The backends
    /// take `[String]`, so there is no representation for `Image().tag(x)` to
    /// become -- and returning the tag's `String(describing:)` instead would put
    /// a debug description on screen where a caller expected a picture, which is
    /// worse than the option being absent. `Button._asMenuItems` reaches the
    /// same wall from the other side and leaves the same kind of note
    /// (Views/Button.swift:421).
    ///
    /// Two shapes are unwrapped because `@ViewBuilder` wraps a lone view: a bare
    /// `Text` and a `TupleView1<Text>`. Anything else is the unsupported case.
    ///
    /// 若其內容是文字,則貢獻這一個選項。
    ///
    /// **非文字的內容什麼都不貢獻,而且會說出來。** 各 backend 收的是 `[String]`,因此
    /// `Image().tag(x)` 沒有任何可以變成的表示形式——而改為回傳該 tag 的 `String(describing:)`
    /// 會在呼叫端期待一張圖的位置放上一段除錯描述,那**比該選項不存在更糟**。
    /// `Button._asMenuItems` 從另一側撞上同一面牆,並留下同一類註記(Views/Button.swift:421)。
    ///
    /// 此處解開兩種形狀,因為 `@ViewBuilder` 會包裝單一 view:裸的 `Text`,以及
    /// `TupleView1<Text>`。其餘都是不支援的情況。
    public var _asPickerOptions: [PickerOption] {
        if let text = body as? Text {
            return [PickerOption(tag: tag, label: text.string)]
        } else if let tuple = body as? TupleView1<Text> {
            return [PickerOption(tag: tag, label: tuple.view0.string)]
        } else {
            DebugFeatures.log(
                "Picker: .tag() on a \(Content.self) contributes no option -- backends take "
                    + "option labels as strings, so only Text can supply one"
            )
            return []
        }
    }
}
