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
    /// **COMPILES HERE, since 2026-09-11.** It did not for a while, and the reason
    /// was never this file: the host toolchain was Swift 6.4 while the installed
    /// Android SDK was 6.3.3, so every Android build failed with module-format
    /// errors naming files nobody here wrote. `testapp/compile.zsh` now finds a
    /// matching toolchain and says which one it picked.
    ///
    /// Compiling is not running. Nothing in this file has been executed on a
    /// device or an emulator, and the checks below are still the checks.
    ///
    /// **自 2026-09-11 起，此處編得過。** 它曾有一段時間編不過，而理由從來不在這個檔案:主機的
    /// toolchain 是 Swift 6.4，而安裝的 Android SDK 是 6.3.3，因此每一次 Android 建置都以
    /// 「module 格式」錯誤失敗，指名的是一些此處沒有人寫過的檔案。`testapp/compile.zsh` 現在會找出
    /// 相符的 toolchain，並說出它選了哪一個。
    ///
    /// 編得過不等於跑得起來。本檔中沒有任何東西曾在裝置或模擬器上執行過，而下方那些要查的項目，
    /// 依然要查。
    ///
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
