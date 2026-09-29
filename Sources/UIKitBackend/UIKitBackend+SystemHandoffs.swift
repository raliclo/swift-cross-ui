#if !os(tvOS)
    import UIKit
    import UniformTypeIdentifiers
    @_spi(Backends) import SwiftCrossUI

    /// Revealing a file and choosing where to save one -- both through the
    /// system document browser, which is iOS's file manager.
    ///
    /// Neither existed until 2026-09-30, so `revealFile` was nil and
    /// `chooseFileSaveDestination` warned once and returned nil on iOS.
    ///
    /// 顯示一個檔案，以及選擇檔案要存到哪裡——兩者都經由系統的文件瀏覽器，也就是 iOS 的檔案管理員。
    /// 2026-09-30 之前兩者都不存在，因此在 iOS 上 `revealFile` 是 nil，而
    /// `chooseFileSaveDestination` 只會警告一次並回傳 nil。
    extension UIKitBackend: BackendFeatures.RevealFiles, BackendFeatures.FileSaveDialogs {
        public struct HandoffError: Error, CustomStringConvertible {
            public let description: String
        }

        /// Shows the file's folder in the system document browser.
        ///
        /// Not `shareddocuments://`, the Files app's URL scheme, although it
        /// is the more obvious route. Measured on the iOS 27 simulator
        /// 2026-09-30: for the app's Documents folder and for a subfolder of
        /// it, Files opened at "On My iPhone" -- the list of apps, one level
        /// above -- and for a file path it opened Recents. It never showed the
        /// folder. `directoryURL` on the document picker is the documented way
        /// to start the same browser in a given folder.
        ///
        /// The folder must be one the browser can see: the app's Documents
        /// (the template declares `UIFileSharingEnabled` and
        /// `LSSupportsOpeningDocumentsInPlace`), or any location a file
        /// provider exposes. Measured with P75: for Documents/P75 the browser
        /// opened inside P75 listing the file. For the Documents folder itself
        /// it opens one level up, at "On My iPhone", where Documents is the
        /// folder named after the app -- that is how the browser presents a
        /// container's root, and the same happened through Files.
        ///
        /// 在系統文件瀏覽器中顯示檔案所在的資料夾。**不用** `shareddocuments://`（Files app 的 URL
        /// scheme），儘管那是比較直覺的路。2026-09-30 於 iOS 27 simulator 實測：對 app 的
        /// Documents 資料夾及其子資料夾，Files 開在「On My iPhone」——也就是上一層的 app 清單——而對
        /// 一個檔案路徑則開在「最近項目」。它從未顯示那個資料夾。文件選擇器的 `directoryURL` 才是讓同一個
        /// 瀏覽器從指定資料夾開始的文件化做法。該資料夾必須是瀏覽器看得到的：app 的 Documents（範本已宣告
        /// `UIFileSharingEnabled` 與 `LSSupportsOpeningDocumentsInPlace`），或任何 file provider
        /// 所公開的位置。
        public func revealFile(_ url: URL) throws {
            guard let window = Self.mainWindow else {
                throw HandoffError(description: "no window to present the document browser from")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            else {
                throw HandoffError(description: "no file at \(url.path)")
            }
            let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()

            let browser = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item],
                asCopy: false
            )
            browser.directoryURL = folder
            browser.shouldShowFileExtensions = true
            Self.presentOnTop(browser, in: window)
        }

        /// Chooses a destination by exporting a placeholder.
        ///
        /// iOS has no "name a file that does not exist yet" dialog; it saves
        /// by exporting a file that does. So an empty file with the default
        /// name is created in a private staging folder, the picker MOVES it to
        /// the folder the person chooses, and the URL it arrives at is handed
        /// back for the app to write to -- inside a security scope that is
        /// opened here, because a location outside the app's container is not
        /// writable without one.
        ///
        /// 以匯出一個佔位檔來選擇存放位置。iOS 沒有「為一個尚不存在的檔案命名」的對話框；它的儲存方式是
        /// 匯出一個**已存在**的檔案。因此在私有的暫存資料夾裡建立一個以預設名稱命名的空檔，由選擇器把它
        /// **移動**到使用者選的資料夾，再把它抵達的 URL 交回給 app 寫入——並在此開啟 security scope，
        /// 因為 app container 以外的位置沒有它就無法寫入。
        public func showSaveDialog(
            fileDialogOptions: FileDialogOptions,
            saveDialogOptions: SaveDialogOptions,
            window: UIWindow?,
            resultHandler handleResult: @escaping (DialogResult<URL>) -> Void
        ) {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("save-\(UUID().uuidString)", isDirectory: true)
            let name = saveDialogOptions.defaultFileName ?? "Untitled"
            let placeholder = staging.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(
                    at: staging,
                    withIntermediateDirectories: true
                )
                try Data().write(to: placeholder)
            } catch {
                logger.error(
                    "could not stage the file to export",
                    metadata: ["error": "\(error)"]
                )
                handleResult(.cancelled)
                return
            }

            let picker = UIDocumentPickerViewController(
                forExporting: [placeholder],
                asCopy: false
            )
            picker.directoryURL = fileDialogOptions.initialDirectory
            picker.shouldShowFileExtensions = true

            let delegate = FilePickerDelegate { result in
                switch result {
                    case .success(let urls):
                        guard let destination = urls.first else {
                            handleResult(.cancelled)
                            return
                        }
                        _ = destination.startAccessingSecurityScopedResource()
                        handleResult(.success(destination))
                    case .cancelled:
                        try? FileManager.default.removeItem(at: staging)
                        handleResult(.cancelled)
                }
            }
            picker.delegate = delegate
            filePickerDelegates.setObject(delegate, forKey: picker)

            guard let window = window ?? Self.mainWindow else {
                logger.error("no window to present the save dialog from")
                handleResult(.cancelled)
                return
            }
            Self.presentOnTop(picker, in: window)
        }
    }
#endif
