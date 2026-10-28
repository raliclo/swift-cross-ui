import CGtk
import Foundation

/// A 2D affine transform, (a, b, c, d, tx, ty) in CSS `matrix()` order
/// (x' = a*x + c*y + tx, y' = b*x + d*y + ty), written as GSK and CSS steps
/// that every GTK renderer draws.
///
/// Why not a matrix: GTK files a transform by its *category*, and a matrix
/// handed over as a matrix -- `gsk_transform_matrix`, or CSS `matrix()` and
/// `skew()`, which GTK turns into `gsk_transform_matrix` -- is filed as
/// `GSK_TRANSFORM_CATEGORY_UNKNOWN`, whatever its contents. A chain takes the
/// lowest category of its steps. `GskCairoRenderer`, the software renderer,
/// draws a transform node only from `GSK_TRANSFORM_CATEGORY_2D` up; below that
/// it fills the node's bounds with rgb(255, 105, 180) and draws nothing of the
/// child (gsk_transform_node_draw, GTK 4.22). The GL renderer accepts any
/// category, which is why the same matrix rendered on the GPU and turned
/// hotpink on the software renderer.
///
/// Translation, `gsk_transform_rotate` and `gsk_transform_scale` are all filed
/// as 2D or better, and any 2D linear map is a rotation, an axis-aligned scale
/// and a second rotation (the 2x2 singular value decomposition), so every
/// affine transform can be written in steps the software renderer accepts. A
/// negative determinant comes out as a negative `scaleY`, which GSK files as
/// 2D affine; a singular matrix comes out as a zero scale, which every renderer
/// draws as nothing.
///
/// 一個 2D 仿射變換，以 CSS `matrix()` 的順序表示為 (a, b, c, d, tx, ty)
/// (x' = a*x + c*y + tx,y' = b*x + d*y + ty),並改寫成每一種 GTK renderer 都畫得出的 GSK 與 CSS 步驟。
///
/// 為何不用矩陣：GTK 依變換的「類別」歸檔，而以矩陣形式交出的矩陣——`gsk_transform_matrix`,或 GTK 會轉成
/// `gsk_transform_matrix` 的 CSS `matrix()` 與 `skew()`——不論內容為何都被歸為
/// `GSK_TRANSFORM_CATEGORY_UNKNOWN`。一串變換取其各步驟中最低的類別。軟體 renderer `GskCairoRenderer` 只繪製
/// 類別在 `GSK_TRANSFORM_CATEGORY_2D` 以上的 transform node;低於此者，它以 rgb(255, 105, 180) 填滿該節點的範圍，
/// 子節點的內容一概不畫(gsk_transform_node_draw,GTK 4.22)。GL renderer 接受任何類別，這就是同一個矩陣在 GPU
/// 上畫得出、在軟體 renderer 上卻變成 hotpink 的原因。
///
/// 平移、`gsk_transform_rotate` 與 `gsk_transform_scale` 都被歸為 2D 或更好的類別，而任何 2D 線性映射都可寫成
/// 一次旋轉、一次沿座標軸的縮放，再一次旋轉(2x2 的奇異值分解),因此每個仿射變換都能以軟體 renderer 接受的
/// 步驟寫出。行列式為負時會得到負的 `scaleY`,GSK 將之歸為 2D affine;奇異矩陣會得到零縮放，每一種 renderer 都
/// 將之畫成空無一物。
public struct AffineTransform2D: Equatable {
    /// The translation, applied last.
    /// 平移，最後套用。
    public var translationX: Double
    public var translationY: Double
    /// The rotation applied after the scale, in degrees, clockwise on screen.
    /// 縮放之後套用的旋轉，單位為度，在螢幕上為順時針。
    public var outerRotation: Double
    /// The axis-aligned scale.
    /// 沿座標軸的縮放。
    public var scaleX: Double
    public var scaleY: Double
    /// The rotation applied first, in degrees, clockwise on screen.
    /// 最先套用的旋轉，單位為度，在螢幕上為順時針。
    public var innerRotation: Double

