import Foundation
import SwiftCrossUI
import WinSDK

/// Open and save dialogs through the Win32 shell's `IFileDialog`, not WinRT's
/// pickers.
///
/// **The WinRT pickers could not express half of `FileDialogOptions`.**
/// `FileOpenPicker`, `FolderPicker` and `FileSavePicker` take a start location
/// only as a `PickerLocationId` -- Documents, Desktop, Downloads -- so
/// `initialDirectory` was ignored by all three. Measured 2026-10-07 with P75:
/// "Save..." opened in Documents and the file landed in
/// `C:/Users/lowei/OneDrive/Documents`, a folder the user syncs to the cloud,
/// although the app had asked for none of that. P62 asks for its own temporary
/// folder and was sent to Documents the same way. They also ignored `title`,
/// `showHiddenFiles` and `nameFieldLabel`, ignored `defaultButtonLabel` for files
/// and saves, and choosing more than one folder hit a `precondition` -- a
/// process abort on a shipped backend, which this repository's CLAUDE.md rules
/// out.
///
/// `IFileDialog` has a call for each: `SetFolder`, `SetTitle`,
/// `SetOkButtonLabel`, `SetFileNameLabel`, `SetFileName`, `SetFileTypes`, and
/// the `FOS_FORCESHOWHIDDEN` / `FOS_ALLOWMULTISELECT` / `FOS_PICKFOLDERS`
/// options. It is the same dialog Windows shows for the pickers; only the API in
/// front of it is wider. It needs an STA thread, which is what
/// `WinUIApplication.runSingleThreaded()` gives the main thread.
///
/// Called the way the rest of this backend calls COM -- the C interfaces of
/// WinSDK through `lpVtbl` -- as `D3D11VideoInterop.swift` already does.
///
/// 透過 Win32 shell 的 `IFileDialog` 開檔與存檔,而不是 WinRT 的 picker。
///
/// **WinRT 的 picker 表達不了 `FileDialogOptions` 的一半。** `FileOpenPicker`、`FolderPicker` 與
/// `FileSavePicker` 的起始位置只接受 `PickerLocationId`(Documents、Desktop、Downloads),因此三者都忽略
/// `initialDirectory`。2026-10-07 以 P75 實測:「Save...」開在 Documents,檔案落到
/// `C:/Users/lowei/OneDrive/Documents`——一個使用者會同步上雲的資料夾——而 app 根本沒要求這些。P62 要求自己的
/// 暫存資料夾,也同樣被送到 Documents。它們還忽略 `title`、`showHiddenFiles` 與 `nameFieldLabel`,檔案與存檔
/// 時忽略 `defaultButtonLabel`,而選多個資料夾會撞上 `precondition`——在已發布的 backend 上直接中止行程,正是
/// 本 repository 的 CLAUDE.md 所禁止的。
///
/// `IFileDialog` 對每一項都有對應的呼叫。它就是 Windows 為 picker 顯示的同一個對話框,只是前面那層 API 比較寬。
/// 它需要 STA 執行緒,而 `WinUIApplication.runSingleThreaded()` 正好讓主執行緒是 STA。
extension WinUIBackend {
    /// What a dialog is being asked for.
    /// 這次對話框要做什麼。
    enum ShellDialogKind {
        case openFiles(multiple: Bool)
        case openFolders(multiple: Bool)
        case save(SaveDialogOptions)
    }

    /// Shows a shell file dialog modally over `hwnd` and returns the paths the
    /// user chose, or nil when they cancelled or the dialog could not be shown.
    ///
    /// Synchronous: `IFileDialog::Show` runs its own message loop, so the
    /// window stays responsive while it is up, and the caller's result handler
    /// is invoked after it returns.
    ///
    /// 以 `hwnd` 為擁有者、模態地顯示 shell 檔案對話框,回傳使用者選的路徑;取消或無法顯示時回傳 nil。
    /// 同步執行:`IFileDialog::Show` 會跑自己的訊息迴圈,因此對話框開著時視窗仍有回應,呼叫端的結果處理在它返回
    /// 之後才執行。
    @MainActor
    static func runShellFileDialog(
        _ kind: ShellDialogKind,
        options: FileDialogOptions,
        owner hwnd: HWND
    ) -> [URL]? {
        let isSave: Bool
        if case .save = kind { isSave = true } else { isSave = false }

        var clsid = isSave ? CLSID_FileSaveDialog : CLSID_FileOpenDialog
        var iid = IID_IFileDialog
        var raw: LPVOID?
        guard
            CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &raw) == S_OK,
            let dialog = raw?.assumingMemoryBound(to: IFileDialog.self)
        else {
            reportDialogFailure("CoCreateInstance(FileDialog) failed")
            return nil
        }
        defer { _ = dialog.pointee.lpVtbl.pointee.Release(dialog) }
        let vtbl = dialog.pointee.lpVtbl.pointee

