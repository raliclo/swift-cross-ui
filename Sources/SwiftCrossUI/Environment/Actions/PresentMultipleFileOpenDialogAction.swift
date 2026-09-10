import Foundation

/// Presents an open dialog that allows selecting more than one item.
///
/// **A sibling of ``PresentSingleFileOpenDialogAction`` rather than a parameter
/// on it, and the type system is what decides that.** A
/// `allowsMultipleSelection: Bool` argument cannot change a return type: the
/// single-item action returns `URL?`, this one returns `[URL]?`, and one
/// function cannot do both without making every existing caller unwrap an array
/// of one. The older type is already named `...SingleFile...`, so a sibling was
/// the shape that design left room for.
///
/// **Nothing new had to reach the backends.** `OpenDialogOptions` has carried
/// `allowMultipleSelections` all along and `showOpenDialog` has always handed
/// back `[URL]`; the single-file action passes `false` and then reads
/// `url[0]`. So the capability was there and only the public surface was
/// missing -- checked 2026-09-10 rather than assumed, because "the backends
/// probably support it" is exactly the kind of guess this tree keeps catching.
///
/// 呈現一個「允許選取多個項目」的開啟對話框。
///
/// **它是 ``PresentSingleFileOpenDialogAction`` 的兄弟,而不是它身上的一個參數;而做出這個決定的是
/// 型別系統。** 一個 `allowsMultipleSelection: Bool` 引數改變不了回傳型別:單項的那個 action 回傳
/// `URL?`,而這一個回傳 `[URL]?`;一個函式無法同時做到兩者,除非讓每一個既有呼叫端去拆一個只有一個
/// 元素的陣列。而那個較舊的型別名字裡就寫著 `...SingleFile...`——「兄弟」正是當初那個設計預留的形狀。
///
/// **沒有任何新東西需要送到 backend。** `OpenDialogOptions` 一直帶著 `allowMultipleSelections`,
/// 而 `showOpenDialog` 一直回傳 `[URL]`;單檔那個 action 傳的是 `false`,然後讀 `url[0]`。因此能力
/// 本來就在,缺的只有公開介面——這是 2026-09-10 查證過的,而不是假設的,因為「backend 大概支援吧」
/// 正是這棵樹一再抓到的那種猜測。
@available(tvOS, unavailable, message: "tvOS does not provide file system access")
public struct PresentMultipleFileOpenDialogAction: Sendable {
    let backend: any BaseAppBackend
    let window: MainActorBox<Any?>

    /// Presents the dialog and returns everything the user chose.
    ///
    /// Returns `nil` when the user cancels, and an EMPTY ARRAY never: a dialog
    /// that was dismissed and one that returned nothing are different answers,
    /// and collapsing them into `[]` would make "the user changed their mind"
    /// look like "there was nothing to pick".
    ///
    /// 呈現該對話框，並回傳使用者所選的全部項目。
    ///
    /// 使用者取消時回傳 `nil`，而**永遠不會**回傳空陣列：「對話框被取消」與「什麼都沒回傳」是兩個
    /// 不同的答案，把它們併成 `[]`，會讓「使用者改變了主意」看起來像是「本來就沒有東西可選」。
    @MainActor
    public func callAsFunction(
        title: String = "Open",
        message: String = "",
        defaultButtonLabel: String = "Open",
        initialDirectory: URL? = nil,
        showHiddenFiles: Bool = false,
        allowSelectingFiles: Bool = true,
        allowSelectingDirectories: Bool = false
    ) async -> [URL]? {
        guard let backend = backend as? any BackendFeatures.FileOpenDialogs else {
            logger.warnOnce("\(type(of: backend)) does not support file open dialogs")
            return nil
        }

        func chooseFiles<Backend: BackendFeatures.FileOpenDialogs>(
            backend: Backend
        ) async -> [URL]? {
            await withCheckedContinuation { continuation in
                backend.runInMainThread {
                    let window = self.window.value.map { $0 as! Backend.Window }

                    backend.showOpenDialog(
                        fileDialogOptions: FileDialogOptions(
                            title: title,
                            defaultButtonLabel: defaultButtonLabel,
                            allowedContentTypes: [],
                            showHiddenFiles: showHiddenFiles,
                            allowOtherContentTypes: true,
                            initialDirectory: initialDirectory
                        ),
                        openDialogOptions: OpenDialogOptions(
                            allowSelectingFiles: allowSelectingFiles,
                            allowSelectingDirectories: allowSelectingDirectories,
                            allowMultipleSelections: true
                        ),
                        window: window
                    ) { result in
                        switch result {
                            case .success(let urls):
                                continuation.resume(returning: urls)
                            case .cancelled:
                                continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
        return await chooseFiles(backend: backend)
    }
}
