/// The list appearances a backend can be asked for directly.
///
/// Like ``BackendPickerStyle``, ``BackendDatePickerStyle``,
/// ``BackendToggleStyle`` and ``BackendTextFieldStyle``, it is the vocabulary a
/// backend implements. See ``ListStyle`` for the application-facing protocol.
///
/// Deliberately only two cases. SwiftUI has `.plain`, `.inset`, `.grouped`,
/// `.insetGrouped` and `.bordered` as well, and none of them maps to anything a
/// backend here can draw differently; adding names for them would produce
/// exactly the silent no-op this project spends its time hunting.
///
/// 一個 backend 可被直接要求的清單外觀。
///
/// 與 ``BackendPickerStyle``、``BackendDatePickerStyle``、``BackendToggleStyle``、``BackendTextFieldStyle``
/// 一樣，它是 backend 所實作的詞彙。應用程式所面對的 protocol 見 ``ListStyle``。
///
/// 刻意只有兩個 case。SwiftUI 另有 `.plain`、`.inset`、`.grouped`、`.insetGrouped` 與 `.bordered`，
/// 而其中沒有任何一個能對應到此處 backend 畫得出差異的東西；為它們加上名字，恰好會製造出本專案
/// 一直在獵捕的那種靜默 no-op。
public enum BackendListStyle: Sendable, Hashable {
    /// The platform's ordinary list.
    case `default`
    /// The flatter, frameless list a sidebar uses.
    case sidebar
}
