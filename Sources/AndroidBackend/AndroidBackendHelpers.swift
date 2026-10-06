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

    @JavaMethod
    func setButtonColorScheme(_ button: AndroidKit.Button?, _ dark: Bool)

    @JavaMethod
    func canFloat(_ activity: Activity?) -> Bool

    @JavaMethod
    func setWindowFloating(_ activity: Activity?, _ floating: Bool) -> Bool

    @JavaMethod
    func setWindowBackground(_ activity: Activity?, _ dark: Bool)

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
    func stagingPathForSave(_ activity: Activity?, _ uriString: String, _ name: String)
        -> JavaString?

    /// nil on success, otherwise why it failed.
    @JavaMethod
    func openExternalUrl(_ activity: Activity?, _ urlString: String) -> JavaString?

    /// nil on success, otherwise why it failed.
    @JavaMethod
    func revealFile(_ activity: Activity?, _ path: String) -> JavaString?
}
