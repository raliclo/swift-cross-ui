import Foundation
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidBackend: BackendFeatures.FileOpenDialogs {
    public func showOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[Foundation.URL]>) -> Void
    ) {
        let startingFolder = fileDialogOptions.initialDirectory.map {
            JavaString($0.absoluteString, environment: Self.env)
        }

        if openDialogOptions.allowSelectingFiles {
            let options = FilesActivityContract.Options(
                openDialogOptions.allowMultipleSelections,
                fileDialogOptions.allowedContentTypes.flatMap(\.mimeTypes),
                startingFolder,
                fileDialogOptions.allowedContentTypes.flatMap { $0.fileExtensions + $0.conformingFileExtensions },
                environment: Self.env
            )
            let openHelpers = helpers
            Self.fileDialogCallback = {
                // The dialog answers with content:// URIs, which Foundation on
                // Android cannot read (DocumentGroup's Data(contentsOf:) fails with
                // "unsupported URL"); each becomes a cached copy that is written
                // back on save. See AndroidBackendHelpers.stagingPathForOpen.
                // 對話框回傳 content:// URI,Foundation 在 Android 上讀不了(DocumentGroup 的
                // Data(contentsOf:) 以「unsupported URL」失敗);每一個都換成存檔時會寫回的 cache 副本。
                // 見 AndroidBackendHelpers.stagingPathForOpen。
                let urls = $0.compactMap { url -> Foundation.URL? in
                    guard url.scheme == "content" else { return url }
                    guard
                        let path = openHelpers.stagingPathForOpen(Self.activity, url.absoluteString)?
                            .toString()
                    else {
                        log("open dialog: could not read \(url.absoluteString); left out")
                        return nil
                    }
                    return Foundation.URL(fileURLWithPath: path)
                }
                handleResult(urls.isEmpty ? .cancelled : .success(urls))
            }
            helpers.launchFilesActivityFrom(presentingActivity(for: window), options)
        } else if openDialogOptions.allowSelectingDirectories {
            Self.folderDialogCallback = { url in
                if let url {
                    handleResult(.success([url]))
                } else {
                    handleResult(.cancelled)
                }
            }
            helpers.launchFolderActivityFrom(presentingActivity(for: window), startingFolder)
        } else {
            preconditionFailure("Neither file nor directory selection allowed?!")
        }
    }
}
