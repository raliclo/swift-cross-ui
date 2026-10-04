import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.LazyListRows {
    /// Points the table at the framework instead of at an array.
    ///
    /// The same change as the AppKit half, against `UITableViewDataSource`
    /// rather than `NSTableViewDataSource`. iOS is the platform this matters
    /// most on: the measurement that started #117 phase 3 was 423 MB for ten
    /// thousand rows, and a phone does not have that to spare.
    ///
    /// 讓這個表格改去問框架，而不是去問一個陣列。
    ///
    /// 與 AppKit 那一半是同一個改動，只是對象是 `UITableViewDataSource` 而非
    /// `NSTableViewDataSource`。iOS 是這件事最要緊的平台:啟動 #117 phase 3 的那個量測是「一萬列
    /// 423 MB」，而一支手機沒有那麼多可以揮霍。
    public func setLazyRows(
        ofSelectableListView listView: Widget,
        count: Int,
        estimatedRowHeight: Int,
        provider: @escaping (Int) -> (widget: Widget, height: Int)?
    ) {
        let table = (listView as! WrapperWidget<UICustomTableView>).child
        let delegate = table.customDelegate

        // Same rows, new content: update the visible cells in place.
        //
        // `reloadData()` on every update made UIKit end and re-request every
        // visible cell, and each round trip released the row's node and built
        // it again. P57's readout ticks twice a second, so walking its 500 rows
        // took 343 reloads and 29,718 row builds on iOS against 403 on Android
        // (2026-10-04). When the count is unchanged, re-running the provider
        // for the visible rows refreshes their cached nodes without rebuilding
        // them, and UIKit is asked to re-measure only if a height changed.
        // 列不變、內容變：在原地更新可見的 cell。每次更新都 `reloadData()` 會讓 UIKit 結束並重新索取每一個
        // 可見 cell,而每一趟都會釋放該列的節點再重建。P57 的讀數每秒更新兩次，所以走完 500 列在 iOS 上花了
        // 343 次 reload、建立了 29,718 列，Android 只有 403 列(2026-10-04)。列數不變時，對可見列重跑 provider
        // 就能更新它們已快取的節點而不重建;只有列高改變時才請 UIKit 重新量測。
        if delegate.lazyProvider != nil, delegate.rowCount == count {
            delegate.lazyProvider = provider
            delegate.estimatedRowHeight = max(1, estimatedRowHeight)
            var heightsChanged = false
            for path in table.indexPathsForVisibleRows ?? [] {
                guard let built = provider(path.row),
                    let cell = table.cellForRow(at: path)
                else { continue }
                if delegate.knownRowHeights[path.row] != built.height {
                    delegate.knownRowHeights[path.row] = built.height
                    heightsChanged = true
                }
                if built.widget.view.superview !== cell.contentView {
                    for subview in cell.contentView.subviews {
                        subview.removeFromSuperview()
                    }
                    cell.contentView.addSubview(built.widget.view)
                }
            }
            if heightsChanged {
                table.beginUpdates()
                table.endUpdates()
            }
            return
        }

        delegate.lazyProvider = provider
        delegate.estimatedRowHeight = max(1, estimatedRowHeight)
        delegate.rowCount = count
        // Cleared, not left behind: two answers to the same question would be
        // resolved by whichever branch is read first.
        // 清空而不是留著:同一個問題的兩個答案，會由「先被讀到的那個分支」來決定。
        delegate.widgets = []
        delegate.rowHeights = []
        if delegate.knownRowHeights.count > count {
            delegate.knownRowHeights = delegate.knownRowHeights.filter { $0.key < count }
        }
        table.reloadData()
    }
}

extension UIKitBackend: BackendFeatures.LazyListRowLifetimes {
    /// **`UITableViewDelegate` already reports this; nothing had asked.**
    /// `didEndDisplaying` is the moment a cell stops showing a row, which is
    /// exactly what the framework needs in order to release the node it built
    /// for that row.
    ///
    /// Replaced, never appended to: `List` installs it on every commit.
    ///
    /// **`UITableViewDelegate` 本來就會回報這件事,只是先前沒有人問。** `didEndDisplaying` 正是
    /// 「一個 cell 不再顯示某一列」的那一刻,而那恰好是框架釋放它為該列所建節點所需要的東西。
    ///
    /// 取代、絕不追加:`List` 每次 commit 都會安裝它。
    public func setLazyRowReleaseHandler(
        ofSelectableListView listView: Widget,
        to handler: @escaping (Int) -> Void
    ) {
        let table = (listView as! WrapperWidget<UICustomTableView>).child
        table.customDelegate.lazyReleaseHandler = handler
    }
}
