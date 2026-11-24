import AppKit
import SwiftCrossUI

// zIndex: each child's layer gets its rank in the drawing order as its
// `zPosition`, which Core Animation sorts sibling layers by; the subviews array
// keeps declaration order, so indices still mean what the layout system says.
// `AppKitHitTestingContainer` asks children in the same order, highest first,
// so what is drawn on top is what is clicked.
//
// zIndex:每個子元件的 layer 以它在繪製順序中的名次作為 `zPosition`,Core Animation 依此排序兄弟 layer;
// subviews 陣列維持宣告順序，所以索引仍是版面系統所說的意思。`AppKitHitTestingContainer` 以相同順序
// (最高者先)詢問子元件，所以畫在最上面的就是被點到的。
extension AppKitBackend: BackendFeatures.ZIndices {
    public func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?) {
        let children = container.subviews
        guard let order, order.count == children.count else {
            for child in children where (child.layer?.zPosition ?? 0) != 0 {
                child.layer?.zPosition = 0
            }
            return
        }
        container.wantsLayer = true
        for (rank, index) in order.enumerated() {
            let child = children[index]
            child.wantsLayer = true
            if child.layer?.zPosition != CGFloat(rank) {
                child.layer?.zPosition = CGFloat(rank)
            }
        }
    }
}

extension NSView {
    /// Subviews in the order a point should be offered to them: the one drawn
    /// on top first. That is reverse index order unless a `zIndex` has given a
    /// layer a `zPosition`, and then the highest `zPosition` first.
    ///
    /// 一個點應該交給 subview 的順序：畫在最上面的先。除非 `zIndex` 給了某個 layer `zPosition`,否則就是
    /// 索引的反序;有的話則是 `zPosition` 最高者先。
    var subviewsFrontToBack: [NSView] {
        let reversed = Array(subviews.reversed())
        guard reversed.contains(where: { ($0.layer?.zPosition ?? 0) != 0 }) else { return reversed }
        return reversed.enumerated().sorted { a, b in
            let za = a.element.layer?.zPosition ?? 0
            let zb = b.element.layer?.zPosition ?? 0
            return za != zb ? za > zb : a.offset < b.offset
        }.map(\.element)
    }
}
