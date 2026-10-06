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

    /// What the `DocumentGroup`'s document can read: the
    /// `allowedContentTypes` for the open dialog that comes before this call.
    /// Until 2026-10-06 nothing carried these to a dialog, so an app had to
    /// repeat its document's types or offer every file.
    /// `DocumentGroup` 的文件能讀取的型別：在這個呼叫之前的那個開啟對話框所用的
    /// `allowedContentTypes`。2026-10-06 之前沒有東西把它們帶到對話框，app 只能重抄文件的型別或提供所有檔案。
    public var readableContentTypes: [ContentType] {
        environment.documentRegistry.readableContentTypes
    }

    /// What the document can write: the `allowedContentTypes` for a save dialog.
    /// 文件能寫出的型別：儲存對話框的 `allowedContentTypes`。
    public var writableContentTypes: [ContentType] {
        environment.documentRegistry.writableContentTypes
    }
}
/// One document window's file: where it is, what to call it, and how to write
/// it. Set by ``DocumentGroup`` on each document window's environment.
/// 一個文件視窗的檔案：它在哪裡、叫什麼、如何寫出。由 ``DocumentGroup`` 設定在每個文件視窗的 environment 上。
@MainActor
final class DocumentSaveStore {
    let url: () -> URL?
    let suggestedName: () -> String
    let writableContentTypes: [ContentType]
    let write: (URL) throws -> Void

    init(
        url: @escaping () -> URL?,
        suggestedName: @escaping () -> String,
        writableContentTypes: [ContentType],
        write: @escaping (URL) throws -> Void
    ) {
        self.url = url
        self.suggestedName = suggestedName
        self.writableContentTypes = writableContentTypes
        self.write = write
    }
}

/// Saves the document of the window this environment belongs to.
///
/// **Added 2026-10-06, because `DocumentGroup` said it did this and did not.**
/// Its documentation promised "writes them back through the save dialog";
/// nothing in the tree wrote a document anywhere. To the file it was opened
/// from, or -- untitled, or `saveAs: true` -- to wherever the save dialog
/// returns, offering the document's `writableContentTypes`. The window then
/// takes the file's name.
///
/// 儲存此 environment 所屬視窗的文件。**2026-10-06 加入，因為 `DocumentGroup` 說它做了這件事、卻沒有做。**
/// 它的文件承諾「經由儲存對話框寫回」;整棵樹裡沒有任何東西把文件寫到任何地方。存回它被開啟的檔案；未命名、
/// 或 `saveAs: true` 時，存到儲存對話框回傳的位置，並提供文件的 `writableContentTypes`。之後視窗改用該檔名。
@MainActor
public struct SaveDocumentAction {
    let environment: EnvironmentValues

    /// - Parameters:
    ///   - saveAs: Ask where to save even when the document has a file.
    ///   - initialDirectory: Where the save dialog starts, when one is shown.
    ///   - saveAs:即使文件已有檔案也詢問存檔位置。
    ///   - initialDirectory:顯示儲存對話框時，它從哪個目錄開始。
    /// - Returns: Whether the document was written. `false` when the dialog
    ///   was cancelled, when the write failed (logged), or outside a
    ///   document window (logged).
    /// - Returns:文件是否已寫出。對話框被取消、寫入失敗(有記錄)或不在文件視窗中(有記錄)時為 `false`。
    @discardableResult
    public func callAsFunction(saveAs: Bool = false, initialDirectory: URL? = nil) async -> Bool {
        guard let store = environment.documentSaveStore.wrappedValue else {
            logger.warning("saveDocument() called outside a DocumentGroup window")
            return false
        }
        var destination = saveAs ? nil : store.url()
        if destination == nil {
            destination = await environment.chooseFileSaveDestination(
                initialDirectory: initialDirectory,
                defaultFileName: store.suggestedName(),
                allowedContentTypes: store.writableContentTypes
            )
        }
        guard let destination else { return false }
        do {
            try store.write(destination)
            return true
        } catch {
            logger.warning(
                "could not save document",
                metadata: ["url": "\(destination.path)", "error": "\(error)"]
            )
            return false
        }
    }
}
