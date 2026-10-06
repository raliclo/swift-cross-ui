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
                // are allowed too. `TODO(#235)` until 2026-10-06: always any data.
                // 允許的型別；沒有指定、或也允許其他型別時為任何資料。2026-10-06 之前一律是任何資料。
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

            guard let window = window ?? Self.mainWindow else {
                fatalError(
                    "Attempting to present an open dialog before any windows have been created"
                )
            }

            window.rootViewController!.present(pickerController, animated: true)
        }
    }
#endif
