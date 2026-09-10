import Foundation

/// Opens a new, empty document in its own window.
@MainActor
public struct NewDocumentAction {
    let environment: EnvironmentValues

    public func callAsFunction() {
        guard let newDocument = environment.documentRegistry.newDocument else {
            // Warned rather than ignored, for the reason `openSettings` warns:
            // a menu item that changes nothing on screen reads like a broken
            // menu item, and only the app's author can tell that apart from an
            // app that declares no `DocumentGroup`.
            // 發出警告而非忽略，理由與 `openSettings` 相同：一個「畫面毫無變化」的選單項目讀起來
            // 像是壞掉的選單項目，而只有 app 的作者分辨得出它與「一個沒有宣告 `DocumentGroup` 的
            // app」的差別。
            logger.warning(
                "newDocument() called but no 'DocumentGroup' scene is in the app's body"
            )
            return
        }
        newDocument()
    }
}

/// Opens an existing document in its own window.
@MainActor
public struct OpenDocumentAction {
    let environment: EnvironmentValues

    /// Opens the file at this URL.
    ///
    /// Takes a URL rather than presenting the dialog itself. Choosing a file and
    /// opening one are separate acts: an app that restores its last session, or
    /// opens a file handed to it by the system, has a URL and no dialog to show
    /// -- and `presentSingleFileOpenDialog` is already the piece that asks.
    ///
    /// 收下一個 URL，而不是自己去呈現對話框。「選一個檔案」與「開啟一個檔案」是兩件事：一個會還原
    /// 上次工作階段、或開啟系統交給它的檔案的 app，手上有 URL 而沒有對話框要顯示——而
    /// `presentSingleFileOpenDialog` 本來就是負責「詢問」的那一塊。
    public func callAsFunction(_ url: URL) {
        guard let openDocument = environment.documentRegistry.openDocument else {
            logger.warning(
                "openDocument(_:) called but no 'DocumentGroup' scene is in the app's body",
                metadata: ["url": "\(url.path)"]
            )
            return
        }
        openDocument(url)
    }
}
