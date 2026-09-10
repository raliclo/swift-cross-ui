import Foundation

/// A value that a ``DocumentGroup`` can read from and write to a file.
///
/// ```swift
/// struct TextFile: FileDocument {
///     static let readableContentTypes = [ContentType.plainText]
///     var text: String
///
///     init() { text = "" }
///     init(data: Data) throws { text = String(decoding: data, as: UTF8.self) }
///     func data() throws -> Data { Data(text.utf8) }
/// }
/// ```
///
/// **`Data` in and `Data` out, not a `URL`.** A document that read the file
/// itself would have to be told where the file is, would open it a second time,
/// and would have to answer what happens when the path moves under it. Handing
/// it the bytes puts every one of those questions in one place -- the scene --
/// and leaves the document a pure value, which is also what makes it testable
/// without a filesystem.
///
/// **Throwing on both sides.** A file that is not what it claims to be is the
/// ordinary case, not an exceptional one: a text document handed a JPEG, a
/// half-written file, a truncated download. `init(data:)` throwing lets the
/// scene report that to the user instead of the document inventing an empty
/// value, which would look like a file that opened and turned out to be blank.
///
/// 一個 ``DocumentGroup`` 能從檔案讀入、並寫回檔案的值。
///
/// **進來的是 `Data`、出去的也是 `Data`,不是 `URL`。** 一個自己去讀檔案的 document,必須被告知
/// 檔案在哪、會把它再開一次,而且必須回答「路徑在它腳下被移動了怎麼辦」。把位元組交給它,可以把上述
/// 每一個問題都收在同一個地方——也就是那個 scene——並讓 document 維持為一個純粹的值;而那也正是它
/// 能在沒有檔案系統的情況下被測試的原因。
///
/// **兩側都會 throw。** 「一個檔案並不是它所宣稱的東西」是常態、不是例外:一份被交給 JPEG 的文字
/// 文件、一個只寫到一半的檔案、一次被截斷的下載。讓 `init(data:)` 能 throw,scene 才能把那件事回報
/// 給使用者,而不是由 document 自行捏造一個空值——那看起來會像是「檔案開起來了,而它剛好是空的」。
public protocol FileDocument {
    /// The content types this document can be read from.
    /// 這個 document 可以從哪些內容型別讀入。
    static var readableContentTypes: [ContentType] { get }

    /// The content types this document can be written to.
    ///
    /// Defaults to ``readableContentTypes``, which is what an app that reads and
    /// writes the same format wants and is therefore what it should not have to
    /// say twice.
    /// 這個 document 可以寫成哪些內容型別。
    ///
    /// 預設與 ``readableContentTypes`` 相同——那正是「讀寫同一種格式」的 app 所要的，因此它不應該
    /// 需要說第二遍。
    static var writableContentTypes: [ContentType] { get }

    /// Creates an empty document, for "New".
    /// 建立一份空文件，供「新增」使用。
    init()

    /// Creates a document from a file's contents.
    /// 從一個檔案的內容建立文件。
    init(data: Data) throws

    /// The bytes to write to the file.
    /// 要寫入檔案的位元組。
    func data() throws -> Data
}

extension FileDocument {
    public static var writableContentTypes: [ContentType] { readableContentTypes }
}