        // Strings the dialog reads while it is up. Kept alive until the end of
        // this function and freed together.
        // 對話框開著時會讀取的字串。保留到本函式結束,再一起釋放。
        var owned: [UnsafeMutablePointer<WCHAR>] = []
        defer { owned.forEach { $0.deallocate() } }
        func wide(_ string: String) -> UnsafeMutablePointer<WCHAR> {
            let units = Array(string.utf16) + [0]
            let pointer = UnsafeMutablePointer<WCHAR>.allocate(capacity: units.count)
            pointer.initialize(from: units, count: units.count)
            owned.append(pointer)
            return pointer
        }

        var flags: FILEOPENDIALOGOPTIONS = 0
        _ = vtbl.GetOptions(dialog, &flags)
        flags |= FILEOPENDIALOGOPTIONS(FOS_FORCEFILESYSTEM.rawValue)
        if options.showHiddenFiles {
            flags |= FILEOPENDIALOGOPTIONS(FOS_FORCESHOWHIDDEN.rawValue)
        }
        switch kind {
            case .openFiles(let multiple):
                flags |= FILEOPENDIALOGOPTIONS(FOS_FILEMUSTEXIST.rawValue)
                if multiple { flags |= FILEOPENDIALOGOPTIONS(FOS_ALLOWMULTISELECT.rawValue) }
            case .openFolders(let multiple):
                flags |= FILEOPENDIALOGOPTIONS(FOS_PICKFOLDERS.rawValue)
                if multiple { flags |= FILEOPENDIALOGOPTIONS(FOS_ALLOWMULTISELECT.rawValue) }
            case .save:
                flags |= FILEOPENDIALOGOPTIONS(FOS_OVERWRITEPROMPT.rawValue)
        }
        _ = vtbl.SetOptions(dialog, flags)

        if !options.title.isEmpty {
            _ = vtbl.SetTitle(dialog, wide(options.title))
        }
        if !options.defaultButtonLabel.isEmpty {
            _ = vtbl.SetOkButtonLabel(dialog, wide(options.defaultButtonLabel))
        }

