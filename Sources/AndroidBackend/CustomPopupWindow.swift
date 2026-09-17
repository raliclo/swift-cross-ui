import AndroidKit
import SwiftJava

/// Binding for `CustomPopupWindow.kt`.
///
/// The numbers match that file's constants: 0 platform, 1 top, 2 bottom,
/// 3 leading, 4 trailing. `AndroidBackend+Popover.swift` is the only place that
/// converts between them and ``SwiftCrossUI/Edge``.
///
/// `CustomPopupWindow.kt` 的綁定。
///
/// 這些數字與該檔的常數相同:0 平台自行決定、1 上、2 下、3 前緣、4 後緣。
/// 唯一在它們與 ``SwiftCrossUI/Edge`` 之間轉換的地方是 `AndroidBackend+Popover.swift`。
@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomPopupWindow",
    extends: AndroidKit.PopupWindow.self
)
public class CustomPopupWindow: AndroidKit.PopupWindow {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setPreferredEdge(_ value: Int32)

    @JavaMethod
    func getPreferredEdge() -> Int32

    /// The panel's colour, so the tail is drawn in it. See `CustomPopupWindow.kt`.
    /// 面板的顏色,好讓尾巴以它繪製。見 `CustomPopupWindow.kt`。
    @JavaMethod
    func setPanelColor(_ color: Int32, _ has: Bool)

    /// The side the panel will actually take, given the room around the anchor.
    /// 在錨點四周空間的條件下,面板實際會採取的那一側。
    @JavaMethod
    func resolveEdge(_ anchor: AndroidKit.View?, _ requested: Int32, _ arrowPx: Int32) -> Int32

    /// Draws the tail on the side facing the anchor and grows the popup to hold it.
    /// 在面向錨點的那一側畫出尾巴,並把 popup 放大以容納它。
    @JavaMethod
    func applyArrow(
        _ edge: Int32,
        _ arrowPx: Int32,
        _ anchorWidthPx: Int32,
        _ anchorHeightPx: Int32
    )
}
