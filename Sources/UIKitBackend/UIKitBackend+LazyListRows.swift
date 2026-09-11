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
