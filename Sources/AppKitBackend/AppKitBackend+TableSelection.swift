import AppKit

@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.TableSelection {
    /// The table and the selectable list are the same `NSTableView` subclass
    /// here, so the click path already existed -- `createTable` simply left it
    /// switched off.
    ///
    /// **`allowSelections` is turned on here rather than in `createTable`.**
    /// A table written without `selection:` must stay unselectable: a row that
    /// highlights under the pointer but reports to nothing is a control that
    /// looks live and is not. Turning it on at the moment a handler arrives
    /// means the highlight appears exactly when something is listening for it.
    ///
    /// 表格與可選取清單在此是同一個 `NSTableView` 子類別,因此點擊路徑本來就存在——
    /// `createTable` 只是把它關著。
    ///
    /// **`allowSelections` 在此開啟,而不是在 `createTable` 裡。** 一個沒有寫 `selection:` 的表格
    /// 必須維持不可選取:一個在指標下會高亮、卻不向任何人回報的列,是一個看起來活著、實際上不是的
    /// 控制項。在 handler 抵達的那一刻才開啟它,高亮才會恰好出現在「有人在聽」的時候。
    public func setSelectionHandler(
        ofTable table: Widget,
        to action: @escaping (_ selectedRow: Int?) -> Void
    ) {
        let table = (table as! NSScrollView).documentView as! NSCustomTableView
        table.customDelegate.allowSelections = true
        // Replaced, never appended to. `Table.commit` installs the handler on
        // every commit, and the protocol requires this to be a replacement --
        // a table that accumulated handlers would write the binding once per
        // frame that had ever been drawn.
        // 取代,絕不追加。`Table.commit` 在每一次 commit 都會安裝 handler,而協定要求這裡必須是
        // 一次取代——一個會累積 handler 的表格,每畫過一幀就會往 binding 多寫一次。
        table.customDelegate.tableSelectionHandler = action
    }

    public func setSelectedRow(ofTable table: Widget, to index: Int?) {
        let table = (table as! NSScrollView).documentView as! NSCustomTableView

        // Asynchronously, for the reason `setSelectedItem(ofSelectableListView:)`
        // gives: the data-reloading calls just made by `setCells` have not taken
        // effect yet, and they clear the selection when they do. A selection
        // written before that lands is a selection that disappears a moment
        // later, which reads on screen as "the framework cannot select a row".
        //
        // 非同步執行,理由與 `setSelectedItem(ofSelectableListView:)` 所給的相同:`setCells` 剛做出
        // 的那些資料重載呼叫尚未生效,而它們生效時會清掉選取。在那之前寫下的選取,會在片刻之後消失
        // ——在畫面上讀起來就是「框架選不動任何一列」。
        DispatchQueue.main.async {
            // Compared inside the block, not outside it. Read before the queued
            // reload settles, `selectedRow` is the value about to be discarded,
            // so an equality check out here would skip exactly the writes that
            // needed to happen.
            // 比較寫在 block 之內,不是之外。在排隊中的重載安定之前讀取,`selectedRow` 是那個
            // 即將被丟棄的值;因此把相等性檢查放在外面,會剛好略過那些**真正需要**發生的寫入。
            let current = table.selectedRow == -1 ? nil : table.selectedRow
            guard current != index else { return }
            table.selectRowIndexes(
                IndexSet([index].compactMap { $0 }),
                byExtendingSelection: false
            )
        }
    }
}
