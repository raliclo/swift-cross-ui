import AndroidKit
import SwiftJava
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.LazyListRows {
    /// Points the adapter at the framework instead of at an array.
    ///
    /// **`BaseAdapter` is already the right shape** -- `getCount`, `getView(position,...)` --
    /// so only where `getView` reads from changes, through two native methods on
    /// `CustomListAdapter`.
    ///
    /// `ListView` recycles the row containers itself through `convertView`, so
    /// the AppKit and UIKit half of this work -- giving the recycled view an
    /// identifier -- has no counterpart here. The adapter already honours
    /// `convertView`.
    ///
    /// 讓 adapter 改去問框架，而不是去問一個陣列。
    ///
    /// **`BaseAdapter` 本來就是對的形狀**——`getCount`、`getView(position,...)`——因此改變的只是 `getView`
    /// 從哪裡讀,途徑是 `CustomListAdapter` 上的兩個 native method。
    ///
    /// `ListView` 自己會透過 `convertView` 回收那些列容器，因此 AppKit 與 UIKit 那一半的工作
    /// ——給被回收的 view 一個識別碼——在此處沒有對應物。這個 adapter 本來就遵守 `convertView`。
    ///
    public func setLazyRows(
        ofSelectableListView listView: Widget,
        count: Int,
        estimatedRowHeight: Int,
        provider: @escaping (Int) -> (widget: Widget, height: Int)?
    ) {
        guard
            let adapter = listView.as(AndroidKit.AdapterView.self)?
                .getAdapter()?
                .as(CustomListAdapter.self)
        else {
            // Reported, not swallowed. A list that quietly falls back to
            // holding every row looks identical to a lazy one until the row
            // count is large enough to matter, and by then the cause is far
            // from the symptom.
            // 回報，而非吞掉。一個「靜默退回持有每一列」的 list，在列數大到足以造成影響之前，
            // 看起來與一個懶載入的完全相同；而到那時，成因已離症狀很遠。
            log("lazy list rows: the list view has no CustomListAdapter")
            return
        }

        let density = AndroidBackend.density { listView.getResources().getDisplayMetrics().density }
        let rowProvider: LazyListRowSource.Provider = { row in
            guard let built = provider(row) else { return nil }
            // Points to pixels, the same conversion `setItems` does and the one
            // `setSize` uses -- rounded up, so a row's height agrees with the
            // size its own content was laid out at. A height that skipped it is
            // off by the display's scale, which on a phone is two or three --
            // rows would overlap by half their own height.
            // 由點換算為像素，與 `setItems` 所做、`setSize` 所用的換算相同——無條件進位，讓列高與其內容排版時的
            // 尺寸一致。少了這一步的高度會差一個顯示器縮放倍率，而在手機上那是二或三——列與列之間會重疊掉自身一半的高度。
            return (built.widget, Int(Self.layoutLength(built.height, density: density)))
        }

        // The source lives in the adapter (see `LazyListRowSource`): an update
        // replaces the provider in the box the adapter already holds.
        // 來源住在 adapter 裡(見 `LazyListRowSource`):更新時替換 adapter 已持有之箱子裡的 provider。
        let rows: SwiftObject
        if let existing = adapter.getLazyRows(),
            let source = existing.value() as? LazyListRowSource
        {
            source.provider = rowProvider
            rows = existing
        } else {
            rows = SwiftObject(LazyListRowSource(provider: rowProvider), environment: Self.env)
        }

        adapter.setLazy(
            rows,
            Int32(clamping: count),
            Self.layoutLength(estimatedRowHeight, density: density)
        )
    }
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.lists.SwiftRowRecycler",
    implements: AndroidKit.AbsListView.RecyclerListener.self
)
class SwiftRowRecycler: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ adapter: CustomListAdapter?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setAction(_ action: SwiftAction?)

    @JavaMethod
    func getWatch() -> SwiftObject?

    @JavaMethod
    func setWatch(_ watch: SwiftObject?)

    @JavaMethod
    func getLastReleasedPosition() -> Int32
}

