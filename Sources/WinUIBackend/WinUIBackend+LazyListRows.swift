import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.LazyListRows {
    /// Points the ListView at the framework instead of at an eager array.
    ///
    /// **`ListView` already virtualizes its containers** -- its default
    /// `ItemsStackPanel` realizes a `ListViewItem` only for rows near the
    /// viewport and recycles the rest. What it does not do on its own is fill
    /// that container: the eager `setItems` built one content view for every row
    /// up front. This makes the content come from `provider`, per realized
    /// container, through `ContainerContentChanging` -- WinUI's equivalent of
    /// AppKit's `tableView(_:viewFor:row:)`.
    ///
    /// So the memory this saves is the framework's, not WinUI's: the provider is
    /// only asked for rows a container is being prepared for, so the framework
    /// builds a view-graph node only for those. Measured on AppKit at 31 KB a
    /// node; WinUI's node cost is the same shape.
    ///
    /// **`estimatedRowHeight` is ignored here, and that is correct.** AppKit
    /// needs it because `NSTableView` asks for row heights up front; WinUI sizes
    /// each `ListViewItem` to its content as the container is realized and
    /// estimates the extent of unrealized rows from the ones it has. Feeding it
    /// a guess would not improve that and could fight it.
    ///
    /// 讓這個 ListView 改去問框架，而不是去問一個 eager 陣列。
    ///
    /// **`ListView` 本來就虛擬化它的容器**——預設的 `ItemsStackPanel` 只為視port附近的列實體化
    /// `ListViewItem`，其餘回收。它自己不做的是「填滿那個容器」:eager 的 `setItems` 會為每一列
    /// 預先建一個內容 view。這裡改為讓內容逐「已實體化的容器」從 `provider` 經由
    /// `ContainerContentChanging` 取得——那是 WinUI 對應 AppKit `tableView(_:viewFor:row:)` 的東西。
    ///
    /// 因此這裡省下的記憶體是**框架的**、不是 WinUI 的:provider 只會為「有容器正在被準備」的列被詢問，
    /// 於是框架也只為那些列建 view-graph 節點。AppKit 上量到每個節點 31 KB;WinUI 的節點成本是同一個形狀。
    ///
    /// **此處忽略 `estimatedRowHeight`，而那是正確的。** AppKit 需要它，因為 `NSTableView` 會預先詢問
    /// 列高;WinUI 則在容器被實體化時把每個 `ListViewItem` 依內容定尺寸，並從已實體化的列估計未實體化列的
    /// 範圍。餵它一個猜測值不會改善那件事，還可能與它相衝。
    public func setLazyRows(
        ofSelectableListView listView: Widget,
        count: Int,
        estimatedRowHeight: Int,
        provider: @escaping (Int) -> (widget: Widget, height: Int)?
    ) {
        let listView = listView as! CustomListView
        listView.lazyProvider = provider

        // The eager state and the provider are two answers to the same question;
        // a list holding both would show whichever was read first. Clear it, the
        // same clearing AppKit's setLazyRows does.
        // eager 狀態與 provider 是同一問題的兩個答案;同時持有兩者的清單會顯示先被讀到的那個。
        // 清掉它——與 AppKit 的 setLazyRows 所做的清除相同。
        listView.currentItems = []
        listView.cachedSelectedItem = nil

        attachContainerContentChanging(to: listView)

        // The item source is `count` lightweight index values. WinUI virtualizes
        // over this: it holds all `count` of them (a boxed Int is a few bytes)
        // but realizes a container for only the visible ones. The value carried
        // is never shown -- `ContainerContentChanging` replaces the container's
        // content with the provider's widget -- it exists so the panel knows how
        // many rows there are and can size the scrollbar.
        //
        // Rebuilt each call rather than diffed. A list whose count changed would
        // otherwise keep stale trailing indices, and the cost is `count`
        // appends of a boxed Int, which is bounded and one-time.
        //
        // item source 是 `count` 個輕量的索引值。WinUI 對它虛擬化:它持有全部 `count` 個(一個 boxed
        // Int 只有幾個位元組),但只為可見的那些實體化容器。所攜帶的值永遠不會被顯示——
        // `ContainerContentChanging` 會把容器的內容換成 provider 的 widget——它存在只是為了讓面板知道
        // 共有幾列、好為捲軸定尺寸。
        //
        // 每次呼叫都重建,而非做差異更新。否則一個列數改變了的清單會留著陳舊的尾端索引;而其代價是
        // `count` 次「append 一個 boxed Int」,那是有上限且一次性的。
        listView.items.clear()
        if count > 0 {
            for index in 0..<count {
                listView.items.append(Int32(index))
            }
        }
    }

    /// Subscribes `ContainerContentChanging`, at most once per list.
    ///
    /// It reads `lazyProvider` off the list at fire time rather than capturing a
    /// provider, so a later `setLazyRows` swaps the provider without needing a
    /// fresh subscription -- and a stale subscription cannot outlive the current
    /// provider.
    ///
    /// 為每個清單訂閱 `ContainerContentChanging`，最多一次。
    ///
    /// 它在觸發時從清單讀取 `lazyProvider`，而不是捕獲某個 provider，因此稍後的 `setLazyRows` 可以換掉
    /// provider 而不需要重新訂閱——而一個陳舊的訂閱也不會活得比當前的 provider 久。
    private func attachContainerContentChanging(to listView: CustomListView) {
        guard !listView.lazyHandlerAttached else { return }
        listView.lazyHandlerAttached = true

        listView.containerContentChanging.addHandler { [weak listView] _, args in
            guard let listView, let args else { return }
            // A recycled container is on its way out; dropping its content lets
            // the framework's row node be released. Without this the content --
            // and its node -- would be pinned by the container it last held.
            // 被回收的容器正在離場;丟掉它的內容能讓框架的列節點被釋放。少了這一步,內容——以及它的
            // 節點——會被它最後所持有的那個容器釘住。
            if args.inRecycleQueue {
                args.itemContainer?.content = nil
                return
            }
            let index = Int(args.itemIndex)
            guard index >= 0, let provider = listView.lazyProvider else { return }
            guard let row = provider(index) else {
                args.itemContainer?.content = nil
                return
            }
            let container = args.itemContainer
            container?.content = row.widget
            container?.horizontalContentAlignment = .left
            container?.padding = Thickness(left: 16, top: 8, right: 12, bottom: 8)
        }
    }
}
