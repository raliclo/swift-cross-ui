import Gtk
import SwiftCrossUI

// zIndex: GTK draws and picks a widget's children in sibling order, so the
// siblings are rearranged and `Fixed.children` keeps declaration order; see
// `Fixed.setDrawingOrder`.
// zIndex:GTK 依兄弟順序繪製與挑選子元件，所以重排兄弟節點,`Fixed.children` 維持宣告順序;
// 見 `Fixed.setDrawingOrder`。
extension GtkBackend: BackendFeatures.ZIndices {
    public func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?) {
        (container as? Fixed)?.setDrawingOrder(order)
    }
}
