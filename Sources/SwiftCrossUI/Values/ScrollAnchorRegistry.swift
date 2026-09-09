/// Where `.id(_:)` puts what it tagged, and where `ScrollViewProxy` looks.
///
/// A class carried in the environment, which is how a value handed DOWN the tree
/// gets read by something ABOVE it. `ScrollViewReader` creates one, puts it in
/// the environment, and hands a proxy holding the same object to its content
/// closure; the `.id(_:)` modifiers below register into it as they update, and
/// the `ScrollView` between them installs the closure that can actually scroll.
///
/// **The scroll closure exists because widgets are type-erased and backends are
/// not.** `scrollContainer(_:to:anchor:)` needs `Backend.Widget`, and this
/// object cannot name a backend -- it is stored in `EnvironmentValues`, which is
/// not generic over one. `ScrollView.update` HAS the concrete backend, so it
/// installs a closure that captures it. The type is recovered exactly once, at
/// the only point where it is still known.
///
/// `.id(_:)` 所標記的東西存放之處,也是 `ScrollViewProxy` 查找之處。
///
/// 這是一個放在 environment 中傳遞的 class,而那正是「一個往**下**傳的值,如何被它**上方**的東西
/// 讀到」的方式。`ScrollViewReader` 建立它、把它放進 environment,並把一個持有同一個物件的 proxy
/// 交給它的內容 closure;下方的 `.id(_:)` modifier 會在更新時登記進來,而位於兩者之間的 `ScrollView`
/// 則安裝那個真正能執行捲動的 closure。
///
/// **之所以需要那個 scroll closure,是因為 widget 被型別抹除了而 backend 沒有。**
/// `scrollContainer(_:to:anchor:)` 需要 `Backend.Widget`,而這個物件無法指名任何一個 backend——
/// 它存放在 `EnvironmentValues` 之中,而後者並不對 backend 泛型化。`ScrollView.update` **擁有**具體的
/// backend,因此由它安裝一個捕捉了該 backend 的 closure。型別只在一個地方被還原,而那正是它仍然
/// 為人所知的唯一地點。
@MainActor
public final class ScrollAnchorRegistry {
    /// The widget each `.id(_:)` most recently wrapped.
    ///
    /// Overwritten rather than accumulated. A view's widget is stable across
    /// updates but not across a rebuild, and a registry that kept both would
    /// scroll to the dead one -- which succeeds, moves the container, and shows
    /// the wrong row.
    ///
    /// 每一個 `.id(_:)` 最近一次所包住的 widget。
    ///
    /// 採覆寫而非累積。一個 view 的 widget 在多次更新之間是穩定的,但在一次重建之後就不是了;
    /// 而一個把兩者都留著的 registry 會捲向那個已死的 widget——那會成功、會移動容器、並顯示錯誤的列。
    var anchors: [AnyHashable: AnyWidget] = [:]

    /// Installed by the enclosing ``ScrollView`` on every update, because that
    /// is where the backend's type is still known.
    /// 由外圍的 ``ScrollView`` 在每次更新時安裝,因為那裡是 backend 的型別仍為人所知之處。
    var performScroll: ((AnyWidget, UnitPoint?) -> Void)?

    public init() {}

    func register(_ widget: AnyWidget, for id: AnyHashable) {
        anchors[id] = widget
    }

    func scroll(to id: AnyHashable, anchor: UnitPoint?) {
        // Silent when the id is unknown or no ScrollView installed a closure.
        //
        // Both are application mistakes -- an id nobody tagged, or a proxy used
        // outside a ScrollView -- and both are the shape where a warning would
        // fire on every frame of a perfectly ordinary transition, because the
        // proxy outlives one update and the anchors are rebuilt during it.
        //
        // 當 id 未知、或沒有任何 ScrollView 安裝過 closure 時,靜默處理。
        //
        // 兩者都是應用程式的錯誤——一個沒有人標記過的 id,或是在 ScrollView 之外使用 proxy——
        // 而兩者也都屬於「發出警告會在一次再普通不過的轉場中逐幀觸發」的形狀,因為 proxy 的生命
        // 長於一次更新,而那些 anchor 正是在該次更新期間被重建的。
        guard let widget = anchors[id], let performScroll else { return }
        performScroll(widget, anchor)
    }
}
