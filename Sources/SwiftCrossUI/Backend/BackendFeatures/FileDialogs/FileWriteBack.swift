import Foundation

extension BackendFeatures {
    /// Backend methods for a file that stands in for a document elsewhere.
    ///
    /// A backend whose save dialog answers with something a plain write cannot
    /// reach hands back a local file instead and copies it on. On Android the
    /// dialog gives a content:// URI and the file is in the app's cache. Without
    /// this, `saveDocument()` reported success once the stand-in was written,
    /// while the copy to the document happened later and failed in logcat alone
    /// (todo.md, 2026-10-14). A backend whose dialog gives the real file does not
    /// adopt it.
    ///
    /// These are used by ``SaveDocumentAction``.
    ///
    /// 用於「代替別處文件的檔案」的 backend 方法。存檔對話框回傳的東西無法用一般寫入抵達時，backend 改交回一個
    /// 本機檔案，再把它複製過去。Android 的對話框給的是 content:// URI,該檔案在 app 的 cache 裡。沒有這一步時,
    /// `saveDocument()` 在代用檔寫完時就回報成功，而複製到文件發生在之後，失敗只出現在 logcat(todo.md,
    /// 2026-10-14)。對話框直接給真正檔案的 backend 不需要採用它。
    @MainActor
    public protocol FileWriteBack: Core {
        /// Copies a file just written to the document it stands in for, and
        /// returns when the document holds it.
        ///
        /// Does nothing for a file that stands in for nothing.
        ///
        /// 把剛寫完的檔案複製到它所代表的文件，文件確實存好後才返回。對不代表任何文件的檔案不做事。
        ///
        /// - Parameter url: The file that was written.
        /// - Throws: When the document could not be written.
        func commitWrite(to url: URL) throws
    }
}
