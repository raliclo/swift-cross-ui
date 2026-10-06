#if !os(tvOS)
    import SwiftCrossUI
    import UniformTypeIdentifiers

    #if canImport(MobileCoreServices)
        import MobileCoreServices
    #endif

    extension ContentType {
        /// The uniform type identifiers this content type names, for
        /// `UIDocumentPickerViewController(documentTypes:in:)`.
        ///
        /// From the extensions first, then the MIME types, each listed once --
        /// the same rule as AppKitBackend's `utTypes`. `UTType` is iOS 14; on
        /// iOS 13, the package's floor, the same lookup goes through the older
        /// `UTTypeCreatePreferredIdentifierForTag`, so the filter is not lost
        /// there.
        ///
        /// 這個內容型別所指的 uniform type identifier,供
        /// `UIDocumentPickerViewController(documentTypes:in:)` 使用。先副檔名、再 MIME 型別，各列一次
        /// ——與 AppKitBackend 的 `utTypes` 規則相同。`UTType` 是 iOS 14 才有；在 iOS 13(本套件的最低版本)
        /// 上，同樣的查詢改走較舊的 `UTTypeCreatePreferredIdentifierForTag`,因此那裡也不會失去過濾。
        var typeIdentifiers: [String] {
            var identifiers: [String] = []
            func add(_ identifier: String?) {
                if let identifier, !identifiers.contains(identifier) {
                    identifiers.append(identifier)
                }
            }
            if #available(iOS 14, macCatalyst 14, *) {
                for fileExtension in fileExtensions {
                    add(UTType(filenameExtension: fileExtension)?.identifier)
                }
                for mimeType in mimeTypes {
                    add(UTType(mimeType: mimeType)?.identifier)
                }
            } else {
                #if canImport(MobileCoreServices)
                    func lookUp(_ tag: String, _ tagClass: CFString) -> String? {
                        UTTypeCreatePreferredIdentifierForTag(tagClass, tag as CFString, nil)?
                            .takeRetainedValue() as String?
                    }
                    for fileExtension in fileExtensions {
                        add(lookUp(fileExtension, kUTTagClassFilenameExtension))
                    }
                    for mimeType in mimeTypes {
                        add(lookUp(mimeType, kUTTagClassMIMEType))
                    }
                #endif
            }
            return identifiers
        }
    }
#endif
