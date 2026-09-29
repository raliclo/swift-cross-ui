import AndroidKit
import Foundation
@_spi(Backends) import SwiftCrossUI

/// Handing a URL or a file to another app: `openURL` and `revealFile`.
///
/// Both were absent until 2026-09-30, so `openURL` and `revealFile` warned once
/// and did nothing on Android. Each is one Intent, started from the activity;
/// the helpers return nil on success and a sentence on failure, which is
/// thrown here as a `HandoffError` so a caller learns why rather than only
/// that it did not happen.
///
/// 把一個 URL 或一個檔案交給另一個 app：`openURL` 與 `revealFile`。2026-09-30 之前兩者都不存在，
/// 因此在 Android 上 `openURL` 與 `revealFile` 只會警告一次、什麼也不做。兩者各是一個從 activity
/// 啟動的 Intent；helper 成功時回傳 nil、失敗時回傳一句話，在此以 `HandoffError` 拋出，讓呼叫端知道
/// **為什麼**，而不只是「沒發生」。
/// Closing the window: the activity is the window on Android, so closing it is
/// `finish()`, which is also what the back gesture does to a root activity.
/// The close handler runs first, while the scene graph can still reach the
/// window it is about to release.
///
/// 關閉視窗：在 Android 上 activity 就是視窗，因此關閉它就是 `finish()`——這也是返回手勢對根
/// activity 所做的事。close handler 先執行，趁 scene graph 仍能觸及它即將釋放的視窗。
extension AndroidBackend: BackendFeatures.WindowClosing {
    public func setCloseHandler(ofWindow window: Window, to action: @escaping () -> Void) {
        Self.closeHandler = action
    }

    public func close(window: Window) {
        let handler = Self.closeHandler
        Self.closeHandler = nil
        handler?()
        Self.activity.finish()
    }
}

extension AndroidBackend: BackendFeatures.FileSaveDialogs {
    /// The system "create document" dialog, answered with a path a plain write
    /// can use -- see `AndroidBackendHelpers.stagingPathForSave` for why the
    /// content:// URI the dialog returns is not handed back as it is, and how
    /// what is written there reaches the document.
    ///
    /// 系統的「建立文件」對話框，回傳一個一般寫入就能使用的路徑——為何不直接交回對話框給的 content://
    /// URI，以及寫到那裡的內容如何抵達該文件，見 `AndroidBackendHelpers.stagingPathForSave`。
    public func showSaveDialog(
        fileDialogOptions: FileDialogOptions,
        saveDialogOptions: SaveDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<Foundation.URL>) -> Void
    ) {
        let name = saveDialogOptions.defaultFileName ?? "Untitled"
        Self.saveDialogCallback = { [helpers] uri in
            guard let uri,
                  let path = helpers.stagingPathForSave(Self.activity, uri, name)?.toString()
            else {
                handleResult(.cancelled)
                return
            }
            handleResult(.success(Foundation.URL(fileURLWithPath: path)))
        }
        helpers.launchSaveActivity(name)
    }
}

extension AndroidBackend: BackendFeatures.ExternalURLs, BackendFeatures.RevealFiles {
    public struct HandoffError: Error, CustomStringConvertible {
        public let description: String
    }

    public func openExternalURL(_ url: Foundation.URL) throws {
        if let failure = helpers.openExternalUrl(Self.activity, url.absoluteString) {
            throw HandoffError(description: failure.toString())
        }
    }

    /// Opens the system file manager at the file's folder. Files in storage
    /// private to an app throw: see `AndroidBackendHelpers.revealFile` for why
    /// no file manager can list them.
    ///
    /// 在檔案所在的資料夾開啟系統檔案管理員。位於 app 私有儲存區的檔案會拋出錯誤：沒有任何檔案管理員
    /// 能列出它們的理由，見 `AndroidBackendHelpers.revealFile`。
    public func revealFile(_ url: Foundation.URL) throws {
        if let failure = helpers.revealFile(Self.activity, url.path) {
            throw HandoffError(description: failure.toString())
        }
    }
}
