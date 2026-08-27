/// The list appearances a backend can be asked for directly.
///
/// The fourth of these, after ``BackendPickerStyle``, ``BackendDatePickerStyle``
/// and ``BackendToggleStyle``, and the only one whose enum was previously
/// `@_spi(Backends)` rather than public API -- which was correct while nothing
/// read it. See ``ListStyle`` for the application-facing protocol.
///
/// Deliberately only two cases. SwiftUI has `.plain`, `.inset`, `.grouped`,
/// `.insetGrouped` and `.bordered` as well, and none of them maps to anything a
/// backend here can draw differently; adding names for them would produce
/// exactly the silent no-op this project spends its time hunting.
///
/// 一個 backend 可被直接要求的清單外觀。
///
/// 這是繼 ``BackendPickerStyle``、``BackendDatePickerStyle`` 與 ``BackendToggleStyle`` 之後的第四個，
/// 也是唯一一個其 enum 先前為 `@_spi(Backends)` 而非公開 API 的——在沒有任何東西讀取它的期間，那是
/// 正確的。應用程式所面對的 protocol 見 ``ListStyle``。
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
