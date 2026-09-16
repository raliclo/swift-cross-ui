import AppKit

@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.TableColumnSorting {
    /// **AppKit already draws sortable headers; it just has to be told which
    /// columns are sortable.** Giving a column a `sortDescriptorPrototype` is
    /// what makes its header clickable, gives it the pressed appearance, draws
    /// the triangle, and flips the direction on a second click -- none of which
    /// this backend has to implement. That is why `TableColumnSorting` is
    /// separate from `TableSelection` in the first place: here sorting is
    /// nearly free and selection had to be switched on, and a backend whose
    /// headers are plain labels has exactly the reverse problem.
    ///
    /// **The prototypes are set on every commit, not once.** `setColumnLabels`
    /// builds fresh `NSTableColumn` objects each commit, so a prototype set at
    /// creation time would be attached to columns that have since been thrown
    /// away -- the headers would stop responding after the first update, which
    /// reads as "sorting broke when the data changed" rather than as a lifetime
    /// mistake.
    ///
    /// The key is the column index as a string. `NSSortDescriptor` is built for
    /// key-value coding against model objects and this table has no model
    /// object, so the key is used purely as a label to read back -- stated
    /// because a key that looks like a property name would invite someone to
    /// make it one.
    ///
    /// **AppKit 本來就會畫可排序的標題,只是必須被告知哪些欄位可以排序。** 給一個欄位設定
    /// `sortDescriptorPrototype`,就是讓它的標題可被點擊、具有按下的外觀、畫出那個三角形,並在第二次
    /// 點擊時翻轉方向的東西——這些沒有一項需要本 backend 自己實作。那正是 `TableColumnSorting`
    /// 一開始就與 `TableSelection` 分開的理由:在這裡排序近乎免費、而選取必須被明確開啟;
    /// 而一個標題只是純 label 的 backend,情況恰好相反。
    ///
    /// **prototype 每次 commit 都要設,不是只設一次。** `setColumnLabels` 每次 commit 都會建出全新的
    /// `NSTableColumn` 物件,因此在建立時設定的 prototype 會附在「其後已被丟棄」的那些欄位上——
    /// 標題會在第一次更新之後停止反應,而那讀起來像是「資料一變排序就壞了」,不像是一個生命期錯誤。
    ///
    /// 那把 key 是以字串寫下的欄位索引。`NSSortDescriptor` 是為了對 model 物件做 key-value coding
    /// 而設計的,而本表格沒有任何 model 物件,因此這把 key 純粹被當成一個「之後讀回來」的標籤——
    /// 此處寫明,因為一把長得像屬性名稱的 key,會引誘人真的把它變成一個屬性。
    public func setSortHandler(
        ofTable table: Widget,
        to action: @escaping (_ column: Int) -> Void
    ) {
        let table = (table as! NSScrollView).documentView as! NSCustomTableView
        table.customDelegate.sortHandler = action
        for (index, column) in table.tableColumns.enumerated() {
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: String(index),
                ascending: true
            )
        }
    }

    public func setSortIndicator(ofTable table: Widget, column: Int?, ascending: Bool) {
        let table = (table as! NSScrollView).documentView as! NSCustomTableView

        let descriptors: [NSSortDescriptor] =
            column.map { [NSSortDescriptor(key: String($0), ascending: ascending)] } ?? []

        // Compared on key and direction, not with `==` on the descriptors.
        // `NSSortDescriptor` does not promise value equality, so comparing the
        // arrays would be an identity test that never matches -- the guard
        // would be dead code that reads like a working one, and the header row
        // would be repainted on every commit of every unrelated change.
        // 以 key 與方向比較,而不是對那些 descriptor 用 `==`。`NSSortDescriptor` 並未承諾值相等性,
        // 因此比較那兩個陣列會是一次永遠不相符的身分比對——那個防護會變成一段「讀起來像在運作」的
        // 死碼,而標題列會在每一個不相干的改變的每一次 commit 被重繪。
        let existing = table.sortDescriptors.first.map { ($0.key ?? "", $0.ascending) }
        let wanted = column.map { (String($0), ascending) }
        guard existing?.0 != wanted?.0 || existing?.1 != wanted?.1 else { return }

        // The flag has to WRAP the assignment rather than be cleared on the
        // next runloop turn, because `sortDescriptorsDidChange` is delivered
        // synchronously from inside this line.
        // 這個旗標必須**包住**這次賦值,不能等到下一個 runloop 回合才清掉,因為
        // `sortDescriptorsDidChange` 是從這一行之內同步送達的。
        table.customDelegate.isApplyingFrameworkChange = true
        table.sortDescriptors = descriptors
        table.customDelegate.isApplyingFrameworkChange = false
    }
}
