@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

/// Geometric effects, as an animation matrix on the container.
///
/// Android's coordinate space already has its origin at the top left with y
/// increasing downwards, and `Matrix` transforms about that origin rather than
/// about a centre anchor. So neither of the two conversions AppKitBackend needs
/// applies here: the incoming transform goes across as it stands. That is worth
/// stating rather than leaving as an absence, because the AppKit file spends
/// forty lines deriving those two conversions and their absence here looks like
/// an omission.
///
/// 幾何效果，實作為容器上的 animation matrix。
///
/// Android 的座標空間原點本來就在左上角、y 向下遞增，而 `Matrix` 是繞該原點而非繞中心錨點做變換。
/// 因此 AppKitBackend 所需的那兩次轉換在此都不適用：傳入的 transform 原樣送過去即可。這一點值得
/// 明說而非以「沒有」呈現，因為 AppKit 那個檔案花了四十行推導那兩次轉換，而此處它們的缺席看起來
/// 會像是漏掉了。
@JavaClass(
    "dev.swiftcrossui.androidbackend.GeometricEffectContainer",
    extends: AndroidKit.ViewGroup.self
)
class GeometricEffectContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setAffineTransform(
        _ scaleX: Float,
        _ skewX: Float,
        _ translateX: Float,
        _ skewY: Float,
        _ scaleY: Float,
        _ translateY: Float
    )

    @JavaMethod
    func clearAffineTransform()
}

extension AndroidBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = GeometricEffectContainer(Self.activity, environment: Self.env)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        guard let container = widget.as(GeometricEffectContainer.self) else { return }

        guard transform != .identity else {
            container.clearAffineTransform()
            return
        }

        // Read as GtkBackend and AppKitBackend read it: `linearTransform` is a
        // 2x2 stored row-major as (x y / z w), and the graphics frameworks take
        // its transpose, so the pairs are (m.x, m.z) and (m.y, m.w).
        // 讀法與 GtkBackend、AppKitBackend 相同：`linearTransform` 是以 row-major 儲存的 2x2 矩陣
        // (x y / z w)，而各圖形框架取其轉置，因此配對為 (m.x, m.z) 與 (m.y, m.w)。
        let m = transform.linearTransform
        let t = transform.translation

        // Only the translation is scaled by density. The linear part is a pure
        // ratio -- a scale of 1.6 is 1.6 on every screen -- while the
        // translation is a length in points and has to become pixels, the same
        // conversion `setSize` does.
        // 只有平移量需要乘上密度。線性部分是純比值——1.6 倍的縮放在任何螢幕上都是 1.6——而平移量是
        // 以點為單位的長度，必須換算為像素，與 `setSize` 所做的是同一種換算。
        let density = widget.getResources().getDisplayMetrics().density

        container.setAffineTransform(
            Float(m.x),
            Float(m.y),
            Float(t.x) * density,
            Float(m.z),
            Float(m.w),
            Float(t.y) * density
        )
    }
}
