import UIKit

@_spi(Backends) import SwiftCrossUI

/// Geometric effects, as a `CATransform3D` on the container's layer.
///
/// Simpler than the AppKit implementation by exactly one conversion. A UIKit
/// layer's coordinate space already has its origin at the top left with y
/// increasing downwards, which is the space the transform arrives in, so the
/// y-axis flip AppKit needs is absent here. The anchor-point correction is not:
/// CoreAnimation applies a layer's transform about `anchorPoint`, which is the
/// centre by default, and the incoming transform is about the widget's origin.
///
/// 幾何效果，實作為容器 layer 上的 `CATransform3D`。
///
/// 比 AppKit 的實作恰好少一次轉換。UIKit 的 layer 座標空間原點本來就在左上角、y 向下遞增，正是
/// transform 傳入時所在的空間，因此 AppKit 所需的 y 軸翻轉在此不存在。但錨點修正仍然需要：
/// CoreAnimation 是繞著 `anchorPoint`（預設為中心）套用 layer 的 transform，而傳入的 transform
/// 是繞該 widget 原點的。
///
/// ``BackendFeatures/VisualEffects`` is deliberately not implemented here. Six
/// of its seven effects need Core Image running over a live layer, and
/// `CALayer.filters` does not do that on iOS -- the property exists in the
/// header but Core Image does not take part in iOS layer compositing, so
/// assigning to it has no effect. A conformance that carried opacity and
/// silently dropped blur, saturation, brightness, contrast, grayscale and hue
/// would be worse than none, because it would also silence the warning that
/// tells an application which of its effects did nothing.
///
/// 此處刻意不實作 ``BackendFeatures/VisualEffects``。其七種效果中有六種需要 Core Image 作用於
/// 即時的 layer，而 `CALayer.filters` 在 iOS 上並不提供這件事——該屬性存在於標頭中，但 Core Image
/// 並不參與 iOS 的 layer 合成，因此對它賦值不會有任何效果。一個「帶著 opacity、卻靜默丟棄 blur、
/// saturation、brightness、contrast、grayscale 與 hue」的 conformance，會比完全不實作更糟，
/// 因為它同時也會讓「告知應用程式哪些效果沒有生效」的那則警告消失。
extension UIKitBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)

        // All four edges, so the child takes the container's size.
        //
        // ``GeometricEffectModifier``'s commit sizes the container it is given
        // and nothing sizes what is inside it. On AppKit that left the child at
        // zero by zero and every tile in P40 drew nothing; UIKit sizes widgets
        // through the same kind of constraint, so it has the same gap.
        //
        // 四個邊都釘住，讓子元件取得容器的尺寸。
        //
        // ``GeometricEffectModifier`` 的 commit 只設定它所拿到的那個容器的尺寸，沒有任何東西為
        // 容器內部的元件設定尺寸。在 AppKit 上，這使子元件停留在 0x0，P40 中每一塊都畫不出東西；
        // UIKit 以同一類約束來設定 widget 尺寸，因此存在同樣的缺口。
        let childView = child.view!
        let containerView = container.view!
        childView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            childView.topAnchor.constraint(equalTo: containerView.topAnchor),
            childView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        return container
    }

    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        let view = widget.view!
        let layer = view.layer

        guard transform != .identity else {
            layer.transform = CATransform3DIdentity
            return
        }

        // Read the same way GtkBackend and AppKitBackend read it:
        // `linearTransform` is a 2x2 stored row-major as (x y / z w), and
        // CoreGraphics takes the transpose, so `CGAffineTransform(a: m.x,
        // b: m.z, c: m.y, d: m.w, ...)`.
        // 讀法與 GtkBackend、AppKitBackend 相同：`linearTransform` 是以 row-major 儲存的 2x2 矩陣
        // (x y / z w)，而 CoreGraphics 取其轉置，因此對應為
        // `CGAffineTransform(a: m.x, b: m.z, c: m.y, d: m.w, ...)`。
        let m = transform.linearTransform
        let t = transform.translation
        let a = m.x
        let b = m.z
        let c = m.y
        let d = m.w

        // The anchor correction, and only that.
        //
        // CoreAnimation computes q = anchor + N(p - anchor) for the matrix N it
        // is handed, while the incoming transform is about the widget's origin.
        // Requiring the two to agree for every p leaves the linear part alone
        // and moves the translation:
        //
        //     n = t - anchor + A·anchor
        //
        // 只做錨點修正，別無其他。
        //
        // 對於它所收到的矩陣 N，CoreAnimation 計算的是 q = anchor + N(p - anchor)，而傳入的
        // transform 是繞該 widget 原點的。要求兩者對每一個 p 都相等，線性部分維持不變，僅平移量改變
        // （關係式如上）。
        let anchorX = Double(view.bounds.width) * Double(layer.anchorPoint.x)
        let anchorY = Double(view.bounds.height) * Double(layer.anchorPoint.y)
        let nx = t.x - anchorX + (a * anchorX + c * anchorY)
        let ny = t.y - anchorY + (b * anchorX + d * anchorY)

        let affine = CGAffineTransform(
            a: CGFloat(a),
            b: CGFloat(b),
            c: CGFloat(c),
            d: CGFloat(d),
            tx: CGFloat(nx),
            ty: CGFloat(ny)
        )
        layer.transform = CATransform3DMakeAffineTransform(affine)
    }
}
