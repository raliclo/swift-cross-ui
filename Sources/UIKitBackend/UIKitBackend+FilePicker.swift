#if !os(tvOS)
    @_spi(Backends) import SwiftCrossUI
    import UIKit

    extension UIKitBackend: BackendFeatures.FileOpenDialogs {
        final class FilePickerDelegate: NSObject, UIDocumentPickerDelegate {
            var resultHandler: ((DialogResult<[URL]>) -> Void)

            init(resultHandler: @escaping (DialogResult<[URL]>) -> Void) {
                self.resultHandler = resultHandler
            }

            func documentPicker(
                _ controller: UIDocumentPickerViewController,
                didPickDocumentsAt urls: [URL]
            ) {
                resultHandler(.success(urls))
            }

            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                resultHandler(.cancelled)
            }
        }

        public func showOpenDialog(
            fileDialogOptions: FileDialogOptions,
            openDialogOptions: OpenDialogOptions,
            window: UIWindow?,
            resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
        ) {
            var allowedTypes: [String] = []

            if openDialogOptions.allowSelectingDirectories {
                allowedTypes.append("public.directory")
            }

            if openDialogOptions.allowSelectingFiles {
                // The allowed types, or any data when there are none or others
                // are allowed too.
                // 允許的型別；沒有指定、或也允許其他型別時為任何資料。
                let identifiers = fileDialogOptions.allowedContentTypes.flatMap(\.typeIdentifiers)
                if identifiers.isEmpty || fileDialogOptions.allowOtherContentTypes {
                    allowedTypes.append("public.data")
                } else {
                    allowedTypes += identifiers
                }
            }

            let pickerController = UIDocumentPickerViewController(
                documentTypes: allowedTypes,
                in: .import
            )

            pickerController.allowsMultipleSelection = openDialogOptions.allowMultipleSelections
            pickerController.directoryURL = fileDialogOptions.initialDirectory

            pickerController.shouldShowFileExtensions =
                fileDialogOptions.allowOtherContentTypes
                    || fileDialogOptions.allowedContentTypes.count > 1

            let delegate = FilePickerDelegate(resultHandler: handleResult)
            pickerController.delegate = delegate
            self.filePickerDelegates.setObject(delegate, forKey: pickerController)

            // No window means nothing to present from: logged and reported as
            // cancelled, as the save dialog does, rather than ending the app.
            // From the top of the presentation chain, so a picker opened from a
            // sheet is not refused because the root is presenting that sheet.
            // 沒有視窗就沒有可以呈現的起點：記錄下來並回報為取消，與存檔對話框相同，而不是結束 app。
            // 從呈現鏈的最上層呈現，因此從 sheet 打開的選擇器不會因為 root 正在呈現那個 sheet 而被拒絕。
            guard let window = window ?? Self.mainWindow else {
                logger.error("no window to present the open dialog from")
                self.filePickerDelegates.removeObject(forKey: pickerController)
                handleResult(.cancelled)
                return
            }

            Self.presentOnTop(pickerController, in: window)
        }
    }
#endif
