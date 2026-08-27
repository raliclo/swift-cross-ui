/// What a button is for, when that changes how it should look.
///
/// SwiftUI's roles. A role is not a style: `.destructive` says the action
/// deletes something, and each platform decides what that looks like — red text
/// on Apple platforms, the `destructive-action` style class on GTK. An
/// application says what the button *does* and the platform stays in charge of
/// how that reads to its users.
///
/// Only the two SwiftUI has. Inventing more would give applications a vocabulary
/// no platform can honour.
///
/// 按鈕的用途——當該用途會改變它應有的外觀時。
///
/// 這是 SwiftUI 的 role。role 並不是 style：`.destructive` 說的是「這個動作會刪除某些東西」，而各
/// 平台自行決定它看起來如何——在 Apple 平台上是紅色文字，在 GTK 上則是 `destructive-action` 樣式
/// 類別。應用程式陳述按鈕**做什麼**，平台則保有「這在其使用者眼中該如何呈現」的決定權。
///
/// 此處只提供 SwiftUI 所具備的兩種。自行發明更多，等於給應用程式一套沒有任何平台能夠遵從的詞彙。
public enum ButtonRole: Sendable, Hashable {
    /// The action deletes data or is otherwise hard to undo.
    /// 該動作會刪除資料，或在其他意義上難以復原。
    case destructive

    /// The action backs out without doing anything.
    /// 該動作不做任何事，僅退出。
    case cancel
}
