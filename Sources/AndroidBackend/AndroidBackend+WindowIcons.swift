import AndroidKit
import Foundation
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `windowIcon(_:)` on Android: the icon of the window's task in Recents.
///
/// An Android window has no title-bar icon. The place a user sees an icon for a
/// running window is its task in Recents, which `Activity.setTaskDescription`
/// sets from a Bitmap; nil restores the app's launcher icon. The label in the same
/// description is the window's title, so both are built together in Kotlin
/// (ScuiWindowIcons) and neither a title nor an icon change drops the other.
///
/// Android 上的 `windowIcon(_:)`:視窗所屬 task 在「最近使用」中的圖示。Android 的視窗沒有標題列圖示，使用者看到執行中
/// 視窗圖示的地方是它在「最近使用」中的 task,由 `Activity.setTaskDescription` 以 Bitmap 設定;nil 恢復 app 的啟動器圖示。
/// 同一個 description 裡的標籤就是視窗標題，所以兩者在 Kotlin(ScuiWindowIcons)一起建立，改標題或改圖示都不會丟掉另一個。
extension AndroidBackend: BackendFeatures.WindowIcons {
    public func setIcon(ofWindow window: Window, to icon: URL?) {
        // An empty path, not nil, for the default icon: @JavaMethod takes no optional String. / 預設圖示用空字串而非 nil:@JavaMethod 不接受 optional String。
        let path = icon.map { $0.withUnsafeFileSystemRepresentation { String(cString: $0!) } } ?? ""
        if let token = window.token {
            helpers.setIconOfWindow(token, path)
        } else {
            helpers.setWindowIcon(Self.activity, path)
        }
    }

    /// The centre pixel (ARGB) of the task icon the system holds for the first
    /// window, read back from ActivityManager; 0 when the task has none of its own.
    /// For P118, which checks the icon on the platform rather than in the backend.
    /// 系統為第一個視窗的 task 所持有之圖示的中心像素(ARGB),讀自 ActivityManager;task 沒有自己的圖示時為 0。
    /// 給 P118 用：它在平台上檢查圖示，而不是在 backend 裡。
    public static func taskIconCentre() -> Int32 {
        AndroidBackendHelpers(environment: AndroidBackend.env).taskIconCentre(activity)
    }
}
