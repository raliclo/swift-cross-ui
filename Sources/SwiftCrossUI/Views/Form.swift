/// A scrolling container for a column of labelled controls.
///
/// Composed from `ScrollView` and `VStack`, so it needs nothing from any
/// backend. See ``Stepper`` for why this batch was chosen.
///
/// **This is the container, not the platform form appearance.** SwiftUI's `Form`
/// restyles everything inside it -- inset grouped rows on iOS, aligned label
/// columns on macOS -- by pushing an environment value its children read. Nothing
/// here does that, so a `Form` is a padded scrolling column and its children look
/// exactly as they would anywhere else. Said plainly rather than left to be
/// found: the shape is right, the platform styling is absent. ``Section`` carries
/// the same note for the same reason.
///
/// The `ScrollView` is not decoration. A form is the one container that reliably
/// outgrows its window, and a non-scrolling one clips its last rows with no way
/// to reach them -- a failure that looks like a layout bug rather than a missing
/// container.
///
/// 一個可捲動的容器，用來放置一整欄帶標籤的控制項。
///
/// 由 `ScrollView` 與 `VStack` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，
/// 見 ``Stepper``。
///
/// **這是那個容器，而不是平台的表單外觀。** SwiftUI 的 `Form` 會為其中的一切重新上樣式——iOS 上
/// 的 inset grouped 列、macOS 上對齊的標籤欄——做法是推入一個環境值供子項讀取。此處沒有任何東西
/// 這麼做，因此 `Form` 就是一個帶內距、可捲動的欄，其子項的外觀與放在別處時完全相同。這一點明說
/// 而不留給人自己發現：**形狀是對的、平台樣式是缺的**。``Section`` 帶有同樣的說明，理由相同。
///
/// 那個 `ScrollView` 不是裝飾。表單是最容易長得比視窗還高的容器，而一個不能捲動的表單會把最後
/// 幾列裁掉、且無從抵達——那個失敗看起來像版面錯誤，而不像少了一個容器。
public struct Form<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content())
    }

    /// Takes the content as a VALUE, matching the shape ``VStack`` already uses.
    /// 以**值**的形式接收內容，與 ``VStack`` 既有的寫法一致。
    private init(content: Content) {
        self.content = content
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
        }
    }
}
