/// A content type corresponding to a specific file/data format.
public struct ContentType: Sendable {
    /// The HTML content type.
    /// Plain UTF-8 text.
    ///
    /// Added 2026-09-10 with ``FileDocument``: `html` was the only constant
    /// here, and a document type that every example and every first app uses
    /// should not have to be spelled out by hand.
    ///
    /// Both `text/plain` and the two extensions rather than one: a file saved
    /// as `.txt` and one saved as `.text` are the same thing to a user, and a
    /// dialog that accepted only the first would refuse a file it can open.
    /// 純 UTF-8 文字。
    ///
    /// 2026-09-10 與 ``FileDocument`` 一同加入：此處原本只有 `html`，而一個「每個範例與每個第一支
    /// app 都會用到」的文件型別，不應該還要由人手寫出來。
    ///
    /// 同時列出 `text/plain` 與兩個副檔名，而非只有一個：對使用者而言，存成 `.txt` 與存成 `.text`
    /// 是同一回事，而一個只接受前者的對話框，會拒絕一個它其實開得起來的檔案。
    public static let plainText = ContentType(
        name: "Plain text",
        mimeTypes: ["text/plain"],
        fileExtensions: ["txt", "text"]
    )

    public static let html = ContentType(
        name: "HTML",
        mimeTypes: ["text/html"],
        fileExtensions: ["html", "htm"]
    )

    /// The name of this content type.
    public var name: String
    /// An array of MIME types associated with this content type.
    public var mimeTypes: [String]
    /// An array of file extensions associated with this content type.
    public var fileExtensions: [String]

    /// Creates an instance of `ContentType`.
    ///
    /// - Parameters:
    ///   - name: The name of this content type.
    ///   - mimeTypes: An array of MIME types associated with this content type.
    ///   - fileExtensions: An array of file extensions associated with this
    ///     content type.
    public init(name: String, mimeTypes: [String], fileExtensions: [String]) {
        self.name = name
        self.mimeTypes = mimeTypes
        self.fileExtensions = fileExtensions
    }
}
