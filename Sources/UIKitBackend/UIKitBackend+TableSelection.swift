import UIKit

@_spi(Backends) import SwiftCrossUI

extension UIKitBackend: BackendFeatures.TableSelection {
    /// **UIKit's table here is not a `UITableView`, so none of this came for
    /// free.** `TableWidget` lays its cells out in `layoutSubviews` for the
    /// reason that file records -- the total width is not known when the cells
    /// arrive -- and a `UITableView` cannot be given a flat array of arbitrary
    /// widgets grouped by row without a cell class per shape. So selection is
    /// a highlight view behind the cells and a tap recogniser over them, both
    /// built in `TableWidget`.
    ///
    /// The division of labour matches AppKit's: the backend only forwards, and
    /// the widget owns the state. That keeps `Table.commit` calling the same
    /// two methods on every backend regardless of how much each had to build.
    ///
    /// **UIKit 在此的表格不是 `UITableView`,因此這些沒有一項是免費得來的。** `TableWidget`
    /// 在 `layoutSubviews` 中排列它的 cell,理由記在那個檔案裡——cell 抵達時總寬度尚未可知——
    /// 而 `UITableView` 無法在「不為每一種形狀各寫一個 cell 類別」的前提下,接受一個依列分組的
    /// 任意 widget 扁平陣列。因此選取是由「cell 後面的一個高亮 view」與「cell 上面的一個 tap
    /// recogniser」構成,兩者都建在 `TableWidget` 裡。
    ///
    /// 分工與 AppKit 一致:backend 只負責轉交,狀態歸 widget 所有。那讓 `Table.commit` 在每一個
    /// backend 上都呼叫同樣的兩個方法,無論各自底下得自己蓋多少東西。
    public func setSelectionHandler(
        ofTable table: Widget,
        to action: @escaping (_ selectedRow: Int?) -> Void
    ) {
        (table as! TableWidget).setSelectionHandler(action)
    }

    public func setSelectedRow(ofTable table: Widget, to index: Int?) {
        (table as! TableWidget).setSelectedRow(index)
    }
}
