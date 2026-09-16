import Foundation
import SwiftCrossUI
import WinUI
// `TypedEventHandler` is not a class here -- WindowsFoundation declares it as
// `typealias TypedEventHandler<TSender, TResult> = (TSender, TResult) -> ()`,
// a plain closure -- so `registerUpdateCallback` takes a closure literal and
// this import is what puts the name in scope.
// 此處的 `TypedEventHandler` 不是一個 class——`WindowsFoundation` 把它宣告為
// `typealias TypedEventHandler<TSender, TResult> = (TSender, TResult) -> ()`,一個單純的 closure
// ——因此 `registerUpdateCallback` 收的是一個 closure literal,而這個 import 正是讓那個名字進入作用域的東西。
@preconcurrency import WindowsFoundation

// **THE CONFORMANCE IS WITHHELD ON PURPOSE. Do not re-add
// `: BackendFeatures.LazyListRows` without first making the rows render.**
//
// This code virtualizes correctly and saves the memory it claims -- 10,000 rows
// measured 143 MB against 328 MB eager, with a control. It also draws NOTHING.
// Both were true at once, which is the entire lesson here.
//
// Measured on 2026-09-16, WinUI, P57 at 10,000 rows, three arrangements:
//
//   content set in phase 0            rows render as their placeholder index,
//                                     "0" "1" "2", because ListViewBase's own
//                                     preparation runs afterwards and assigns
//                                     Content from the data item
//   `args.handled = true`             blank. Preparation is skipped wholesale,
//                                     including presenting the content. Probed
//                                     the container straight back: content=Canvas,
//                                     so the assignment HAD worked
//   `registerUpdateCallback`, later   blank. The callback fires and replaces the
//   phase                             placeholder -- which is why the numbers
//                                     disappear -- and the Canvas still shows
//                                     nothing
//
// The EAGER path renders correctly with the SAME Canvas widgets in the SAME
// ListViewItem containers (captured 2026-09-16: "row 0 revision 0" and on down),
// so a Canvas can be a ListViewItem's content. What differs on the lazy path has
// not been found yet.
//
// A list that renders nothing is worse than a list that uses more memory, and
// `LazyListRows` is conformance-checked, so withholding it restores fully
// correct behaviour at the eager path's cost. That is the trade taken here.
//
// **此處刻意不掛上 conformance。在讓那些列真的算繪出來之前,不要把
// `: BackendFeatures.LazyListRows` 加回去。**
//
// 這段程式碼的虛擬化是正確的,也確實省下了它所宣稱的記憶體——一萬列量到 143 MB,對照 eager 的
// 328 MB,而且有對照組。它同時**什麼都畫不出來**。兩件事同時為真,而那就是此處的全部教訓。
//
// 2026-09-16 在 WinUI 上以 P57、一萬列量測三種安排:
//
//   在 phase 0 設定內容        列算繪成它的佔位索引「0」「1」「2」,因為 `ListViewBase` 自己的
//                              準備工作在那之後才跑,並用 data item 指派 Content
//   `args.handled = true`      空白。準備工作被整份跳過,包含「把內容呈現出來」。把容器直接讀回來
//                              得到 content=Canvas,可見那次指派**是成功的**
//   `registerUpdateCallback`   空白。該 callback 有觸發、也換掉了佔位值——這正是那些數字消失的原因
//   改在較晚的 phase           ——而那個 Canvas 依然什麼都不顯示
//
// **eager 路徑用同樣的 Canvas widget、放在同樣的 ListViewItem 容器裡,算繪是正確的**
// (2026-09-16 擷圖:「row 0 revision 0」以下皆是),因此 Canvas 是可以當 ListViewItem 的內容的。
// lazy 路徑上究竟差在哪裡,目前尚未找到。
//
// 一份什麼都畫不出來的清單,比一份比較耗記憶體的清單更糟;而 `LazyListRows` 是 conformance 檢查制,
// 因此把它收回來,就能以「回到 eager 路徑的成本」換取完全正確的行為。此處採取的正是這個取捨。
extension WinUIBackend {
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
        // is never shown -- the update callback below replaces the container's
        // content with the provider's widget -- it exists so the panel knows how
        // many rows there are and can size the scrollbar.
        //
        // Rebuilt each call rather than diffed. A list whose count changed would
        // otherwise keep stale trailing indices, and the cost is `count`
        // appends of a boxed Int, which is bounded and one-time.
        //
        // item source 是 `count` 個輕量的索引值。WinUI 對它虛擬化:它持有全部 `count` 個(一個 boxed
        // Int 只有幾個位元組),但只為可見的那些實體化容器。所攜帶的值永遠不會被顯示——下方那個 update
        // callback 會把容器的內容換成 provider 的 widget——它存在只是為了讓面板知道共有幾列、好為捲軸定尺寸。
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

