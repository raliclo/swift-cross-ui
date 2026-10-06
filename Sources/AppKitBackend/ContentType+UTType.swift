import SwiftCrossUI
import UniformTypeIdentifiers

extension ContentType {
    /// The uniform types this content type names, for `NSOpenPanel` and
    /// `NSSavePanel`'s `allowedContentTypes`.
    ///
    /// From the file extensions first, then the MIME types: an extension is
    /// what the panel matches files by, and a MIME type that the system has no
    /// type for yields nothing rather than a guess. A type is listed once even
    /// when several of its extensions resolve to it (`htm` and `html` are both
    /// `public.html`). An extension the system does not know still gives a
    /// type -- a dynamic one -- so the panel filters by it rather than dropping
    /// it, which would silently widen the dialog to every file.
    ///
    /// 這個內容型別所指的 uniform type,供 `NSOpenPanel` 與 `NSSavePanel` 的 `allowedContentTypes`
    /// 使用。先由副檔名、再由 MIME 型別取得：面板是依副檔名比對檔案的，而系統不認得的 MIME 型別會得到
    /// 「無」而非猜測。好幾個副檔名對到同一型別時只列一次(`htm` 與 `html` 都是 `public.html`)。系統不認得的
    /// 副檔名仍會得到一個(動態)型別，讓面板依它過濾，而不是丟掉它——那會讓對話框悄悄放寬成所有檔案。
    var utTypes: [UTType] {
        var types: [UTType] = []
        func add(_ type: UTType?) {
            if let type, !types.contains(type) {
                types.append(type)
            }
        }
        for fileExtension in fileExtensions {
            add(UTType(filenameExtension: fileExtension))
        }
        for mimeType in mimeTypes {
            add(UTType(mimeType: mimeType))
        }
        return types
    }
}
