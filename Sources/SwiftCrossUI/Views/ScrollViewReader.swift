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
    public var body: some View { storage }

    private let storage: EnvironmentModifier<Content>

    public init(@ViewBuilder content: (ScrollViewProxy) -> Content) {
        // Created here, once per reader, and captured by both the proxy and the
        // environment. Creating it inside `body` would make a new registry on
        // every update, and the proxy the content is holding would keep looking
        // in the previous one -- a scroll that finds nothing, every time, with
        // nothing failing.
        //
        // 在此處建立,每個 reader 一個,並同時被 proxy 與 environment 捕捉。若改在 `body` 中建立,
        // 每次更新都會產生一個新的 registry,而內容手上握著的那個 proxy 會一直在前一個裡面找——
        // 一次「什麼都找不到」的捲動,每次皆然,而且沒有任何東西會失敗。
        let registry = ScrollAnchorRegistry()
        storage = EnvironmentModifier(content(ScrollViewProxy(registry: registry))) { environment in
            environment.with(\.scrollAnchors, registry)
        }
    }
}