            // **Phase 0 belongs to ListViewBase, and neither fighting it nor
            // pre-empting it works. Both were measured on 2026-09-16.**
            //
            // Assigning the content during phase 0 and returning: the control's
            // own preparation runs AFTERWARDS and assigns `Content` from the
            // data item, so every row rendered as its placeholder index -- "0",
            // "1", "2" -- where GtkBackend rendered "row 0 revision 1".
            //
            // Setting `args.handled = true` to stop that: preparation is skipped
            // wholesale, including the part that PRESENTS the content. A probe
            // read the container straight back and found `content=Canvas`, so
            // the assignment had worked -- and the list drew nothing at all.
            // Content present, never shown.
            //
            // **Neither failure was visible in the memory measurement**, which
            // is the reason this comment is long. Containers were virtualized
            // and the provider was called in both cases, so 10,000 rows measured
            // flat at 143 MB against 328 eager either way. Right size, right
            // cost, wrong content. Only a screenshot separated them.
            //
            // So the content is applied in a LATER phase, through the callback
            // WinUI provides for exactly this, after the control has finished.
            //
            // **phase 0 屬於 `ListViewBase`,而「與它相爭」和「搶在它之前」兩者都行不通——
            // 兩者都在 2026-09-16 量過。**
            //
            // 在 phase 0 指派內容然後返回:該控制項自己的準備工作是**在那之後**才跑,並用 data item
            // 去指派 `Content`,於是每一列都算繪成它的佔位索引——「0」「1」「2」——而 GtkBackend
            // 算繪出來的是「row 0 revision 1」。
            //
            // 改設 `args.handled = true` 去阻止它:準備工作被整份跳過,**包含「把內容呈現出來」的那一部分**。
            // 探針把容器直接讀回來,得到 `content=Canvas`,可見那次指派是成功的——而清單什麼都沒畫出來。
            // 內容在,但從未被顯示。
            //
            // **這兩種失敗在記憶體量測中都看不見**,而那正是本註解寫得這麼長的理由。兩種情況下容器都有
            // 虛擬化、provider 都有被呼叫,因此一萬列在兩種情況下都平穩地量到 143 MB(對照 eager 的
            // 328 MB)。尺寸對、成本對、內容錯。只有截圖能把它們分開。
            //
            // 因此內容改在**較晚的 phase** 套用——透過 WinUI 正為此提供的那個 callback,在該控制項
            // 完成自己的工作之後。
            if args.phase == 0 {
                try? args.registerUpdateCallback { _, laterArgs in
                    MainActor.assumeIsolated {
                        WinUIBackend.applyLazyRow(listView: listView, args: laterArgs)
                    }
                }
                return
            }

            WinUIBackend.applyLazyRow(listView: listView, args: args)
        }
    }

    /// Puts one row's widget into its container, after WinUI has finished
    /// preparing that container.
    /// 在 WinUI 完成對某個容器的準備工作之後,把該列的 widget 放進那個容器。
    @MainActor
    fileprivate static func applyLazyRow(
        listView: CustomListView,
        args: ContainerContentChangingEventArgs?
    ) {
        guard let args, let container = args.itemContainer else { return }
        let index = Int(args.itemIndex)
        guard index >= 0, let provider = listView.lazyProvider else { return }
        guard let row = provider(index) else {
            container.content = nil
            return
        }
        container.content = row.widget
        container.horizontalContentAlignment = .left
        container.padding = Thickness(left: 16, top: 8, right: 12, bottom: 8)
    }
}
