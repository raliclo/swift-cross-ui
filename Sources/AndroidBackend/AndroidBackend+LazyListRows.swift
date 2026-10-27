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
        let id = LazyListProviders.register(
            { row in
                guard let built = provider(row) else { return nil }
                // Points to pixels, the same conversion `setItems` does. A
                // height that skipped it is off by the display's scale, which on
                // a phone is two or three -- rows would overlap by half their
                // own height.
                // 由點換算為像素，與 `setItems` 所做的換算相同。少了這一步的高度會差一個顯示器
                // 縮放倍率，而在手機上那是二或三——列與列之間會重疊掉自身一半的高度。
                return (built.widget, Int(Float(built.height) * density))
            },
            reusing: Self.lazyListIDs[ObjectIdentifier(adapter)]
        )
        Self.lazyListIDs[ObjectIdentifier(adapter)] = id

        adapter.setLazy(
            id,
            Int32(count),
            Int32(Float(estimatedRowHeight) * density)
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
    func getLastReleasedPosition() -> Int32
}

/// The Swift side of a list's row-release handler.
///
/// Same arrangement as `LazyListProviders`, and for the same reason:
/// `SwiftAction` is a `() -> Void`, so the position travels in the Java object
/// and the closure carries only an id.
///
/// 一個清單的「列釋放」handler 在 Swift 這一側的部分。
///
/// 與 `LazyListProviders` 是同一種安排,理由也相同:`SwiftAction` 是一個 `() -> Void`,
/// 因此那個位置留在 Java 物件裡,而 closure 只帶一個 id。
enum LazyRowReleaseHandlers {
    final class Watch {
        let recycler: SwiftRowRecycler
        var handler: (Int) -> Void

        init(recycler: SwiftRowRecycler, handler: @escaping (Int) -> Void) {
            self.recycler = recycler
            self.handler = handler
        }
    }

    nonisolated(unsafe) private static var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    static func register(
        recycler: SwiftRowRecycler,
        handler: @escaping (Int) -> Void,
        reusing existing: Int32?
    ) -> Int32 {
        if let existing, let watch = watches[existing] {
            watch.handler = handler
            return existing
        }
        let id = nextID
        nextID += 1
        watches[id] = Watch(recycler: recycler, handler: handler)
        return id
    }

    static func recycler(for id: Int32) -> SwiftRowRecycler? {
        watches[id]?.recycler
    }

    static func report(id: Int32) {
        guard let watch = watches[id] else { return }
        let position = watch.recycler.getLastReleasedPosition()
        guard position >= 0 else { return }
        watch.handler(Int(position))
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
    /// per frame while leaving every previous one attached.
    ///
    /// **`AbsListView` 本來就會回報這件事。**
    /// `RecyclerListener.onMovedToScrapHeap` 正是「某一列的 view 離開這個清單」的那一刻,
    /// 而那恰好是框架釋放它為該列所建節點所需要的東西。
    ///
    /// recycler 只安裝一次、handler 每次都替換,理由與本 backend 每一個 handler 所帶的相同:
    /// `List` 每次 commit 都會安裝它,而每次 commit 都加一個 listener,會每幀配置一個 Java 物件,
    /// 同時讓先前每一個都繼續掛著。
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

        let key = ObjectIdentifier(adapter)
        if let existing = Self.lazyReleaseIDs[key] {
            _ = LazyRowReleaseHandlers.register(
                recycler: LazyRowReleaseHandlers.recycler(for: existing)!,
                handler: handler,
                reusing: existing
            )
            return
        }

        let recycler = SwiftRowRecycler(adapter, environment: Self.env)
        let id = LazyRowReleaseHandlers.register(
            recycler: recycler,
            handler: handler,
            reusing: nil
        )
        Self.lazyReleaseIDs[key] = id
        recycler.setAction(
            SwiftAction(environment: Self.env) {
                MainActor.assumeIsolated {
                    LazyRowReleaseHandlers.report(id: id)
                }
            }
        )
        absListView.setRecyclerListener(
            recycler.as(AndroidKit.AbsListView.RecyclerListener.self)
        )
    }

    nonisolated(unsafe) static var lazyReleaseIDs: [ObjectIdentifier: Int32] = [:]
}
