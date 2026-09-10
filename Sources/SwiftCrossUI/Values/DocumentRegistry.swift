import Foundation

/// Where a ``DocumentGroup`` leaves the two things a menu item needs to call.
///
/// The same shape as ``SettingsRegistry`` and for the same reason: the scene
/// that OWNS the documents and the view or command that asks for a new one are
/// in different parts of the tree, and the environment only travels downwards.
///
/// Not `@MainActor`, because `EnvironmentValues` builds its defaults in a
/// nonisolated context and rejects a main-actor-isolated one outright -- the
/// error ``SettingsRegistry`` records. Both closures are only ever touched
/// during scene and view updates, which are already on the main actor.
///
/// ``DocumentGroup`` 把「一個選單項目需要呼叫的那兩件事」留在這裡。
///
/// 形狀與 ``SettingsRegistry`` 相同，理由也相同：**擁有**那些文件的 scene，與「要求開一份新文件」的
/// view 或命令，位於樹的不同部分，而 environment 只會往下走。
///
/// 不標 `@MainActor`：`EnvironmentValues` 是在 nonisolated 情境中建構它的預設值，會直接拒絕一個以
/// main actor 隔離的值——那正是 ``SettingsRegistry`` 所記載的錯誤。這兩個 closure 只會在 scene 與
/// view 的更新期間被碰到，而那些本來就在 main actor 上。
public final class DocumentRegistry: @unchecked Sendable {
    /// Opens a new, empty document in its own window.
    /// 在自己的視窗中開啟一份新的空白文件。
    var newDocument: (@MainActor () -> Void)?

    /// Opens the file at this URL in its own window.
    /// 在自己的視窗中開啟位於這個 URL 的檔案。
    var openDocument: (@MainActor (URL) -> Void)?

    public init() {}
}
