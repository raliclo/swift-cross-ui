import UIKit

/// A split view for the idioms where `UISplitViewController` will not show two
/// columns.
///
/// On a compact-width iPhone, `UISplitViewController` collapses to a navigation
/// stack regardless of `preferredDisplayMode`; there is no configuration that
/// makes it place a sidebar beside a detail pane. So this is not a wrapper
/// around it — it is the two panes laid out side by side, which is what
/// `NavigationSplitView` means and what every other backend produces.
///
/// It is deliberately close to what the layout system already assumes. Look at
/// `SplitView.commit`: it asks the backend for ``resolvedSidebarWidth``, gives
/// the leading child that width and the trailing child the remainder, then
/// positions each pane's *contents* itself. The one thing it never does is
/// place the panes — `UISplitViewController` does that for the iPad path, and
/// this does it here, in ``layoutSubviews``.
///
/// **The width is derived, not stored.** `UISplitViewController` settles on a
/// column width and can be asked what it chose; there is nothing here to ask,
/// so `sidebarWidth` has to be able to answer during `computeLayout`, before
/// any layout pass has run. Deriving it from `width` — the value
/// `setSize(of:)` just wrote — means the answer is available immediately and is
/// the same number `layoutSubviews` will use.
///
/// 供「`UISplitViewController` 不會顯示兩欄」的那些 idiom 使用的分割視圖。
///
/// 在緊湊寬度的 iPhone 上，`UISplitViewController` 無論 `preferredDisplayMode` 為何都會收合成一個
/// navigation stack；沒有任何設定能讓它把 sidebar 放在 detail 窗格旁邊。因此本類別並非它的包裝——
/// 它就是並排放置的兩個窗格，而那正是 `NavigationSplitView` 的語意，也是其他每一個 backend 所產生
/// 的結果。
///
/// 它刻意貼近版面系統原本就假設的東西。看 `SplitView.commit`：它向 backend 詢問
/// ``resolvedSidebarWidth``，把該寬度給 leading 子視圖、其餘給 trailing 子視圖，然後自行定位每個
/// 窗格的**內容**。它唯一不做的事，是擺放窗格本身——iPad 路徑上那是 `UISplitViewController` 的工作，
/// 而此處由 ``layoutSubviews`` 完成。
///
/// **寬度是推導出來的，不是存起來的。** `UISplitViewController` 會決定一個欄寬並可被詢問；此處沒有
/// 對象可問，因此 `sidebarWidth` 必須能在 `computeLayout` 期間、任何 layout pass 執行之前就回答。
/// 由 `width`——`setSize(of:)` 剛寫入的那個值——推導，使答案立即可得，且與 `layoutSubviews` 稍後所
/// 用的是同一個數字。
final class PhoneSplitWidget: BaseViewWidget {
    private let sidebarWidget: any WidgetProtocol
    private let mainWidget: any WidgetProtocol

    var resizeHandler: (() -> Void)?

    private var minimumSidebarWidth = 0
    private var maximumSidebarWidth = Int.max

    /// The same fraction `SplitWidget` gives `UISplitViewController` through
    /// `preferredPrimaryColumnWidthFraction`, so the two paths open at the same
    /// proportion and a screenshot from one is comparable with the other.
    /// 與 `SplitWidget` 透過 `preferredPrimaryColumnWidthFraction` 給
    /// `UISplitViewController` 的比例相同，使兩條路徑以相同比例開啟，兩者的螢幕截圖可以互相比較。
    private static let preferredFraction: CGFloat = 0.3