    /// Decomposes the matrix (a, b, c, d, tx, ty), CSS `matrix()` order, into
    /// `translate * rotate(outer) * scale * rotate(inner)`.
    ///
    /// The common cases keep their own shape, so GSK sees what was meant and
    /// not an equivalent with rounding in it: no linear part is a translation
    /// alone, a diagonal matrix is a scale alone, and a uniform scale with a
    /// rotation is one rotation and one scale.
    ///
    /// 把矩陣 (a, b, c, d, tx, ty)(CSS `matrix()` 的順序)分解為
    /// `translate * rotate(outer) * scale * rotate(inner)`。
    ///
    /// 常見情況保留原本的形狀，讓 GSK 看到的是原意，而不是帶有捨入誤差的等價物：沒有線性部分時只有平移、對角
    /// 矩陣只有縮放、等比縮放加旋轉則是一次旋轉加一次縮放。
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        translationX = tx
        translationY = ty
        if b == 0 && c == 0 {
            outerRotation = 0
            scaleX = a
            scaleY = d
            innerRotation = 0
            return
        }
        // Closed-form 2x2 SVD: [a c; b d] = R(phi) * diag(q + r, q - r) * R(theta),
        // with R(t) = [cos t, -sin t; sin t, cos t].
        // 2x2 奇異值分解的封閉形式:[a c; b d] = R(phi) * diag(q + r, q - r) * R(theta),
        // 其中 R(t) = [cos t, -sin t; sin t, cos t]。
        let e = (a + d) / 2
        let f = (a - d) / 2
        let g = (b + c) / 2
        let h = (b - c) / 2
        let q = (e * e + h * h).squareRoot()
        let r = (f * f + g * g).squareRoot()
        let radiansToDegrees = 180 / Double.pi
        if r <= 1e-12 * max(q, 1) {
            // A similarity: a uniform scale q and one rotation.
            // 相似變換：等比縮放 q 與一次旋轉。
            outerRotation = atan2(h, e) * radiansToDegrees
            scaleX = q
            scaleY = q
            innerRotation = 0
            return
        }
        let a1 = atan2(g, f)
        let a2 = atan2(h, e)
        outerRotation = (a2 + a1) / 2 * radiansToDegrees
        scaleX = q + r
        scaleY = q - r
        innerRotation = (a2 - a1) / 2 * radiansToDegrees
    }

    /// Appends this transform to `next` and returns the result, which the
    /// caller owns. Takes ownership of `next`, as every `gsk_transform_*`
    /// builder does.
    ///
    /// 把此變換接在 `next` 之後並回傳結果，結果由呼叫端擁有。與每一個 `gsk_transform_*` 建構函式相同，
    /// 它會取得 `next` 的所有權。
    public func appending(to next: OpaquePointer?) -> OpaquePointer? {
        var transform = next
        if translationX != 0 || translationY != 0 {
            var point = graphene_point_t(x: Float(translationX), y: Float(translationY))
            transform = gsk_transform_translate(transform, &point)
        }
        if outerRotation != 0 {
            transform = gsk_transform_rotate(transform, Float(outerRotation))
        }
        if scaleX != 1 || scaleY != 1 {
            transform = gsk_transform_scale(transform, Float(scaleX), Float(scaleY))
        }
        if innerRotation != 0 {
            transform = gsk_transform_rotate(transform, Float(innerRotation))
        }
        return transform
    }

    /// The same steps as a CSS `transform` value, or `none` for the identity.
    /// `translate`, `rotate` and `scale` reach GSK as translate, 2D rotate and
    /// scale steps; `matrix()` and `skew()` would not (see the type's note).
    ///
    /// 同樣的步驟寫成 CSS `transform` 的值，identity 則為 `none`。`translate`、`rotate` 與 `scale` 到達 GSK 時
    /// 是平移、2D 旋轉與縮放步驟;`matrix()` 與 `skew()` 則不是(見本型別的說明)。
    public var cssValue: String {
        // Fixed-point: Swift prints small doubles in exponent form ("1e-05"),
        // which is not worth trusting to a CSS parser.
        // 定點表示:Swift 會把很小的 double 印成指數形式("1e-05"),不值得交給 CSS 解析器冒險。
        func number(_ value: Double) -> String { String(format: "%.6f", value) }
        var steps: [String] = []
        if translationX != 0 || translationY != 0 {
            steps.append("translate(\(number(translationX))px, \(number(translationY))px)")
        }
        if outerRotation != 0 {
            steps.append("rotate(\(number(outerRotation))deg)")
        }
        if scaleX != 1 || scaleY != 1 {
            steps.append("scale(\(number(scaleX)), \(number(scaleY)))")
        }
        if innerRotation != 0 {
            steps.append("rotate(\(number(innerRotation))deg)")
        }
        return steps.isEmpty ? "none" : steps.joined(separator: " ")
    }
}
