import Foundation
import AndroidKit
import SwiftJava

@JavaClass("dev.swiftcrossui.androidbackend.AndroidBackendHelpers")
class AndroidBackendHelpers: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        environment: JNIEnvironment? = nil
    )

    /// Get the width of the window's usable safe area.
    @JavaMethod
    func getSafeWindowWidth(_ activity: Activity?) -> Int32

    /// Get the height of the window's usable safe area.
    @JavaMethod
    func getSafeWindowHeight(_ activity: Activity?) -> Int32

    @JavaMethod
    func getSafeAreaLeftInset(_ activity: Activity?) -> Int32

    @JavaMethod
    func getSafeAreaTopInset(_ activity: Activity?) -> Int32

    @JavaMethod
    func clearTextSizeCache()

    @JavaMethod
    func getLargeTextSize(_ activity: Activity?) -> Float

    @JavaMethod
    func getTitleTextSize(_ activity: Activity?) -> Float

    @JavaMethod
    func getMediumTextSize(_ activity: Activity?) -> Float

    @JavaMethod
    func getSmallTextSize(_ activity: Activity?) -> Float

    /// The theme's colorPrimary as a colour int, or 0 when the theme has none.
    @JavaMethod
    func getPrimaryColor(_ activity: Activity?) -> Int32

    /// The theme's colorError as a colour int, or 0 when the theme has none.
    @JavaMethod
    func getErrorColor(_ activity: Activity?) -> Int32

    /// See RootScrollHost.originDisplacement: x and y in pixels.
    @JavaMethod
    func rootScrollDisplacement(_ view: AndroidKit.View?) -> [Int32]

    /// See RootScrollHost.reveal: the pixels scrolled, x and y.
    @JavaMethod
    func rootScrollReveal(_ view: AndroidKit.View?, _ x: Int32, _ y: Int32) -> [Int32]

    /// The screen position, in pixels, of the middle of the first shown view whose
    /// text is `label`; empty when there is none. 第一個顯示中、文字為 `label` 的 view 中心的螢幕位置(像素);沒有時為空。
    @JavaMethod
    func centreOfLabel(_ activity: Activity?, _ label: String) -> [Int32]

    /// Tints a ToggleButton by its checked state.
    @JavaMethod
    func styleToggleButton(_ button: AndroidKit.ToggleButton?)

    /// Switch colours from the SwiftCrossUI scheme; see the Kotlin side.
    @JavaMethod
    func styleSwitch(_ switchView: AndroidKit.CompoundButton?, _ foreground: Int32, _ enabled: Bool)

    /// `.checkbox` as UIKitBackend draws it; see the Kotlin side. 與 UIKitBackend 相同的 `.checkbox`;見 Kotlin 端。
    @JavaMethod
    func styleCheckbox(_ checkBox: AndroidKit.CompoundButton?, _ foreground: Int32, _ enabled: Bool)

    /// A progress bar as UIKitBackend draws it; see the Kotlin side. 與 UIKitBackend 相同的進度條;見 Kotlin 端。
    @JavaMethod
    func styleProgressBar(_ bar: AndroidKit.ProgressBar?)

    /// Label colours for a button-style toggle; see the Kotlin side.
    @JavaMethod
    func applyToggleButtonTextColors(_ button: AndroidKit.ToggleButton?, _ enabled: Bool)

    /// `.listStyle(.sidebar)` on, or back to the default.
    @JavaMethod
    func setListSidebar(_ listView: AndroidKit.ListView?, _ sidebar: Bool, _ dark: Bool)

    @JavaMethod
    func styleSimpleButton(_ button: AndroidKit.Button?)

    @JavaMethod
    func canFloat(_ activity: Activity?) -> Bool

    @JavaMethod
    func setWindowFloating(_ activity: Activity?, _ floating: Bool) -> Bool

    @JavaMethod
    func setWindowBackground(_ activity: Activity?, _ dark: Bool)

    /// See AndroidBackendHelpers.kt. 見 AndroidBackendHelpers.kt。
    @JavaMethod
    func styleNavigationTitle(_ activity: Activity?, _ label: AndroidKit.TextView?)

    @JavaMethod
    func setHitTesting(_ view: AndroidKit.View?, _ allowsHitTesting: Bool)

    @JavaMethod
    func isNightMode(_ activity: Activity?) -> Bool

    @JavaMethod
    func getDeviceClass(_ activity: Activity?) -> Int16

    @JavaMethod
    func getTimeZoneIdentifier() -> JavaString?

    @JavaMethod
    func setWindowTitle(_ activity: Activity?, _ title: String)

    @JavaMethod
    func openWindow(
        _ from: Activity?,
        _ token: String,
        _ title: String,
        _ content: AndroidKit.View?,
        _ onClosed: SwiftAction?,
        _ onResized: SwiftAction?
    )

    @JavaMethod
    func closeWindow(_ token: String)

    @JavaMethod
    func windowActivity(_ token: String) -> Activity?

    @JavaMethod
    func setTitleOfWindow(_ token: String, _ title: String)

    /// The URL an intent carries, or `nil`. Through Kotlin because
    /// AndroidKit declares `Intent.getDataString()` as returning a
    /// non-optional `String`, and an intent with no data returns null.
    /// intent 所帶的 URL,或 `nil`。經由 Kotlin,因為 AndroidKit 把 `Intent.getDataString()` 宣告成回傳
    /// 非 optional 的 `String`,而沒有資料的 intent 回傳的是 null。
    @JavaMethod
    func getIntentDataString(_ intent: Intent?) -> JavaString?

    @JavaMethod
    func registerActivityResults(
        _ activity: FragmentActivity!,
        _ filesCallback: FilesActivityCallback!,
        _ folderCallback: FolderActivityCallback!,
    )

    @JavaMethod
    func launchFilesActivity(_ options: FilesActivityContract.Options!)

    @JavaMethod
    func launchFolderActivity(_ urlString: JavaString?)

    @JavaMethod
    func registerSaveResult(_ activity: FragmentActivity!, _ callback: FolderActivityCallback!)

    @JavaMethod
    func launchSaveActivity(_ defaultName: String)

    @JavaMethod
    func launchFilesActivityFrom(_ activity: Activity?, _ options: FilesActivityContract.Options!)

    @JavaMethod
    func launchFolderActivityFrom(_ activity: Activity?, _ urlString: JavaString?)

    @JavaMethod
    func launchSaveActivityFrom(_ activity: Activity?, _ defaultName: String)

    @JavaMethod
    func stagingPathForSave(_ activity: Activity?, _ uriString: String, _ name: String)
        -> JavaString?

    /// A file in the cache holding a copy of the document the open dialog returned,
    /// written back when the app saves over it; nil when it could not be read.
    /// 存放開檔對話框所回傳文件副本的 cache 檔案，app 存回它時會寫回原文件；讀不到時為 nil。
    @JavaMethod
    func stagingPathForOpen(_ activity: Activity?, _ uriString: String) -> JavaString?

    /// nil on success, otherwise why it failed.
    @JavaMethod
    func openExternalUrl(_ activity: Activity?, _ urlString: String) -> JavaString?

    /// nil on success, otherwise why it failed.
    @JavaMethod
    func revealFile(_ activity: Activity?, _ path: String) -> JavaString?
}
