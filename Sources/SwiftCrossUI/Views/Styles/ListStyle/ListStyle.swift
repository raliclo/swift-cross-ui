// This replaces `Environment/ListStyle.swift`, which held an
// `@_spi(Backends) enum ListStyle` and has been deleted rather than emptied:
// SwiftPM derives object file names from the basename, so two files called
// `ListStyle.swift` in one target fail the build with "multiple producers".
// Found the moment this file was added.
//
// 本檔取代了 `Environment/ListStyle.swift`——該檔曾持有 `@_spi(Backends) enum ListStyle`，此處選擇
// 將其刪除而非清空：SwiftPM 以 basename 決定目的檔名稱，因此同一個 target 中出現兩個
// `ListStyle.swift` 會以「multiple producers」使建置失敗。此事在本檔加入的當下即被發現。

/// A type that specifies the appearance of all lists within a view hierarchy.
///
/// The fourth style to take ``PickerStyle``'s shape, and the one that was not
/// worth converting until it did something. Until 2026-08-27 `ListStyle` was an
/// `@_spi(Backends)` enum that `SplitView` set and no backend read, so a public
/// `.listStyle(_:)` would have been a call that provably did nothing. It reaches
/// GtkBackend now.
///
/// Unlike ``PickerStyle`` and ``DatePickerStyle`` this has no `makeView`. A list
/// style changes how the backend's own list widget is drawn; it does not
/// substitute a view for it, and there is no equivalent of a custom style
/// composed out of ordinary views -- a `List` is one widget with rows, not a
/// stack this module can rebuild. So the protocol exists for the shape and the
/// naming, and every conformer is a built-in.
///
/// 用於指定某個 view 階層中所有清單外觀的型別。
///
/// 這是第四個採用 ``PickerStyle`` 形狀的樣式，也是「在它真的做事之前不值得轉換」的那一個。直到
/// 2026-08-27 為止，`ListStyle` 都還是一個 `@_spi(Backends)` 的 enum，由 `SplitView` 設定而無任何
/// backend 讀取——因此公開的 `.listStyle(_:)` 會是一個「可證明什麼也不做」的呼叫。它現在會抵達
/// GtkBackend。
///
/// 與 ``PickerStyle`` 及 ``DatePickerStyle`` 不同，此處沒有 `makeView`。清單樣式改變的是「backend
/// 自己的清單 widget 如何被繪製」，而不是用一個 view 去取代它；也沒有「以一般 view 組成自訂樣式」
/// 的對應物——`List` 是一個帶有列的 widget，不是本模組能重建的 stack。因此本 protocol 的存在是為了
/// 形狀與命名，而其所有 conformer 都是內建的。
@MainActor
public protocol ListStyle: Sendable {
    /// The appearance to ask the backend for.
    func _asBackendListStyle<Backend: BaseAppBackend>(backend: Backend) -> BackendListStyle
}

/// The platform's ordinary list.
public struct AutomaticListStyle: ListStyle {
    public nonisolated init() {}

    public func _asBackendListStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendListStyle
    {
        .default
    }
}

extension ListStyle where Self == AutomaticListStyle {
    /// The platform's ordinary list.
    ///
    /// Named `automatic` after SwiftUI rather than `default` after the backend
    /// enum, because this is the name an application writes.
    /// 依 SwiftUI 命名為 `automatic`，而非依 backend enum 命名為 `default`，因為這是應用程式實際會
    /// 寫下的名字。
    public static nonisolated var automatic: Self { Self() }
}

/// The flatter, frameless list a sidebar uses.
///
/// Set automatically on a ``NavigationSplitView``'s sidebar column, so an
/// application rarely writes it. On GtkBackend it is GTK's `navigation-sidebar`
/// style class.
///
/// 會自動套用於 ``NavigationSplitView`` 的側邊欄那一欄，因此應用程式很少需要自行寫出它。在
/// GtkBackend 上，它即是 GTK 的 `navigation-sidebar` 樣式類別。
public struct SidebarListStyle: ListStyle {
    public nonisolated init() {}

    public func _asBackendListStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendListStyle
    {
        .sidebar
    }
}

extension ListStyle where Self == SidebarListStyle {
    /// The flatter, frameless list a sidebar uses.
    public static nonisolated var sidebar: Self { Self() }
}
