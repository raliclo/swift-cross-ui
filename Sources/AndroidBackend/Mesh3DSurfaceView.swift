import AndroidKit
import SwiftJava

/// The Swift side of `Mesh3DSurfaceView.kt`.
///
/// Declared as extending `AndroidKit.View` rather than `GLSurfaceView`, which AndroidKit does not
/// bind: everything called from here is either a `View` method or one of this class's own, so the
/// nearest bound ancestor is enough and adding a binding for a class nothing else uses is not.
///
/// `Mesh3DSurfaceView.kt` 的 Swift 側。
///
/// 宣告為繼承 `AndroidKit.View` 而不是 `GLSurfaceView`——AndroidKit 沒有綁定後者:此處呼叫的一切,
/// 不是 `View` 的方法就是這個類別自己的,因此「最近的已綁定祖先」就夠了;而為一個其他地方都不用的類別
/// 新增綁定則不必要。
@JavaClass("dev.swiftcrossui.androidbackend.Mesh3DSurfaceView")
class Mesh3DSurfaceView: AndroidKit.View {
    @JavaMethod
    @_nonoverride convenience init(
        context: AndroidKit.Context?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setOnFrame(_ action: SwiftAction?)
    @JavaMethod func getFrameCount() -> Int32
    @JavaMethod func getRendererName() -> String
    @JavaMethod func getDrawableWidth() -> Int32
    @JavaMethod func getDrawableHeight() -> Int32
    @JavaMethod func setGeometry(
        _ vertices: [Float],
        _ indices: [Int16],
        _ meshStarts: [Int32],
        _ meshCounts: [Int32]
    )
    @JavaMethod func setMatrices(_ mvps: [Float], _ normals: [Float])
    @JavaMethod func setLight(_ x: Float, _ y: Float, _ z: Float)
    @JavaMethod func setBackground(_ r: Float, _ g: Float, _ b: Float, _ a: Float)
    @JavaMethod func redraw()
    /// Empty, not nil, when there is nothing to read. swift-java cannot express an optional
    /// primitive array across the boundary, and an empty array says the same thing without a
    /// second spelling of "no pixels".
    /// 沒有東西可讀時回傳**空陣列**而不是 nil。swift-java 無法在邊界上表達「可選的基本型別陣列」,
    /// 而一個空陣列說的是同一件事,且不必為「沒有像素」再發明第二種寫法。
    @JavaMethod func snapshotPixels() -> [Int8]
}