/// The Swift side of a list's row-release handler, boxed and held by its
/// `SwiftRowRecycler` (`watch`), so it lives as long as the recycler and a
/// later commit replaces the handler in place.
///
/// 一個清單的「列釋放」handler 在 Swift 這一側的部分，裝箱後由它的 `SwiftRowRecycler`(`watch`)持有，
/// 因此壽命與 recycler 相同，而之後的 commit 原地替換 handler。
final class LazyRowReleaseWatch {
    var handler: (Int) -> Void

    init(handler: @escaping (Int) -> Void) {
        self.handler = handler
    }
}

extension AndroidBackend: BackendFeatures.LazyListRowLifetimes {
    /// **`AbsListView` already reports this.**
    /// `RecyclerListener.onMovedToScrapHeap` is the moment a row's view leaves
    /// the list, which is exactly what the framework needs in order to release
    /// the node it built for that row.
    ///
    /// The recycler is installed once and the handler replaced every time, for
    /// the reason every handler in this backend carries: `List` installs it on
    /// each commit, and a listener added per commit would allocate a Java object
    /// per frame while leaving every previous one attached. The adapter keeps
    /// the recycler (`rowRecycler`), so "installed once" is per list -- a table
    /// keyed by the adapter's transient Swift wrapper could not tell lists apart.
    ///
    /// **`AbsListView` 本來就會回報這件事。**
    /// `RecyclerListener.onMovedToScrapHeap` 正是「某一列的 view 離開這個清單」的那一刻,
    /// 而那恰好是框架釋放它為該列所建節點所需要的東西。
    ///
    /// recycler 只安裝一次、handler 每次都替換,理由與本 backend 每一個 handler 所帶的相同:
    /// `List` 每次 commit 都會安裝它,而每次 commit 都加一個 listener,會每幀配置一個 Java 物件,
    /// 同時讓先前每一個都繼續掛著。recycler 由 adapter 保存(`rowRecycler`),所以「只安裝一次」是以清單為單位——
    /// 以 adapter 那個臨時 Swift 包裝物件為鍵的表分不出清單。
    public func setLazyRowReleaseHandler(
        ofSelectableListView listView: Widget,
        to handler: @escaping (Int) -> Void
    ) {
        guard
            let adapterView = listView.as(AndroidKit.AdapterView.self),
            let adapter = adapterView.getAdapter()?.as(CustomListAdapter.self),
            let absListView = listView.as(AndroidKit.AbsListView.self)
        else {
            log("lazy row lifetimes: the list view has no CustomListAdapter")
            return
        }

        if let existing = adapter.getRowRecycler(),
            let watch = existing.getWatch()?.value() as? LazyRowReleaseWatch
        {
            watch.handler = handler
            return
        }

        let recycler = SwiftRowRecycler(adapter, environment: Self.env)
        let watch = LazyRowReleaseWatch(handler: handler)
        recycler.setWatch(SwiftObject(watch, environment: Self.env))
        // The recycler through a Java weak reference: it holds this action. See
        // `JavaWeakReference`. 經由 Java 弱參照取得 recycler:它持有這個 action。見 `JavaWeakReference`。
        let weakRecycler = JavaWeakReference(recycler, environment: Self.env)
        recycler.setAction(
            SwiftAction(environment: Self.env) {
                MainActor.assumeIsolated {
                    guard let recycler = weakRecycler.get()?.as(SwiftRowRecycler.self) else {
                        return
                    }
                    let position = recycler.getLastReleasedPosition()
                    guard position >= 0 else { return }
                    watch.handler(Int(position))
                }
            }
        )
        adapter.setRowRecycler(recycler)
        absListView.setRecyclerListener(
            recycler.as(AndroidKit.AbsListView.RecyclerListener.self)
        )
    }
}
