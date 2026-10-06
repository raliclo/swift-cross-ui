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
    ///
    /// ``conformingFileExtensions`` is every extension that macOS 27.2 maps to
    /// a type conforming to `public.plain-text` (source code, scripts,
    /// Markdown, CSV, logs, ...), measured with
    /// `UTType(filenameExtension:)?.conforms(to: .plainText)` on 2026-10-07.
    /// AppKit and UIKit get this from the type tree; Windows and GTK match by
    /// extension only, so without the list they hid `also-text.swift` from a
    /// plain-text open dialog that macOS and iOS offered it in (P62).
    /// 純 UTF-8 文字。
    ///
    /// 2026-09-10 與 ``FileDocument`` 一同加入：此處原本只有 `html`，而一個「每個範例與每個第一支
    /// app 都會用到」的文件型別，不應該還要由人手寫出來。
    ///
    /// 同時列出 `text/plain` 與兩個副檔名，而非只有一個：對使用者而言，存成 `.txt` 與存成 `.text`
    /// 是同一回事，而一個只接受前者的對話框，會拒絕一個它其實開得起來的檔案。
    ///
    /// ``conformingFileExtensions`` 是 macOS 27.2 上對應到「從屬於 `public.plain-text`」之型別的
    /// 每一個副檔名(原始碼、腳本、Markdown、CSV、log……)，2026-10-07 以
    /// `UTType(filenameExtension:)?.conforms(to: .plainText)` 量得。AppKit 與 UIKit 由型別樹得到
    /// 這一點；Windows 與 GTK 只依副檔名比對，少了這份清單，純文字開檔對話框就會藏起 macOS 與 iOS
    /// 都會列出的 `also-text.swift`(P62)。
    public static let plainText = ContentType(
        name: "Plain text",
        mimeTypes: ["text/plain"],
        fileExtensions: ["txt", "text"],
        conformingFileExtensions: [
            "swift", "swiftinterface", "c", "h", "i", "cc", "cpp", "cxx", "c++",
            "ii", "hpp", "hh", "hxx", "ipp", "inl", "m", "mm", "mii", "s", "nasm",
            "py", "php", "phtml", "php3", "php4", "ph3", "ph4", "rb", "rbw", "pl",
            "pm", "js", "mjs", "javascript", "jscript", "tsx", "java", "jav",
            "sh", "zsh", "bash", "command", "csh", "ksh", "tcsh", "r",
            "applescript", "scpt", "md", "markdown", "csv", "tsv", "log", "sql",
            "fs", "glsl", "vert", "frag", "vsh", "fsh", "geom", "metal", "cl",
            "make", "mk", "mak", "diff", "patch", "f", "f77", "f90", "f95", "for",
            "ada", "adb", "ads", "pas", "l", "lm", "lmm", "y", "ym", "ymm", "exp",
            "xcconfig", "modulemap", "m3u", "m3u8",
        ]
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
    /// Extensions of narrower types that also count as this one when a file is
    /// chosen, such as `swift` for plain text. Backends that filter by
    /// extension (WinUI, GTK) add them to the open filter; they never name a
    /// saved file, which takes ``fileExtensions``' first entry.
    /// 也算作此型別的較窄型別之副檔名，例如純文字的 `swift`。依副檔名過濾的 backend(WinUI、GTK)
    /// 會把它們加進開檔過濾器；它們不會用來命名存檔，存檔用的是 ``fileExtensions`` 的第一個。
    public var conformingFileExtensions: [String]

    /// Creates an instance of `ContentType`.
    ///
    /// - Parameters:
    ///   - name: The name of this content type.
    ///   - mimeTypes: An array of MIME types associated with this content type.
    ///   - fileExtensions: An array of file extensions associated with this
    ///     content type.
    ///   - conformingFileExtensions: Extensions of narrower types that also
    ///     count as this one when opening a file.
    public init(
        name: String,
        mimeTypes: [String],
        fileExtensions: [String],
        conformingFileExtensions: [String] = []
    ) {
        self.name = name
        self.mimeTypes = mimeTypes
        self.fileExtensions = fileExtensions
        self.conformingFileExtensions = conformingFileExtensions
    }
}