        // The start folder. Only an existing directory is used: the shell
        // rejects a path it cannot resolve, and the dialog's own default is the
        // honest fallback.
        // 起始資料夾。只採用確實存在的目錄:shell 會拒絕無法解析的路徑,而對話框自己的預設是誠實的退路。
        if let directory = options.initialDirectory {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                var itemIID = IID_IShellItem
                var itemRaw: LPVOID?
                if SHCreateItemFromParsingName(
                    wide(directory.withUnsafeFileSystemRepresentation { String(cString: $0!) }
                        .replacingOccurrences(of: "/", with: "\\")),
                    nil, &itemIID, &itemRaw
                ) == S_OK, let item = itemRaw?.assumingMemoryBound(to: IShellItem.self) {
                    _ = vtbl.SetFolder(dialog, item)
                    _ = item.pointee.lpVtbl.pointee.Release(item)
                }
            }
        }

        // File types: one entry per content type, then "All files" when there
        // are none or others are allowed. Not for folders, which have no type.
        // `*.*` is the pattern Windows itself uses for "All files"; the WinRT
        // save picker needed the unverified spelling `"."` for the same thing.
        // 檔案型別:每個內容型別一項,沒有指定或也允許其他型別時再加「All files」。資料夾沒有型別,不加。
        // `*.*` 是 Windows 自己用來表示「All files」的樣式;WinRT 的存檔 picker 為此用的是未經驗證的 `"."`。
        if case .openFolders = kind {} else {
            var specs: [COMDLG_FILTERSPEC] = []
            var firstExtension: String?
            for contentType in options.allowedContentTypes where !contentType.fileExtensions.isEmpty {
                let pattern = contentType.fileExtensions.map { "*." + $0 }.joined(separator: ";")
                specs.append(COMDLG_FILTERSPEC(pszName: wide(contentType.name), pszSpec: wide(pattern)))
                firstExtension = firstExtension ?? contentType.fileExtensions.first
            }
            if options.allowedContentTypes.isEmpty || options.allowOtherContentTypes {
                specs.append(COMDLG_FILTERSPEC(pszName: wide("All files"), pszSpec: wide("*.*")))
            }
            if !specs.isEmpty {
                _ = specs.withUnsafeBufferPointer { buffer in
                    vtbl.SetFileTypes(dialog, UINT(buffer.count), buffer.baseAddress)
                }
                _ = vtbl.SetFileTypeIndex(dialog, 1)
            }
            // The extension a typed name gets when it has none, taken from the
            // selected type -- so "All files" adds nothing.
            // 輸入的檔名沒有副檔名時要補上的副檔名,取自目前選的型別——因此「All files」不補。
            if let firstExtension {
                _ = vtbl.SetDefaultExtension(dialog, wide(firstExtension))
            }
        }

        if case .save(let saveOptions) = kind {
            if let label = saveOptions.nameFieldLabel, !label.isEmpty {
                _ = vtbl.SetFileNameLabel(dialog, wide(label))
            }
            if let name = saveOptions.defaultFileName, !name.isEmpty {
                _ = vtbl.SetFileName(dialog, wide(name))
            }
        }

        let shown = vtbl.Show(dialog, hwnd)
        guard shown == S_OK else {
            // ERROR_CANCELLED is the user closing the dialog; anything else is
            // a dialog that could not be shown, and saying so is the difference
            // between the two.
            // ERROR_CANCELLED 是使用者關掉對話框;其他值則是對話框根本顯示不出來,而說出來正是兩者的差別。
            if shown != HRESULT(bitPattern: 0x8007_04C7) {
                reportDialogFailure("IFileDialog::Show failed, hr=0x\(String(UInt32(bitPattern: shown), radix: 16))")
            }
            return nil
        }

        func path(of item: UnsafeMutablePointer<IShellItem>) -> URL? {
            var name: LPWSTR?
            guard item.pointee.lpVtbl.pointee.GetDisplayName(item, SIGDN_FILESYSPATH, &name) == S_OK,
                let name
            else { return nil }
            defer { CoTaskMemFree(name) }
            return URL(fileURLWithPath: String(decodingCString: name, as: UTF16.self))
        }

        let isMultiple: Bool
        switch kind {
            case .openFiles(let multiple), .openFolders(let multiple): isMultiple = multiple
            case .save: isMultiple = false
        }

        if isMultiple {
            var openIID = IID_IFileOpenDialog
            var openRaw: LPVOID?
            guard vtbl.QueryInterface(dialog, &openIID, &openRaw) == S_OK,
                let open = openRaw?.assumingMemoryBound(to: IFileOpenDialog.self)
            else { return nil }
            defer { _ = open.pointee.lpVtbl.pointee.Release(open) }
            var results: UnsafeMutablePointer<IShellItemArray>?
            guard open.pointee.lpVtbl.pointee.GetResults(open, &results) == S_OK, let results else {
                return nil
            }
            defer { _ = results.pointee.lpVtbl.pointee.Release(results) }
            var count: DWORD = 0
            _ = results.pointee.lpVtbl.pointee.GetCount(results, &count)
            var urls: [URL] = []
            for index in 0..<count {
                var item: UnsafeMutablePointer<IShellItem>?
                if results.pointee.lpVtbl.pointee.GetItemAt(results, index, &item) == S_OK, let item {
                    if let url = path(of: item) { urls.append(url) }
                    _ = item.pointee.lpVtbl.pointee.Release(item)
                }
            }
            return urls
        } else {
            var item: UnsafeMutablePointer<IShellItem>?
            guard vtbl.GetResult(dialog, &item) == S_OK, let item else { return nil }
            defer { _ = item.pointee.lpVtbl.pointee.Release(item) }
            return path(of: item).map { [$0] }
        }
    }

    /// Loud on stderr rather than through the logger: a dialog that silently
    /// fails to appear reads as a cancel, which is the one outcome nobody
    /// would report.
    /// 寫到 stderr 而不是 logger:默默顯示不出來的對話框看起來就像使用者取消,而那是唯一不會有人回報的結果。
    private static func reportDialogFailure(_ message: String) {
        FileHandle.standardError.write(Data("WinUIBackend file dialog: \(message)\n".utf8))
    }
}
