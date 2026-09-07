/// An icon paired with a title.
///
/// Composed from `HStack`, so it needs nothing from any backend. See ``Stepper``
/// for why this batch was chosen.
///
/// **`Label(_:systemImage:)` was deliberately absent until 2026-09-08**, and the
/// paragraph below is kept because it states the condition that had to be met
/// rather than merely recording an absence. That condition was met by
/// ``BackendFeatures/Symbols``: the name is resolved by the backend, and a
/// backend that cannot produce the glyph draws ``SystemSymbol/textFallback``
/// instead of nothing. The original text follows.
///
/// **`Label(_:systemImage:)` 在 2026-09-08 之前是刻意不提供的**，而下方那段文字被保留下來，是因為
/// 它陳述的是「必須被滿足的條件」，而不只是記錄一項缺席。該條件已由 ``BackendFeatures/Symbols``
/// 滿足:名稱由 backend 解析，而無法產生該字符的 backend 會改畫 ``SystemSymbol/textFallback``，
/// 不是什麼都不畫。以下為原文。
///
/// **`Label(_:systemImage:)` is deliberately absent.** SwiftUI's most common
/// spelling names a symbol -- `Label("Add", systemImage: "plus")` -- and
/// resolving that name is backend work, not composition: SF Symbols on Apple, an
/// icon-theme lookup on GTK, Segoe Fluent Icons on WinUI. ``Image`` today takes a
/// URL or raw pixels and has no symbol source at all, so the initialiser could
/// only be added by rendering nothing where the icon belongs. A label whose icon
/// is silently missing is precisely the shape this project refuses: it compiles,
/// it runs, and it is wrong without saying so. The initialiser arrives with the
/// symbol API, in the same change.
///
/// `LabelStyle` is likewise absent, and for the separate reason recorded in task
/// #65. What is here is SwiftUI's `.automatic` layout, which is the correct
/// default rather than a stand-in for one.
///
/// 一個圖示配上一個標題。
///
/// 由 `HStack` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，見 ``Stepper``。
///
/// **`Label(_:systemImage:)` 是刻意不提供的。** SwiftUI 最常見的寫法是指名一個符號——
/// `Label("Add", systemImage: "plus")`——而解析那個名稱屬於 backend 的工作，不是組合：在 Apple
/// 上是 SF Symbols、在 GTK 上是 icon theme 查詢、在 WinUI 上是 Segoe Fluent Icons。今天的
/// ``Image`` 只接受 URL 或原始像素，根本沒有符號來源，因此若要加上這個建構式，就只能在圖示該
/// 出現的位置畫出空白。**一個圖示靜默缺席的 label，正是本專案所拒絕的那種形狀**：編得過、跑得動，
/// 錯了卻不出聲。這個建構式會與符號 API 在同一次改動中一起到來。
///
/// `LabelStyle` 同樣缺席，理由則另記於任務 #65。此處提供的是 SwiftUI 的 `.automatic` 版面，
/// 那是正確的預設值，而不是預設值的替代品。
public struct Label<Title: View, Icon: View>: View {
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

    public var body: some View {
        HStack(spacing: 6) {
            icon
            title
        }
    }
}

extension Label where Title == Text, Icon == Image {
    /// A titled label whose icon comes from an ``Image`` the caller already has.
    /// This is the spelling that works today; see the type's note on
    /// `systemImage:`.
    /// 一個帶標題的 label，其圖示來自呼叫端手上已有的 ``Image``。這是今天可用的寫法；關於
    /// `systemImage:`，見型別上的說明。
    public init(_ title: String, image: Image) {
        self.init(title: Text(title), icon: image)
    }

    /// A titled label whose icon is named, as SwiftUI spells it.
    ///
    /// The initialiser the type's note said would arrive with the symbol API.
    /// It did, and the condition that note set out is what made it possible:
    /// resolving a name is backend work, so ``BackendFeatures/Symbols`` is where
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
    /// 這正是型別上那段說明所稱「會與符號 API 一同到來」的建構式。它到來了，而讓它成為可能的，正是
    /// 那段說明所提出的條件:解析名稱是 backend 的工作，因此解析發生在 ``BackendFeatures/Symbols``
    /// 之中，而每一個 backend 都會作答——有字符時給字符，沒有時給 ``SystemSymbol/textFallback``。
    /// 此處不存在任何一種「平台與符號」的組合會畫出空白。
    ///
    /// 名稱的兩種拼法都能解析，因此從 SwiftUI 搬過來的 `Label("Add", systemImage: "plus")` 與
    /// `Label("Add", systemImage: "add")` 是同一個 label。無法辨識的名稱會畫出它自己；
    /// 見 ``Image/init(systemName:)``。
    public init(_ title: String, systemImage: String) {
        self.init(title: Text(title), icon: Image(systemName: systemImage))
    }
}
