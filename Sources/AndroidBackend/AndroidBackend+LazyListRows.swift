import AndroidKit
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.LazyListRows {
    /// Points the adapter at the framework instead of at an array.
    ///
    /// **`BaseAdapter` was already the right shape** -- `getCount`, `getView(position,...)` --
    /// and was being fed a complete array. This changes where `getView` reads
    /// from, through the two native methods `CustomListAdapter` gained for it.
    ///
    /// `ListView` recycles the row containers itself through `convertView`, so
    /// the AppKit and UIKit half of this work -- giving the recycled view an
    /// identifier -- has no counterpart here. The adapter already honours
    /// `convertView`.
    ///
    /// **NOT COMPILED HERE (2026-09-11)**: this machine's Android SDK modules
    /// are Swift 6.3.3 against a 6.4 compiler. What to check, in order: that the
    /// two `external fun` declarations bind to the `@JavaImplementation`
    /// methods (`MainRunLoopTickler.tickle` is the working precedent in this
    /// package), and that returning a `View?` across that boundary is allowed --
    /// the precedent returns an `Int`, which is the one difference.
    ///
    /// 讓 adapter 改去問框架，而不是去問一個陣列。
    ///
    /// **`BaseAdapter` 本來就是對的形狀**——`getCount`、`getView(position,...)`——只是一直被餵一個
    /// 完整的陣列。此處改變的是 `getView` 從哪裡讀，途徑是 `CustomListAdapter` 為此新增的那兩個
    /// native method。
    ///
    /// `ListView` 自己會透過 `convertView` 回收那些列容器，因此 AppKit 與 UIKit 那一半的工作
    /// ——給被回收的 view 一個識別碼——在此處沒有對應物。這個 adapter 本來就遵守 `convertView`。
    ///
    /// **此處未編譯(2026-09-11)**:這台機器的 Android SDK 模組是 Swift 6.3.3、而編譯器是 6.4。
    /// 依序要查的是:那兩個 `external fun` 宣告是否綁定到了那兩個 `@JavaImplementation` 方法
    /// (`MainRunLoopTickler.tickle` 是本套件中可運作的先例)，以及跨越該邊界回傳一個 `View?` 是否
    /// 被允許——先例回傳的是 `Int`，那是唯一的差別。
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
        else { return }

        let density = listView.getResources().getDisplayMetrics().density
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
