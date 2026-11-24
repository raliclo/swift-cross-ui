import SwiftCrossUI
import UIKit

// zIndex: each child's layer gets its rank in the drawing order as its
// `zPosition`, which Core Animation sorts sibling layers by. `childWidgets` and
// `subviews` keep declaration order, so indices still mean what the layout
// system says. `BaseViewWidget.hitTest` asks children in the same order,
// highest first, so what is drawn on top is what is touched.
//
// zIndex:每個子元件的 layer 以它在繪製順序中的名次作為 `zPosition`,Core Animation 依此排序兄弟 layer。
// `childWidgets` 與 `subviews` 維持宣告順序，所以索引仍是版面系統所說的意思。`BaseViewWidget.hitTest`
// 以相同順序(最高者先)詢問子元件，所以畫在最上面的就是被觸碰到的。
extension UIKitBackend: BackendFeatures.ZIndices {
    public func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?) {
        let children = container.childWidgets
        guard let order, order.count == children.count else {
            for child in children where child.view.layer.zPosition != 0 {
                child.view.layer.zPosition = 0
            }
            return
        }
        for (rank, index) in order.enumerated() {
            let layer = children[index].view.layer
            if layer.zPosition != CGFloat(rank) {
                layer.zPosition = CGFloat(rank)
            }
        }
    }
}

extension UIView {
    /// Subviews in the order a touch should be offered to them: the one drawn
    /// on top first. That is reverse index order unless a `zIndex` has given a
    /// layer a `zPosition`, and then the highest `zPosition` first.
    ///
    /// 觸控應該交給 subview 的順序：畫在最上面的先。除非 `zIndex` 給了某個 layer `zPosition`,否則就是
    /// 索引的反序;有的話則是 `zPosition` 最高者先。
    var subviewsFrontToBack: [UIView] {
        let reversed = Array(subviews.reversed())
        guard reversed.contains(where: { $0.layer.zPosition != 0 }) else { return reversed }
        return reversed.enumerated().sorted { a, b in
            let za = a.element.layer.zPosition
            let zb = b.element.layer.zPosition
            return za != zb ? za > zb : a.offset < b.offset
        }.map(\.element)
    }
}
