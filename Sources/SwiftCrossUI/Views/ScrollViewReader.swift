/// A handle for scrolling an enclosing ``ScrollView`` to a tagged view.
///
/// Obtained from ``ScrollViewReader``, and used the way SwiftUI's is:
///
/// ```swift
/// ScrollViewReader { proxy in
///     ScrollView {
///         ForEach(rows) { row in
///             Text(row.name).id(row.id)
///         }
///     }
///     Button("Jump to the end") { proxy.scrollTo(rows.last!.id) }
/// }
/// ```
///
/// 用來把外圍的 ``ScrollView`` 捲到某個被標記的 view 的握把。
///
/// 由 ``ScrollViewReader`` 取得,用法與 SwiftUI 的相同。
public struct ScrollViewProxy {
    let registry: ScrollAnchorRegistry

    /// Scrolls so that the view tagged with `id` is visible.
    ///
    /// - Parameter anchor: Where in the viewport to put it, or `nil` for the
    ///   shortest scroll that makes it visible. `nil` is the default because it
    ///   is what every backend here has a native call for; an anchor is
    ///   arithmetic on top of that.
    ///
    /// Does nothing when no view carries that id, or when the proxy is used
    /// outside a ``ScrollView``. See ``ScrollAnchorRegistry`` for why neither
    /// warns.
    ///
    /// 捲動使帶有 `id` 標記的 view 可見。
    ///
    /// - Parameter anchor: 要把它放在視口的什麼位置,或傳 `nil` 表示「讓它可見的最短捲動」。
    ///   預設為 `nil`,因為那是此處每一個 backend 都有原生呼叫可用的情況;anchor 則是疊在其上的算術。
    ///
    /// 當沒有任何 view 帶有該 id、或該 proxy 被用在 ``ScrollView`` 之外時,不做任何事。
    /// 兩者為何都不發出警告,見 ``ScrollAnchorRegistry``。
    @MainActor
    public func scrollTo(_ id: some Hashable, anchor: UnitPoint? = nil) {
        registry.scroll(to: AnyHashable(id), anchor: anchor)
    }
}

/// Gives its content a ``ScrollViewProxy`` for scrolling a ``ScrollView`` inside
/// it to a view tagged with ``View/id(_:)``.
///
/// **The reader goes OUTSIDE the scroll view, not inside it**, which is also
/// SwiftUI's shape and is easy to get backwards. The thing that triggers a
/// scroll is usually a button that must stay on screen while the content moves,
/// so it cannot be inside the thing being scrolled.
///
/// 為其內容提供一個 ``ScrollViewProxy``,用來把它內部的 ``ScrollView`` 捲到某個以 ``View/id(_:)``
/// 標記的 view。
///
/// **這個 reader 位於捲動視圖的外面,而不是裡面**,那也是 SwiftUI 的形狀,而且很容易搞反。
/// 觸發捲動的東西通常是一顆「必須在內容移動時仍留在畫面上」的按鈕,因此它不能位於被捲動的那個東西裡面。
public struct ScrollViewReader<Content: View>: View {
    // `some View` rather than the concrete `EnvironmentModifier<Content>`.
    // That type is internal, and a public property cannot name it -- the error
    // is `property cannot be declared public because its type uses an internal
    // type`, and it points at the property rather than at the modifier, which
    // is the confusing half.
    // 使用 `some View` 而非具體的 `EnvironmentModifier<Content>`。那個型別是 internal 的,而一個
    // public 屬性無法指名它——錯誤訊息是 `property cannot be declared public because its type uses
    // an internal type`,而它指向的是這個屬性、而不是那個 modifier,那才是令人困惑的一半。
    public var body: some View {
        let registry = holder.registry
        return EnvironmentModifier(content(ScrollViewProxy(registry: registry))) { environment in
            environment.with(\.scrollAnchors, registry)
        }
    }

    // **Held in `@State`, so it lives as long as the view-graph node, not as long
    // as this struct.** Until 2026-10-05 the registry was created in `init`, "once
    // per reader" -- but a reader is a value, rebuilt every time its parent's body
    // runs, so every update brought a new registry. The node laid out with the
    // newest one, so the ScrollView and every `.id` registered there, while a
    // proxy captured earlier -- by `onAppear`, or by a closure dispatched a moment
    // later -- kept looking in the one before: measured, `0 anchors, 0 scrollers`
    // in the registry the proxy held, with 500 rows on screen. `scrollTo` then did
    // nothing and nothing failed. The registry sits in a struct because `@State`
    // deprecates a bare non-observable class; it needs no change notification,
    // only to survive.
    //
    // **放在 `@State` 裡,讓它活得跟 view graph 的節點一樣久,而不是跟這個 struct 一樣久。**
    // 2026-10-05 之前,registry 在 `init` 中建立,「每個 reader 一個」——但 reader 是一個值,父層的
    // body 每執行一次就重建一次,所以每次更新都帶來一個新的 registry。節點以最新的那個排版,ScrollView
    // 與每一個 `.id` 都登記在那裡;而較早被捕捉的 proxy——被 `onAppear`,或被稍後才派送的閉包——仍在
    // 前一個裡面找:實測 proxy 手上的 registry 是 `0 anchors, 0 scrollers`,而畫面上有 500 列。
    // `scrollTo` 因此什麼都沒做,也沒有任何東西失敗。registry 包在 struct 裡,是因為 `@State` 不建議
    // 直接放非 observable 的 class;它不需要變更通知,只需要存活。
    @State private var holder = RegistryHolder()
    private let content: (ScrollViewProxy) -> Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }
}

private struct RegistryHolder {
    let registry = ScrollAnchorRegistry()
}
