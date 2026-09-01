import AppKit

@_spi(Backends) import SwiftCrossUI

/// Geometric effects, as a `CATransform3D` on a layer-backed container.
///
/// Two frames of reference have to be reconciled, and neither is optional.
///
/// The transform arrives in the widget's own space with the origin at its **top
/// left and y increasing downwards** -- the protocol says so, and GtkBackend
/// makes the same assumption explicit by setting `transform-origin: 0px 0px`
/// beside its `matrix(...)`. A CALayer under a non-flipped NSView works in a
/// space whose origin is the **bottom left with y increasing upwards**, and it
/// applies its transform about `anchorPoint`, which is the layer's centre by
/// default.
///
/// So the incoming matrix is converted twice, and the arithmetic is written out
/// below rather than left to be re-derived. Getting either conversion wrong
/// produces a transform that is visibly *a* transform -- so it does not look
/// like a failure -- and is wrong by a reflection or by half the view's size.
///
/// 幾何效果，實作為 layer-backed 容器上的 `CATransform3D`。
///
/// 有兩個座標系必須調和，兩者都無法迴避。
///
/// 傳入的 transform 位於該 widget 自身的空間中，原點在**左上角、y 向下遞增**——protocol 明文如此，
/// 而 GtkBackend 也在其 `matrix(...)` 旁設定 `transform-origin: 0px 0px`，把同一個假設寫明。
/// 位於未翻轉 NSView 之下的 CALayer，其座標空間原點在**左下角、y 向上遞增**，且它是繞著
/// `anchorPoint` 套用 transform，而該錨點預設為 layer 的中心。
///
/// 因此傳入的矩陣要轉換兩次，且推導過程寫在下方，而非留待日後重新推導。任一次轉換出錯，產生的都會是
/// 一個「看得出來是某種 transform」的結果——因此不會看起來像失敗——而它會差了一次鏡射，或差了 view
/// 尺寸的一半。
extension AppKitBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        // All four edges, so the child takes the container's size.
        //
        // Measured, after two wrong guesses. With no constraints at all the
        // cells were blank; with a left and top constraint they were still
        // blank, and the probe said why:
        //
        //     container=(0, 0, 200, 109)  child=(0, 109, 0, 0)  childConstraints=0
        //
        // The container is sized correctly and the child has no size at all.
        // ``VisualEffectModifier``'s commit sizes `widget`, which is this
        // container; nothing sizes what is inside it. That is invisible on
        // GtkBackend, where a container sizes its child for you, and it does not
        // arise in the ordinary case either, because there the layout system
        // owns both ends. A pass-through container inserted by a backend is the
        // one case with neither.
        //
        // Pinning all four edges makes the child follow the container, which is
        // what a pass-through means. It is safe here because the child arrives
        // with no size constraints of its own -- the probe above counted zero.
        //
        // 四個邊都釘住，讓子元件取得容器的尺寸。
        //
        // 這是量出來的，而且是在兩次猜錯之後。完全沒有約束時，各格是空白的；加上 left 與 top 約束
        // 之後仍然空白，而探測指出了原因（數值如上方英文所示）。
        //
        // 容器的尺寸是正確的，而子元件根本沒有尺寸。``VisualEffectModifier`` 的 commit 設定的是
        // `widget` 的尺寸，也就是這個容器；沒有任何東西為它內部的元件設定尺寸。這在 GtkBackend 上
        // 看不出來，因為那裡的容器會替你調整子元件的尺寸；在一般情況下也不會發生，因為版面系統同時
        // 掌握兩端。由 backend 插入的 pass-through 容器，正是兩者皆無的那個情況。
        //
        // 釘住四個邊會讓子元件跟隨容器，而那正是 pass-through 的意義。此處這麼做是安全的，因為子元件
        // 抵達時本身沒有任何尺寸約束——上述探測數到的是零。
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.wantsLayer = true
        return container
    }

    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        widget.wantsLayer = true
        guard let layer = widget.layer else { return }

        guard transform != .identity else {
            layer.transform = CATransform3DIdentity
            return
        }

        // The linear part, read the way GtkBackend reads it.
        //
        // `AffineTransform.linearTransform` is a 2x2 stored row-major as
        // (x y / z w), and its own documentation says CoreGraphics takes the
        // transpose. GtkBackend writes `matrix(m.x, m.z, m.y, m.w, t.x, t.y)`
        // into CSS, whose `matrix(a, b, c, d, e, f)` is exactly
        // `CGAffineTransform(a:b:c:d:tx:ty:)`. So the mapping below is the same
        // one, spelled in CoreGraphics rather than in CSS.
        //
        // 線性部分的讀法與 GtkBackend 一致。
        //
        // `AffineTransform.linearTransform` 是以 row-major 儲存的 2x2 矩陣 (x y / z w)，而它自己
        // 的文件說明 CoreGraphics 取的是其轉置。GtkBackend 往 CSS 寫入
        // `matrix(m.x, m.z, m.y, m.w, t.x, t.y)`，而 CSS 的 `matrix(a, b, c, d, e, f)` 恰好就是
        // `CGAffineTransform(a:b:c:d:tx:ty:)`。因此下方的對應關係與其相同，只是改用 CoreGraphics
        // 的寫法而非 CSS。
        let m = transform.linearTransform
        let t = transform.translation
        let a = m.x
        let b = m.z
        let c = m.y
        let d = m.w
        let tx = t.x
        let ty = t.y

        // Step 1: flip the y axis.
        //
        // A point p in the layer's y-up space is F(p) in the incoming y-down
        // space, where F(x, y) = (x, h - y) and h is the widget's height. The
        // transform the layer must perform is therefore F o M o F.
        //
        // Working it through, with M written as
        //     x' = a·x + c·y + tx
        //     y' = b·x + d·y + ty
        // and applying F before and after:
        //     x'' =  a·x - c·y + (c·h + tx)
        //     y'' = -b·x + d·y + (h·(1 - d) - ty)
        //
        // 步驟 1：翻轉 y 軸。
        //
        // layer 的 y 向上空間中的點 p，在傳入的 y 向下空間中是 F(p)，其中 F(x, y) = (x, h - y)，
        // h 為該 widget 的高度。因此 layer 必須執行的 transform 是 F o M o F。
        //
        // 推導過程如上方英文所列。
        let h = Double(widget.bounds.height)
        let fa = a
        let fc = -c
        let ftx = c * h + tx
        let fb = -b
        let fd = d
        let fty = h * (1 - d) - ty

        // Step 2: move the origin from the layer's corner to its anchor point.
        //
        // CoreAnimation applies the transform about `anchorPoint`, so it
        // computes q = anchor + N(p - anchor) for the matrix N it is given. The
        // matrix derived above is about the layer's origin instead. Requiring
        // the two to agree for every p:
        //
        //     anchor + A·(p - anchor) + n = A·p + f
        //  =>                           n = f - anchor + A·anchor
        //
        // The linear part is unchanged; only the translation moves. `anchorPoint`
        // is left at its default centre rather than set to a corner, because a
        // layer-backed view has its layer's `position` and `bounds` rewritten
        // from the view's frame on every layout pass, and a moved anchor without
        // a matching position would displace the view itself.
        //
        // 步驟 2：把原點從 layer 的角落移到它的錨點。
        //
        // CoreAnimation 是繞著 `anchorPoint` 套用 transform，因此對於它所收到的矩陣 N，它計算的是
        // q = anchor + N(p - anchor)。而上一步推得的矩陣是繞 layer 原點的。要求兩者對每一個 p 都
        // 相等，即得上方英文所列的關係式。
        //
        // 線性部分不變，只有平移量改變。此處讓 `anchorPoint` 維持預設的中心而不改設為角落，因為
        // layer-backed view 的 layer，其 `position` 與 `bounds` 在每一次版面計算時都會由 view 的
        // frame 重寫；若移動了錨點卻沒有同步調整 position，會使該 view 本身位移。
        let anchorX = Double(widget.bounds.width) * Double(layer.anchorPoint.x)
        let anchorY = Double(widget.bounds.height) * Double(layer.anchorPoint.y)
        let nx = ftx - anchorX + (fa * anchorX + fc * anchorY)
        let ny = fty - anchorY + (fb * anchorX + fd * anchorY)

        let affine = CGAffineTransform(
            a: CGFloat(fa),
            b: CGFloat(fb),
            c: CGFloat(fc),
            d: CGFloat(fd),
            tx: CGFloat(nx),
            ty: CGFloat(ny)
        )

        // `layer.transform`, not `layer.setAffineTransform`. They are the same
        // for an affine value, but assigning the 3D form makes it obvious that
        // this replaces the whole transform rather than concatenating onto what
        // was there -- which is what the protocol requires, and what a backend
        // that concatenated would break on every view update.
        // 使用 `layer.transform` 而非 `layer.setAffineTransform`。對仿射值而言兩者等價，但指派 3D
        // 形式能清楚顯示這是「取代整個 transform」而非「串接到既有值之上」——那正是 protocol 的
        // 要求，也是「會串接的 backend」在每次 view 更新時都會壞掉的地方。
        layer.transform = CATransform3DMakeAffineTransform(affine)
    }
}
