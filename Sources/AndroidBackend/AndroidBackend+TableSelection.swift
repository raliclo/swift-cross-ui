import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// The Swift side of a table's selection, held here because `SwiftAction` is a
/// `() -> Void` and cannot carry the row.
///
/// Same arrangement as `FocusHandlers`, and for the same two reasons. The
/// closure travelling to Java captures an id rather than the table, so the
/// registration survives `Table.commit` running again; and the handler is
/// swapped in place rather than re-registered, so one tap is reported once
/// however many times the table has been committed.
///
/// `nonisolated(unsafe)` on the same grounds that file gives: every access is
/// on the Android main thread -- registration from a commit, reporting from a
/// touch callback -- and the type is not reachable from anywhere else.
///
/// 表格選取在 Swift 這一側的部分,放在這裡是因為 `SwiftAction` 是一個 `() -> Void`,帶不動列號。
///
/// 與 `FocusHandlers` 是同一種安排,理由也是同樣那兩個。前往 Java 的那個 closure 捕捉的是一個 id
/// 而非那個表格,因此這次註冊能撐過 `Table.commit` 的再次執行;而 handler 是就地**替換**、不是重新
/// 註冊,因此無論這個表格被 commit 過多少次,一次點擊都只回報一次。
///
/// `nonisolated(unsafe)` 的理由與該檔案所給的相同:每一次存取都在 Android 主執行緒上——註冊來自
/// 一次 commit,回報來自一次觸控回呼——而這個型別在別處無從觸及。
enum TableSelectionHandlers {
    final class Watch {
        let table: TableContainer
        var handler: (Int?) -> Void

        init(table: TableContainer, handler: @escaping (Int?) -> Void) {
            self.table = table
            self.handler = handler
        }
    }

    nonisolated(unsafe) private static var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    static func register(
        table: TableContainer,
        handler: @escaping (Int?) -> Void,
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

    /// Reads back the row the tap landed on and reports it.
    ///
    /// -1 becomes `nil` here and nowhere else, so the sentinel does not travel
    /// any further into the framework than the boundary that needs it.
    /// 在此讀回那次點擊落在的列號並回報出去。
    ///
    /// -1 只在這裡變成 `nil`,因此那個哨兵值不會比「需要它的那道邊界」再往框架內部多走一步。
    static func report(id: Int32) {
        guard let watch = watches[id] else { return }
        let tapped = watch.table.getTappedRow()
        watch.handler(tapped < 0 ? nil : Int(tapped))
    }
}

extension AndroidBackend: BackendFeatures.TableSelection {
    /// **The touch listener is installed once; the handler is replaced every
    /// time.** `Table.commit` calls this on every commit, and a `SwiftAction`
    /// created per commit would allocate a Java object per frame and hand the
    /// table a new closure that captures state the previous one already had.
    /// The id is what makes the second call cheap: it finds the existing watch
    /// and swaps the closure inside it.
    ///
    /// **觸控 listener 只安裝一次,而 handler 每一次都替換。** `Table.commit` 每一次 commit 都會
    /// 呼叫這裡;每次 commit 都建一個 `SwiftAction`,會每幀配置一個 Java 物件,並交給那個表格一個
    /// 「捕捉了前一個早已持有之狀態」的新 closure。那個 id 正是讓第二次呼叫變便宜的東西:它找到既有的
    /// watch,把裡面的 closure 換掉。
    public func setSelectionHandler(
        ofTable table: Widget,
        to action: @escaping (_ selectedRow: Int?) -> Void
    ) {
        let container = table.as(TableContainer.self)!
        let key = ObjectIdentifier(table)
        let existing = Self.tableSelectionIDs[key]
        let id = TableSelectionHandlers.register(
            table: container,
            handler: action,
            reusing: existing
        )
        guard existing == nil else { return }
        Self.tableSelectionIDs[key] = id
        container.setSelectionAction(
            SwiftAction(environment: Self.env) {
                MainActor.assumeIsolated {
                    TableSelectionHandlers.report(id: id)
                }
            }
        )
    }

    public func setSelectedRow(ofTable table: Widget, to index: Int?) {
        table.as(TableContainer.self)!.setSelectedRow(Int32(index ?? -1))
    }

    nonisolated(unsafe) static var tableSelectionIDs: [ObjectIdentifier: Int32] = [:]
}
