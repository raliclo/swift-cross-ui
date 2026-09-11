import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.LazyListRows {
    /// Points the table at the framework instead of at an array.
    ///
    /// **`NSTableView` was already asking per row** -- `tableView(_:viewFor:row:)`
    /// -- and the delegate answered from a `widgets` array that had every row in
    /// it. This changes what that answer reads from, and nothing else about the
    /// table.
    ///
    /// `reloadData` at the end because the count may have changed, and because a
    /// table holding views from the previous provider would otherwise keep
    /// showing them.
    ///
    /// 讓這個表格改去問框架，而不是去問一個陣列。
    ///
    /// **`NSTableView` 本來就是逐列詢問的**——`tableView(_:viewFor:row:)`——而那個 delegate 是從一個
    /// 裝著每一列的 `widgets` 陣列裡回答。這裡改變的是「那個答案從哪裡讀」，表格的其餘一切不變。
    ///
    /// 最後呼叫 `reloadData`，因為列數可能已經改變;也因為一個仍持有前一個 provider 所產出 view 的
    /// 表格，否則會繼續顯示它們。
    public func setLazyRows(
        ofSelectableListView listView: Widget,
        count: Int,
        estimatedRowHeight: Int,
        provider: @escaping (Int) -> (widget: Widget, height: Int)?
    ) {
        let table = (listView as! NSScrollView).documentView as! NSCustomTableView
        let delegate = table.customDelegate
        delegate.lazyProvider = provider
        delegate.estimatedRowHeight = max(1, estimatedRowHeight)
        delegate.rowCount = count
        delegate.columnCount = 1
        // Cleared, not left behind: the eager array and the provider are two
        // answers to the same question, and a delegate holding both would answer
        // with whichever branch was read first.
        // 清空而不是留著:那個 eager 陣列與這個 provider 是同一個問題的兩個答案，而一個同時持有兩者的
        // delegate，會用「先被讀到的那個分支」來回答。
        delegate.widgets = []
        delegate.rowHeights = []
        if delegate.knownRowHeights.count > count {
            delegate.knownRowHeights = delegate.knownRowHeights.filter { $0.key < count }
        }
        table.reloadData()
    }
}
