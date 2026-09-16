import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// The Swift side of a table's sort handler, held here because `SwiftAction`
/// is a `() -> Void` and cannot carry the column.
///
/// Same arrangement as `TableSelectionHandlers`, deliberately duplicated rather
/// than merged with it: the two channels are separate protocols, and a table
/// that implemented one and not the other would otherwise share a registration
/// whose other half is never filled in.
///
/// **What is NOT here is the toggle rule.** An earlier version of this file
/// kept the current sort order so it could work out what a second tap on the
/// same header meant. The published protocol reports the column and lets
/// ``TableSortOrder/toggled(byClicking:)`` decide once, in the framework -- so
/// the rule exists in one place rather than once per backend that had to
/// hand-roll its header.
///
/// 表格排序 handler 在 Swift 這一側的部分,放在這裡是因為 `SwiftAction` 是一個 `() -> Void`,
/// 帶不動欄位索引。
///
/// 與 `TableSelectionHandlers` 是同一種安排,而且是刻意重複、沒有與它合併:那兩條通道是分開的協定,
/// 一個只實作其中之一的表格,否則會共用一份「另一半永遠填不上」的註冊。
///
/// **不在這裡的,是那條切換規則。** 本檔較早的版本會保存當下的排序狀態,好算出「在同一個標題上點
/// 第二次」代表什麼。已發布的協定回報的是欄位,並讓 ``TableSortOrder/toggled(byClicking:)``
/// 在框架裡決定一次——於是那條規則只存在於一個地方,而不是「每一個必須自行實作標題的 backend 各一份」。
enum TableSortHandlers {
    final class Watch {
        let table: TableContainer
        var handler: (Int) -> Void

        init(table: TableContainer, handler: @escaping (Int) -> Void) {
            self.table = table
            self.handler = handler
        }
    }

    nonisolated(unsafe) private static var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    static func register(
        table: TableContainer,
        handler: @escaping (Int) -> Void,
        reusing existing: Int32?
    ) -> Int32 {
        if let existing, let watch = watches[existing] {
            watch.handler = handler
            return existing
        }
        let id = nextID
        nextID += 1
        watches[id] = Watch(table: table, handler: handler)
        return id
    }

    /// Reads back which header was tapped and reports it.
    ///
    /// A tap that hit no column reports nothing rather than column 0: the
    /// sentinel crosses JNI because a Java signature has no `Int?`, and turning
    /// it into a real column here would sort by the first column every time a
    /// tap landed in a table with no headers yet.
    /// 讀回哪一個標題被點了,並回報出去。
    ///
    /// 一次沒有打中任何欄位的點擊,回報的是「什麼都不回報」,而不是第 0 欄:那個哨兵值之所以要穿過
    /// JNI,是因為 Java 簽章裡沒有 `Int?`;而在此把它變成一個真的欄位,會讓「在一個還沒有標題的表格上
    /// 落下的每一次點擊」都依第一欄排序。
    static func report(id: Int32) {
        guard let watch = watches[id] else { return }
        let tapped = watch.table.getTappedColumn()
        guard tapped >= 0 else { return }
        watch.handler(Int(tapped))
    }
}

extension AndroidBackend: BackendFeatures.TableColumnSorting {
    /// The touch listener is installed once and the handler replaced every
    /// time, for the reasons `setSelectionHandler` gives.
    /// 觸控 listener 只安裝一次、handler 每次都替換,理由見 `setSelectionHandler`。
    public func setSortHandler(
        ofTable table: Widget,
        to action: @escaping (_ column: Int) -> Void
    ) {
        let container = table.as(TableContainer.self)!
        let key = ObjectIdentifier(table)
        let existing = Self.tableSortIDs[key]
        let id = TableSortHandlers.register(
            table: container,
            handler: action,
            reusing: existing
        )
        guard existing == nil else { return }
        Self.tableSortIDs[key] = id
        container.setSortAction(
            SwiftAction(environment: Self.env) {
                MainActor.assumeIsolated {
                    TableSortHandlers.report(id: id)
                }
            }
        )
    }

    public func setSortIndicator(ofTable table: Widget, column: Int?, ascending: Bool) {
        let container = table.as(TableContainer.self)!
        container.setSortedColumn(Int32(column ?? -1))
        container.setSortAscending(ascending)
    }

    nonisolated(unsafe) static var tableSortIDs: [ObjectIdentifier: Int32] = [:]
}