    /// The width the sidebar pane will actually get.
    ///
    /// Clamped last, and clamped in this order, because the bounds arrive from
    /// `SplitView.commit` as *content* minimums: the maximum is
    /// `totalWidth - minimumTrailingWidth`, which can fall below the minimum
    /// when neither pane fits. `max(minimum:)` after `min(maximum:)` keeps the
    /// leading pane's minimum winning in that case, which matches the order
    /// `commit` itself uses when it computes the maximum.
    ///
    /// sidebar 窗格實際會取得的寬度。
    ///
    /// 最後才做夾限，且依此順序，因為邊界值是以**內容**最小值的形式從 `SplitView.commit` 傳來的：
    /// 最大值為 `總寬度 - minimumTrailingWidth`，當兩個窗格都放不下時，它可能低於最小值。先
    /// `min(maximum:)` 再 `max(minimum:)`，可讓 leading 窗格的最小值在該情況下勝出，這與 `commit`
    /// 自己計算最大值時所用的順序一致。
    var resolvedSidebarWidth: Int {
        let available = width > 0 ? CGFloat(width) : bounds.width
        guard available > 0 else { return minimumSidebarWidth }

        let preferred = Int((available * Self.preferredFraction).rounded(.toNearestOrEven))
        return max(minimumSidebarWidth, min(maximumSidebarWidth, preferred))
    }

    init(sidebarWidget: any WidgetProtocol, mainWidget: any WidgetProtocol) {
        self.sidebarWidget = sidebarWidget
        self.mainWidget = mainWidget
        super.init()

        add(childWidget: sidebarWidget)
        add(childWidget: mainWidget)
    }

    func setSidebarWidthBounds(minimum: Int, maximum: Int) {
        guard minimum != minimumSidebarWidth || maximum != maximumSidebarWidth else { return }
        minimumSidebarWidth = minimum
        maximumSidebarWidth = maximum
        setNeedsLayout()
    }

    /// Guards against the resize handler re-entering within one pass of the run
    /// loop, the same way ``SplitWidget/hasCalledResizeHandler`` does. The
    /// handler asks SwiftCrossUI to lay out again, which sets a new size, which
    /// lays out again.
    /// 防止 resize handler 在同一輪 run loop 中重入，做法與
    /// ``SplitWidget/hasCalledResizeHandler`` 相同。該 handler 會請 SwiftCrossUI 重新排版，
    /// 而重新排版會設定新的尺寸，新的尺寸又會觸發排版。
    private var hasCalledResizeHandler = false {
        willSet {
            if newValue {
                DispatchQueue.main.async { [weak self] in
                    self?.hasCalledResizeHandler = false
                }
            }
        }
    }

    private var lastLaidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let sidebar = resolvedSidebarWidth

        // Written through the widget properties rather than the frames. Every
        // other container in this backend positions its children with the
        // left/top/width/height constraints in `WidgetProtocolHelpers`; setting
        // frames here would be overwritten by the next Auto Layout pass.
        // 透過 widget 屬性而非 frame 寫入。本 backend 中其他每一個容器都是以
        // `WidgetProtocolHelpers` 的 left/top/width/height constraint 來定位子元件；在此處設定
        // frame 會被下一輪 Auto Layout 覆寫。
        sidebarWidget.x = 0
        sidebarWidget.y = 0
        sidebarWidget.width = sidebar
        sidebarWidget.height = Int(size.height.rounded(.toNearestOrEven))

        mainWidget.x = sidebar
        mainWidget.y = 0
        mainWidget.width = max(0, Int(size.width.rounded(.toNearestOrEven)) - sidebar)
        mainWidget.height = Int(size.height.rounded(.toNearestOrEven))

        // Only on a real size change. `SplitWidget` fires on every
        // `layoutSubviews` and relies on the async reset to stop the loop;
        // firing on the size instead means a steady state produces no calls at
        // all, and the async reset is left as the guard for the pass in which
        // the size really did change.
        // 僅在尺寸真的改變時觸發。`SplitWidget` 是每次 `layoutSubviews` 都觸發，靠非同步重設來中斷
        // 迴圈；改以尺寸為條件，意味著穩定狀態下完全不會產生呼叫，而非同步重設則留作「尺寸確實改變的
        // 那一輪」的防護。
        guard size != lastLaidOutSize else { return }
        lastLaidOutSize = size

        guard !hasCalledResizeHandler else { return }
        hasCalledResizeHandler = true
        resizeHandler?()
    }
}
