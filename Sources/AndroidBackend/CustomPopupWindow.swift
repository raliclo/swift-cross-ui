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
}
