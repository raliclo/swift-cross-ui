import UIKit

@_spi(Backends) import SwiftCrossUI

extension UIKitBackend: BackendFeatures.TableColumnSorting {
    /// **Nothing here came from UIKit, which is the point of the protocol being
    /// separate.** AppKit gets sortable headers from one property on
    /// `NSTableColumn`; this table's headers are `UILabel`s laid out by hand,
    /// so the click, the toggle and the arrow are all `TableWidget`'s. A single
    /// protocol carrying sorting and selection together would have made "AppKit
    /// got both nearly free" and "UIKit had to build both" indistinguishable
    /// from the outside.
    ///
    /// The division of labour is the same as everywhere else here: the backend
    /// forwards and the widget owns the state.
    ///
    /// **此處沒有任何一樣東西是 UIKit 給的,而那正是這個協定獨立存在的意義。** AppKit 從
    /// `NSTableColumn` 上的一個屬性就得到可排序的標題;本表格的標題是手工排版的 `UILabel`,
    /// 因此點擊、切換與箭頭全都是 `TableWidget` 自己的。一個把排序與選取合在一起的協定,會讓
    /// 「AppKit 兩者幾乎都免費拿到」與「UIKit 兩者都得自己蓋」從外面看起來一模一樣。
    ///
    /// 分工與此處其他地方相同:backend 只負責轉交,狀態歸 widget 所有。
    public func setSortHandler(
        ofTable table: Widget,
        to action: @escaping (_ column: Int) -> Void
    ) {
        (table as! TableWidget).setSortHandler(action)
    }

    public func setSortIndicator(ofTable table: Widget, column: Int?, ascending: Bool) {
        (table as! TableWidget).setSortIndicator(column: column, ascending: ascending)
    }
}
