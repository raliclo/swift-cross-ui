import Foundation

/// One tab of a ``TabView``: a title and the view behind it.
///
/// The iOS 18 SwiftUI shape, where a tab is a value written beside its content
/// rather than a modifier applied to it. That form is also the one this
/// codebase can express: the older `.tabItem` spelling needs the label carried
/// up out of an arbitrary child view, and preferences only reach the parent
/// after layout -- by which time the tab strip has already been built and would
/// be a frame behind.
///
/// ``TabView`` 的一個分頁：一個標題與其背後的視圖。
///
/// 採 iOS 18 SwiftUI 的形式——分頁是寫在內容旁邊的「值」，而非套用於內容之上的 modifier。這也正是
/// 此程式庫表達得出來的形式：較舊的 `.tabItem` 寫法需要把標籤從任意子視圖中往上帶，而 preference
/// 要到 layout 之後才會抵達父層——屆時分頁列早已建構完成，只會慢一個 frame。
public struct Tab {
    var title: String
    var content: AnyView

    /// Creates a tab.
    ///
    /// - Parameters:
    ///   - title: The label on the tab.
    ///   - content: The view shown when the tab is selected.
    @MainActor
    public init<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        // Erased so a tab view's tabs can be a plain array. Every other
        // approach to a heterogeneous list here needs a generated variadic
        // type; a `Tab` is a value rather than a view, so it can be erased
        // without the view graph noticing.
        // 進行型別抹除，使一個 tab view 的分頁能以單純的陣列表示。此處要處理異質清單的其他做法都
        // 需要產生式的可變參數型別；而 `Tab` 是「值」而非 view，因此可以在 view graph 無從察覺的
        // 情況下被抹除。
        self.content = AnyView(content())
    }
}

/// Collects the tabs written inside a ``TabView``.
@resultBuilder
public enum TabBuilder {
    public static func buildExpression(_ tab: Tab) -> [Tab] { [tab] }
    public static func buildBlock(_ components: [Tab]...) -> [Tab] { components.flatMap { $0 } }
    public static func buildArray(_ components: [[Tab]]) -> [Tab] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [Tab]?) -> [Tab] { component ?? [] }
    public static func buildEither(first component: [Tab]) -> [Tab] { component }
    public static func buildEither(second component: [Tab]) -> [Tab] { component }
}

/// A container that shows one of several views at a time, with a row of tabs to
/// choose between them.
///
/// ```swift
/// TabView(selection: $tab) {
///     Tab("Overview") { OverviewPage() }
///     Tab("Networking") { NetworkPage() }
/// }
/// ```
///
/// Composed from ordinary views rather than asked of the backend, so every
/// backend has it at once. A deliberate first step rather than the end state: a
/// native tab strip -- `GtkStackSwitcher`, `NSTabView`, WinUI's `TabView` -- is
/// what each platform's users expect, and a `BackendFeatures` protocol is how a
/// backend will opt into drawing one. Shipping the protocol first would have
/// meant a `TabView` that traps on every backend that had not implemented it
/// yet, because `@CastBackend` turns a missing conformance into a `fatalError`
/// rather than a fallback.
///
/// 一次顯示多個視圖其中之一的容器，並以一列分頁供選擇（如上）。
///
/// 由一般 view 組成而非向 backend 索取，因此所有 backend 一次獲得。這是刻意的第一步而非最終狀態：
/// 原生分頁列——`GtkStackSwitcher`、`NSTabView`、WinUI 的 `TabView`——才是各平台使用者所預期的，
/// 而 `BackendFeatures` 協定則是 backend 選擇繪製原生分頁列的方式。若先推出協定，結果會是
/// 「`TabView` 在所有尚未實作它的 backend 上直接 trap」，因為 `@CastBackend` 會把「未符合協定」
/// 轉為 `fatalError` 而非退回後備。
public struct TabView: View {
    var tabs: [Tab]
    var selection: Binding<Int>?

    @State private var internalSelection = 0

    /// Creates a tab view.
    ///
    /// - Parameters:
    ///   - selection: The index of the visible tab. Omit it and the view keeps
    ///     its own, which is what a tab view with nothing else depending on it
    ///     wants.
    ///   - content: The tabs.
    public init(
        selection: Binding<Int>? = nil,
        @TabBuilder content: () -> [Tab]
    ) {
        self.selection = selection
        tabs = content()
    }

    private var selected: Int {
        let index = selection?.wrappedValue ?? internalSelection
        // Clamped rather than trusted. The binding belongs to the caller and
        // nothing stops it holding an index no tab has -- restored from disk,
        // or left behind by a shorter list -- and an out-of-range subscript
        // here would take the whole application down.
        // 進行夾制而非直接信任。該綁定屬於呼叫端，沒有任何機制阻止它持有一個沒有對應分頁的索引
        // ——可能是從磁碟還原，或是較短的清單所遺留——而此處若發生索引越界，會使整個應用程式崩潰。
        return min(max(index, 0), max(tabs.count - 1, 0))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { entry in
                    Button(label(for: entry.offset, title: entry.element.title)) {
                        select(entry.offset)
                    }
                }
                Spacer()
            }
            .padding(6)

            Divider()

            // Only the selected tab is built.
            //
            // SwiftUI keeps every tab alive, so a half-filled form or a scroll
            // position survives a switch away and back. This does not: the
            // unselected tabs are not in the view graph, so their state is
            // rebuilt when they return. Written down rather than left to be
            // discovered, because it is the difference people notice first and
            // it is not visible in a screenshot.
            //
            // 只有被選取的分頁會被建構。
            //
            // SwiftUI 會讓每個分頁保持存活，因此填到一半的表單或捲動位置能在切走再切回之後留存。
            // 此處則否：未選取的分頁不在 view graph 中，其狀態會在回到該分頁時重新建構。此事明白
            // 記錄而非留待日後發現，因為它是使用者最先察覺的差異，而截圖看不出來。
            if tabs.isEmpty {
                Text("No tabs")
            } else {
                tabs[selected].content
            }
        }
    }

    /// The selected tab is marked in its text.
    ///
    /// Not with a colour or a border: a backend's button styling is its own,
    /// and a highlight that reads clearly on one platform can be invisible on
    /// another. Brackets are legible everywhere, including in a screenshot
    /// taken by a test -- which is what has to read it here.
    ///
    /// 被選取的分頁以文字標示。
    ///
    /// 不使用顏色或框線：各 backend 的按鈕樣式自成一格，在某個平台上清晰的強調效果，在另一個平台
    /// 上可能完全看不見。括號在任何地方都可讀，包括測試所擷取的截圖——而在此處，真正需要讀懂它的
    /// 正是截圖。
    private func label(for index: Int, title: String) -> String {
        index == selected ? "[ \(title) ]" : title
    }

    private func select(_ index: Int) {
        if let selection {
            selection.wrappedValue = index
        } else {
            internalSelection = index
        }
    }
}
