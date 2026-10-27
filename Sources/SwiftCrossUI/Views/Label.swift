/// An icon paired with a title.
///
/// Composed from `HStack` by default, and from whatever ``LabelStyle`` is in
/// scope otherwise -- either way it needs nothing from any backend. See
/// ``Stepper`` for why this batch was chosen.
///
/// **`Label(_:systemImage:)` depends on ``BackendFeatures/Symbols``.**
/// Resolving a symbol name is backend work, not composition: SF Symbols on
/// Apple, an icon-theme lookup on GTK, Segoe Fluent Icons on WinUI. A backend
/// that cannot produce the glyph draws ``SystemSymbol/textFallback`` instead of
/// nothing, because a label whose icon is silently missing compiles, runs, and
/// is wrong without saying so.
///
/// Styles come from ``LabelStyle`` and its four built-ins, reached by
/// ``View/labelStyle(_:)``. The default, ``DefaultLabelStyle`` (`.automatic`),
/// renders `HStack(spacing: 6) { icon; title }` through
/// ``TitleAndIconLabelStyle``.
///
/// 一個圖示配上一個標題。
///
/// 預設由 `HStack` 組合而成，否則由當前作用中的 ``LabelStyle`` 組合——兩者皆不需要任何 backend
/// 支援。本批工作為何如此挑選，見 ``Stepper``。
///
/// **`Label(_:systemImage:)` 依賴 ``BackendFeatures/Symbols``。** 解析符號名稱屬於 backend 的工作，
/// 不是組合：在 Apple 上是 SF Symbols、在 GTK 上是 icon theme 查詢、在 WinUI 上是 Segoe Fluent
/// Icons。無法產生該字符的 backend 會改畫 ``SystemSymbol/textFallback``,而不是什麼都不畫，因為一個
/// 圖示靜默缺席的 label 編得過、跑得動，錯了卻不出聲。
///
/// 樣式來自 ``LabelStyle`` 及其四個內建樣式，經由 ``View/labelStyle(_:)`` 取用。預設的
/// ``DefaultLabelStyle``(`.automatic`)經由 ``TitleAndIconLabelStyle`` 繪製
/// `HStack(spacing: 6) { icon; title }`。
public struct Label<Title: View, Icon: View>: View {
    @Environment(\.labelStyle) var labelStyle

    private let title: Title
    private let icon: Icon

    public init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(title: title(), icon: icon())
    }

    /// Takes both views as VALUES. See ``Stepper``'s equivalent for why the
    /// convenience initialisers cannot go through the `@ViewBuilder` form.
    /// 以**值**的形式接收兩個 view。便利建構式為何不能走 `@ViewBuilder` 那一版，見 ``Stepper``
    /// 中的對應說明。
    private init(title: Title, icon: Icon) {
        self.title = title
        self.icon = icon
    }

    /// Routed through the style, as ``Toggle``, ``Picker`` and ``DatePicker``
    /// are. The default, `HStack(spacing: 6) { icon; title }`, is
    /// ``TitleAndIconLabelStyle``'s body, reached by the default
    /// ``EnvironmentValues/labelStyle`` of `.automatic`.
    ///
    /// `AnyView` because the style is existential and its `Body` is not known
    /// here; the same reason ``Toggle`` uses one.
    ///
    /// 交由 style 繪製，與 ``Toggle``、``Picker``、``DatePicker`` 相同。預設的
    /// `HStack(spacing: 6) { icon; title }` 是 ``TitleAndIconLabelStyle`` 的 body，由預設的
    /// ``EnvironmentValues/labelStyle``(即 `.automatic`)抵達。
    ///
    /// 使用 `AnyView`，因為此處的 style 是 existential，其 `Body` 型別在這裡無從得知；理由與
    /// ``Toggle`` 相同。
    public var body: some View {
        AnyView(
            labelStyle.makeBody(
                configuration: LabelStyleConfiguration(title: title, icon: icon)
            )
        )
    }
}

extension Label where Title == Text, Icon == Image {
    /// A titled label whose icon comes from an ``Image`` the caller already has.
    /// 一個帶標題的 label，其圖示來自呼叫端手上已有的 ``Image``。
    public init(_ title: String, image: Image) {
        self.init(title: Text(title), icon: image)
    }

    /// A titled label whose icon is named, as SwiftUI spells it.
    ///
    /// Resolving a name is backend work, so ``BackendFeatures/Symbols`` is where
    /// the resolving happens, and every backend answers -- with a glyph where it
    /// has one and with ``SystemSymbol/textFallback`` where it does not. There
    /// is no arrangement of platform and symbol that draws nothing here.
    ///
    /// Both spellings of a name resolve, so `Label("Add", systemImage: "plus")`
    /// carried over from SwiftUI and `Label("Add", systemImage: "add")` are the
    /// same label. An unrecognised name draws itself; see ``Image/init(systemName:)``.
    ///
    /// 一個帶標題的 label，其圖示以名稱指定——即 SwiftUI 的寫法。
    ///
    /// 解析名稱是 backend 的工作，因此解析發生在 ``BackendFeatures/Symbols`` 之中，而每一個 backend
    /// 都會作答——有字符時給字符，沒有時給 ``SystemSymbol/textFallback``。此處不存在任何一種
    /// 「平台與符號」的組合會畫出空白。
    ///
    /// 名稱的兩種拼法都能解析，因此從 SwiftUI 搬過來的 `Label("Add", systemImage: "plus")` 與
    /// `Label("Add", systemImage: "add")` 是同一個 label。無法辨識的名稱會畫出它自己；
    /// 見 ``Image/init(systemName:)``。
    public init(_ title: String, systemImage: String) {
        self.init(title: Text(title), icon: Image(systemName: systemImage))
    }
}
