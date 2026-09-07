/// A type that specifies the appearance of all labels within a view hierarchy.
///
/// Shaped after ``PickerStyle``, which is shaped after SwiftUI. The fifth style
/// to take that shape, and the first that touches no backend at all: a label
/// style rearranges two views the caller already handed to ``Label``, so there
/// is nothing to ask a backend for and nothing it could refuse.
///
/// **That is why two of ``PickerStyle``'s members are absent here.** There is no
/// `isSupported(backend:)`, because every conformer -- built-in or not -- draws
/// itself out of ordinary views, so the answer could only ever be `true`;
/// `_BuiltinToggleStyle` records what a query that can only return `true` costs.
/// And there is no `_BuiltinLabelStyle` companion protocol, because that protocol
/// exists elsewhere to translate a style into a backend's own vocabulary
/// (`_asBackendPickerStyle`, `_asBackendListStyle`) and there is no such
/// vocabulary for labels. The four built-in styles are ordinary conformers with
/// no privileges.
///
/// The requirement is SwiftUI's `makeBody(configuration:)` rather than this
/// project's usual `makeView(...)`: ``LabelStyleConfiguration`` already carries
/// everything a label style needs, so there is no argument list to invent and no
/// reason to depart from the name an author will already know. ``PickerStyle``
/// and ``DatePickerStyle`` differ because their arguments (`options`,
/// `selection`, `range`, `components`) have no configuration type here.
///
/// 用於指定某個 view 階層中所有 label 外觀的型別。
///
/// 形狀比照 ``PickerStyle``，而後者比照 SwiftUI。這是第五個採用該形狀的樣式，也是第一個完全不觸及
/// backend 的：label style 所做的，只是把呼叫端已經交給 ``Label`` 的兩個 view 重新排列，因此沒有
/// 東西需要向 backend 索取，backend 也沒有東西可以拒絕。
///
/// **這正是 ``PickerStyle`` 的兩個成員在此缺席的原因。** 此處沒有 `isSupported(backend:)`，因為
/// 所有 conformer——不論內建與否——都是以一般 view 自行繪製，答案只可能是 `true`；
/// `_BuiltinToggleStyle` 已記下「一個只可能回傳 `true` 的查詢」要付出什麼代價。此處也沒有
/// `_BuiltinLabelStyle` 這個伴生 protocol，因為該 protocol 在別處的用途是把 style 翻譯成 backend
/// 自身的詞彙（`_asBackendPickerStyle`、`_asBackendListStyle`），而 label 並不存在這樣一套詞彙。
/// 四個內建 style 就是普通的 conformer，沒有任何特權。
///
/// 其 requirement 採用 SwiftUI 的 `makeBody(configuration:)`，而非本專案慣用的 `makeView(...)`：
/// ``LabelStyleConfiguration`` 已經帶著 label style 所需的一切，因此不需要憑空設計一組參數，也沒有
/// 理由偏離作者早已熟悉的名字。``PickerStyle`` 與 ``DatePickerStyle`` 之所以不同，是因為它們的參數
/// （`options`、`selection`、`range`、`components`）在此並沒有對應的 configuration 型別。
@MainActor
public protocol LabelStyle: Sendable {
    associatedtype Body: View

    /// The properties of the label being rendered.
    typealias Configuration = LabelStyleConfiguration

    /// The method used to render ``Label``.
    /// - Parameter configuration: The title and icon of the label being
    ///   rendered.
    func makeBody(configuration: Configuration) -> Body
}

/// The title and icon of the ``Label`` being rendered.
///
/// **``Title`` and ``Icon`` are ``AnyView`` here, and SwiftUI's are opaque
/// structs.** The names still resolve, so `LabelStyleConfiguration.Title`
/// carried over from SwiftUI compiles, and a style writes `configuration.title`
/// either way. What a distinct wrapper struct would add is a widget: a plain
/// `struct Title: View` gets `View.defaultAsWidget`, which wraps its body in a
/// `VStack`, so each of the two children would gain a container that exists only
/// to hide a type that is already erased one line below. The erasure is
/// unavoidable -- this type is not generic, exactly as SwiftUI's is not -- so
/// naming it is the honest option rather than dressing it up.
///
/// 正在繪製之 ``Label`` 的標題與圖示。
///
/// **此處的 ``Title`` 與 ``Icon`` 是 ``AnyView``，而 SwiftUI 的則是 opaque struct。** 名字仍然可以
/// 解析，因此從 SwiftUI 搬過來的 `LabelStyleConfiguration.Title` 編得過，而 style 兩邊都是寫
/// `configuration.title`。獨立的包裝 struct 會多帶來的東西是一個 widget：一個單純的
/// `struct Title: View` 會走 `View.defaultAsWidget`，該實作會把 body 包進一個 `VStack`，於是兩個子
/// view 各自多出一個容器，而它存在的唯一目的，是去藏一個在下一行就已經被抹除的型別。這個抹除是免不了
/// 的——本型別並非泛型，正如 SwiftUI 的也不是——因此如實把它命名出來，比替它裝扮成別的東西要誠實。
public struct LabelStyleConfiguration {
    /// The type of the label's title.
    public typealias Title = AnyView

    /// The type of the label's icon.
    public typealias Icon = AnyView

    /// A view that describes the label.
    public var title: Title

    /// A view that identifies the label with a symbol or image.
    public var icon: Icon

    /// Wraps a label's two views for a style to rearrange.
    ///
    /// Internal because ``Label`` is the only thing that should build one; a
    /// style receives a configuration, it does not manufacture one.
    ///
    /// `@MainActor` because it calls `AnyView.init`, which is main-actor
    /// isolated (`AnyView.swift:15`). Without it the build fails with
    /// `call to main actor-isolated initializer 'init(_:)' in a synchronous
    /// nonisolated context`. This costs nothing: the only caller is ``Label``,
    /// which is a `View` and already on the main actor, and ``LabelStyle``
    /// itself is `@MainActor`. Measured 2026-09-08 -- `swiftc -parse` accepts
    /// the file without it, so syntax checking does not catch this and a real
    /// build is the only thing that does.
    ///
    /// 標記為 internal，因為只有 ``Label`` 該建構它；style 是「收到」一個 configuration，而不是自己
    /// 製造一個。
    ///
    /// 標記 `@MainActor` 是因為它呼叫 `AnyView.init`，而後者受 main actor 隔離
    /// （`AnyView.swift:15`）。缺少它會導致建置失敗。此標記不帶任何代價：唯一的呼叫端 ``Label``
    /// 是一個 `View`，本來就在 main actor 上，而 ``LabelStyle`` 本身也是 `@MainActor`。
    /// 2026-09-08 實測：`swiftc -parse` 在沒有它的情況下仍接受本檔，因此語法檢查抓不到這件事，
    /// 只有真正的建置才抓得到。
    @MainActor
    init(title: some View, icon: some View) {
        self.title = AnyView(title)
        self.icon = AnyView(icon)
    }
}
