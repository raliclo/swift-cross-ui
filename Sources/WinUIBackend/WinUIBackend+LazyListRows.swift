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

// **The rows here did not render at all until 2026-09-16, and the memory
// measurement could not see it. That is why this note is long.**
//
// The saving was real from the start -- 10,000 rows at 143 MB against 328 MB
// eager, with a control -- and the list drew nothing. Containers virtualized,
// the provider was called, the numbers were right, the screen was blank. Only a
// screenshot separated a working list from a broken one.
//
// Four arrangements were measured before one worked. They are kept because each
// looked correct, and because the first three are what a reader would naturally
// try again:
//
//   content set in phase 0            rows draw their placeholder index -- "0",
//                                     "1", "2" -- because ListViewBase's own
//                                     preparation runs AFTER the handler and
//                                     assigns Content from the data item
//   `args.handled = true`             blank. Preparation is skipped wholesale,
//                                     including the part that PRESENTS content.
//                                     A probe read the container straight back:
//                                     content=Canvas, so the assignment worked
//   `registerUpdateCallback` in a     blank, and the placeholder numbers vanish
//   later phase                       -- so that callback does fire and does
//                                     replace the content. Still nothing drawn
//   clear `contentTemplate` first     RENDERS
//
// The cause: a container WinUI GENERATES for a data item carries a
// `ContentTemplate` whose job is to render that item, here the boxed `Int32`
// placeholder. A `UIElement` assigned as `Content` is normally displayed
// directly -- but not while a template is in place to render it through. The
// element goes in and nothing comes out.
//
// The eager path never hit this, which is what made it such a good control: it
// builds its own `ListViewItem`s, and those have no template.
//
// Two probes did the work, and both were cheap. Reading the container back after
// the assignment is what ruled out "the assignment failed"; reading
// `row.widget.parent` is what ruled out "the widget is already parented". Three
// hypotheses were guessed before the first probe was written, and all three were
// wrong.
//
// **此處的那些列直到 2026-09-16 為止根本沒有算繪出來,而記憶體量測看不見這件事。**
// 這正是本註解寫得這麼長的理由。
//
// 那個節省從一開始就是真的——一萬列 143 MB,對照 eager 的 328 MB,而且有對照組——**而清單什麼都
// 沒畫**。容器有虛擬化、provider 有被呼叫、數字都對、畫面是空的。只有截圖能把「會動的清單」與
// 「壞掉的清單」分開。
//
// 在其中一種成功之前,量過四種安排。它們被保留下來,因為每一種看起來都是對的,而且前三種正是讀者
// 會自然而然再試一次的東西:
//
//   在 phase 0 設定內容          列畫出它的佔位索引「0」「1」「2」,因為 `ListViewBase` 自己的準備
//                                工作是在 handler **之後**才跑,並用 data item 指派 Content
//   `args.handled = true`        空白。準備工作被整份跳過,含「把內容呈現出來」那一部分。探針把容器
//                                直接讀回來:content=Canvas,可見那次指派是成功的
//   `registerUpdateCallback`     空白,而且佔位數字消失了——代表那個 callback 確實有觸發、也確實換掉了
//   改在較晚的 phase             內容。依然什麼都沒畫出來
//   先清掉 `contentTemplate`     **算繪成功**
//
// 成因:WinUI 為某個 data item **產生**的容器,會帶著一個 `ContentTemplate`,其職責是算繪那個
// item——此處就是那個 boxed `Int32` 佔位值。一個被指派為 `Content` 的 `UIElement` 通常會被直接顯示,
// **但在「還有一個 template 要拿來算繪它」的情況下並非如此**。元素進得去,卻什麼都出不來。
//
// eager 路徑從未遇上這件事,而那正是它作為對照組如此好用的原因:它是自己建 `ListViewItem` 的,
// 而那些沒有 template。
//
// 真正解決問題的是兩個探針,而且兩個都很便宜。「指派之後把容器讀回來」排除了「指派失敗」;
// 「讀 `row.widget.parent`」排除了「該 widget 已經有 parent」。在寫下第一個探針之前,我猜了三次,
// 而三次全錯。
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
            //
            // **Dropping the content is only half of it.** The widget stops
            // being shown, but the framework still holds the view-graph node
            // that built it, keyed by row index, and nothing here told it
            // otherwise. That is what `LazyListRowLifetimes` is for, and until
            // 2026-09-16 this backend did not conform: the nodes were bounded
            // only by `List.swift`'s 4000-row backstop cache, so a list scrolled
            // through ten thousand rows kept four thousand nodes alive that no
            // container had referenced for a long time.
            //
            // 被回收的容器正在離場;丟掉它的內容能讓框架的列節點被釋放。少了這一步,內容——以及它的
            // 節點——會被它最後所持有的那個容器釘住。
            //
            // **丟掉內容只是其中一半。** 那個 widget 不再被顯示,但框架仍然握著當初建出它的那個
            // view-graph 節點(以列索引為鍵),而這裡沒有任何東西通知過它。那正是
            // `LazyListRowLifetimes` 的用途;而直到 2026-09-16 為止,本 backend 並未 conform 它:
            // 那些節點只被 `List.swift` 的 4000 列兜底快取所限制,於是一份被捲過一萬列的清單,
            // 會留著四千個「早已沒有任何容器引用」的節點。
            if args.inRecycleQueue {
                args.itemContainer?.content = nil
                let index = Int(args.itemIndex)
                WinUIBackend.traceLazyRow("recycle index=\(index)")
                guard index >= 0, !WinUIBackend.lazyReleaseSuppressed else { return }
                listView.lazyRowReleaseHandler?(index)
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
        // **Cleared before the content is set.** A container WinUI generated for
        // a data item carries a `ContentTemplate` whose job is to render that
        // item -- here the boxed `Int32` placeholder. A `UIElement` assigned as
        // `Content` is normally displayed directly, but not while a template is
        // in place to render it through: the element goes in and nothing comes
        // out. The eager path never hit this because it builds its own
        // `ListViewItem`s, which have no template.
        // **在設定內容之前先清掉它。** WinUI 為某個 data item 產生的容器,會帶著一個
        // `ContentTemplate`,其職責是算繪那個 item——此處就是那個 boxed `Int32` 佔位值。一個被指派為
        // `Content` 的 `UIElement` 通常會被直接顯示,但在「還有一個 template 要拿來算繪它」的情況下
        // 並非如此:元素進得去,卻什麼都出不來。eager 路徑從未遇上這件事,因為它是自己建
        // `ListViewItem` 的,而那些沒有 template。
        container.contentTemplate = nil
        container.content = row.widget
        container.horizontalContentAlignment = .left
        container.padding = Thickness(left: 16, top: 8, right: 12, bottom: 8)
        traceLazyRow("prepare index=\(index)")
    }

    // **~~The row a container holds has to be recorded on the way in, because
    // a container can be rebound in place with no recycle event.~~ Both halves
    // of that were measured false on 2026-09-16, and both looked right.**
    //
    // Two recordings were tried and neither is in this file any more:
    //
    //   a side table keyed by      answered a different question every time. The
    //   `ObjectIdentifier`         Swift objects are per-access wrappers around a
    //                              COM pointer, so one address served rows 2-7
    //                              and then 14-18. See `CustomListView`.
    //   the container's own `Tag`  does not round-trip through this binding. A
    //                              probe wrote `Int32(index)` and read the tag
    //                              straight back: LOST on 95 of 95 prepares, so
    //                              a release path reading it fires NEVER while
    //                              the conformance still moves `List.swift` to
    //                              the 4,000-row backstop -- strictly worse than
    //                              not conforming at all
    //
    // And the premise did not hold either. Over a run that prepared 95 rows and
    // recycled 61, **no row was ever prepared again while still live**: every
    // re-preparation had a recycle of that same index before it. So a rebind
    // path is not needed, and `inRecycleQueue` is the whole signal.
    //
    // What makes `itemIndex` trustworthy HERE, having been doubted: every one of
    // the 61 recycled indices is a row that had been prepared, and the two
    // ranges are exactly the rows abandoned by the two scrolls -- 1-25 on the
    // jump to the end, 9964-9999 on the way back to the top.
    //
    // **~~容器持有哪一列必須在放進去時記下來,因為容器可能在沒有回收事件的情況下就地重新綁定。~~
    // 這句話的兩半都在 2026-09-16 被量成假的,而兩者看起來都對。**
    //
    // 試過兩種記錄方式,而兩者都已不在本檔案中:
    //
    //   以 `ObjectIdentifier` 為鍵的旁表   每次被詢問時回答的都是另一個問題。那些 Swift 物件是
    //                                      「每次存取都新建」的 COM 指標 wrapper,於是同一個位址
    //                                      served 了第 2-7 列、接著第 14-18 列。見 `CustomListView`。
    //   容器自己的 `Tag`                   在這個綁定上**無法來回**。探針寫入 `Int32(index)` 後
    //                                      立刻讀回:95 次 prepare 全部 LOST。因此一條讀它的釋放
    //                                      路徑**永遠不會觸發**,而那個 conformance 卻已經讓
    //                                      `List.swift` 切到 4,000 列的兜底上限——比不 conform 還糟。
    //
    // 而那個前提本身也不成立。在一次準備了 95 列、回收了 61 列的執行中,**沒有任何一列在仍然存活時
    // 被再次準備**:每一次重新準備之前,都先有該索引的一次回收。所以不需要 rebind 路徑,
    // `inRecycleQueue` 就是全部的訊號。
    //
    // 曾被懷疑過的 `itemIndex`,在**此處**可信的理由:那 61 個被回收的索引,每一個都是曾被準備過的
    // 列,而它們的兩段範圍正好就是兩次捲動所拋下的列——跳到底時的 1-25,回到頂端時的 9964-9999。

    /// Prints one line per row prepared or released, when
    /// `SCUI_WINUI_LAZY_TRACE` is set.
    ///
    /// Off by default because a list being scrolled produces one line per row
    /// per screenful, which is exactly the volume that makes a log unreadable
    /// for every other purpose.
    ///
    /// 在設定了 `SCUI_WINUI_LAZY_TRACE` 時,每準備或釋放一列印一行。
    ///
    /// 預設關閉:一份正在被捲動的清單,每捲過一個畫面就會產出每列一行,而那個量正好會讓這份 log
    /// 對其他任何用途都失去可讀性。
    /// `SCUI_WINUI_NO_LAZY_RELEASE=1` keeps the conformance and withholds the
    /// callback. **It exists to make the control group runnable from the same
    /// binary**, and there is no other way to get one: conforming to
    /// `LazyListRowLifetimes` is what moves `List.swift` off its 200-row LRU and
    /// onto the 4,000-row backstop, so "before" and "after" differ in two things
    /// at once unless one of them can be held still. With this set, the cache
    /// policy is the after and the releases are the before.
    ///
    /// A measurement switch, not a feature. Nothing but a probe should set it,
    /// and a list running with it set leaks row nodes up to the backstop --
    /// which is precisely the number the control is there to show.
    ///
    /// `SCUI_WINUI_NO_LAZY_RELEASE=1` 會**保留** conformance、但**扣住**那個回呼。
    /// **它的存在是為了讓對照組能用同一個執行檔跑起來**,而且沒有別的辦法:conform
    /// `LazyListRowLifetimes` 這件事本身,就會讓 `List.swift` 從 200 列的 LRU 換到 4,000 列的
    /// 兜底上限——因此若不把其中一項固定住,「之前」與「之後」會同時差兩件事。設了它之後,
    /// 快取策略是「之後」,而釋放行為是「之前」。
    ///
    /// 這是量測開關,不是功能。除了探針以外不該有任何東西設定它;設了它的清單會把列節點漏到兜底上限
    /// ——而那個數字正是這個對照組要顯示的東西。
    static let lazyReleaseSuppressed =
        ProcessInfo.processInfo.environment["SCUI_WINUI_NO_LAZY_RELEASE"] != nil

    fileprivate static func traceLazyRow(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["SCUI_WINUI_LAZY_TRACE"] != nil else { return }
        print("LAZYROW \(message())")
    }
}

/// Reports a row's index when the container holding it is recycled.
///
/// **Kept as its own extension rather than folded into the one above.**
/// `LazyListRowLifetimes` refines `LazyListRows`, so a single extension naming
/// the refined protocol would satisfy both -- which is exactly what made
/// GtkBackend look, to a source sweep on 2026-09-16, as though it had no
/// `LazyListRows` conformance at all. Two named extensions cost nothing and
/// leave both names where a reader and a grep can find them.
///
/// 刻意保留為獨立的 extension,而不是併進上面那個。`LazyListRowLifetimes` refine 了
/// `LazyListRows`,因此**只寫一個具名 refined 協定的 extension 就能同時滿足兩者**——而那正是
/// 2026-09-16 一次原始碼掃描把 GtkBackend 看成「完全沒有 `LazyListRows` conformance」的原因。
/// 寫成兩個具名 extension 不花任何成本,卻讓兩個名字都留在讀者與 grep 找得到的地方。
extension WinUIBackend: BackendFeatures.LazyListRowLifetimes {
    public func setLazyRowReleaseHandler(
        ofSelectableListView listView: Widget,
        to handler: @escaping (Int) -> Void
    ) {
        (listView as! CustomListView).lazyRowReleaseHandler = handler
    }
}
