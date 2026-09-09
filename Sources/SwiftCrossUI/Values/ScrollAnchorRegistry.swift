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

    /// One scroll closure per scroll container, keyed by the container itself.
    ///
    /// **A single closure was wrong and the failure was silent.** Every
    /// ``ScrollView`` under a reader installs one on every update, so with two
    /// scroll views the second overwrote the first -- and then scrolling to an
    /// id inside the FIRST container called the SECOND one, which duly scrolled
    /// to wherever that widget was not. It succeeds, it moves something, and
    /// the row you asked for is still off screen.
    ///
    /// Identity is `===`: `AnyWidget` is a class, and the same scroll view
    /// hands back the same instance across updates, so a container replaces its
    /// own entry rather than adding a second one every frame.
    ///
    /// 每個 scroll container 一個 scroll closure,以該容器本身為索引鍵。
    ///
    /// **只放一個 closure 是錯的,而那個失敗是靜默的。** reader 底下的每一個 ``ScrollView`` 都會在
    /// 每次更新時安裝一個,因此有兩個捲動視圖時,第二個會覆寫第一個——接著「捲到第**一**個容器中的某個
    /// id」會呼叫到第**二**個容器,而它會盡責地捲到「那個 widget 不在的地方」。它成功了、移動了某個東西,
    /// 而你要的那一列仍然在畫面外。
    ///
    /// 身分比較用的是 `===`:`AnyWidget` 是一個 class,而同一個捲動視圖在多次更新之間交回的是同一個
    /// 實例,因此一個容器會替換掉**自己**的項目,而不是每一幀都多加一個。
    private var scrollers: [(container: AnyWidget, perform: (AnyWidget, UnitPoint?) -> Void)] = []

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
        guard let widget = anchors[id] else { return }
        // Every container is asked, and only the one holding the widget acts.
        //
        // `scrollContainer(_:to:anchor:)` is specified to ignore a widget that
        // is not inside it, and all six implementations check -- AppKit and
        // UIKit with `isDescendant(of:)`, GTK through `compute_point` failing,
        // Android through the child's parent chain. So asking all of them is
        // correct, not merely harmless.
        //
        // An earlier draft had the closure return Bool so this could stop at
        // the first one that acted. It did not compile -- the requirement
        // returns Void -- and making it return Bool would have changed the
        // protocol on six backends to save iterating over the one or two scroll
        // views a reader typically holds.
        //
        // 每一個容器都會被問到,而只有持有該 widget 的那一個會動作。
        //
        // `scrollContainer(_:to:anchor:)` 的規格是「忽略不在自己內部的 widget」,而六個實作都有檢查
        // ——AppKit 與 UIKit 用 `isDescendant(of:)`、GTK 靠 `compute_point` 失敗、Android 靠子元件的
        // parent 鏈。因此「全部都問」是正確的,而不只是無害的。
        //
        // 先前的草稿讓該 closure 回傳 Bool,好讓此處能在「第一個動作的容器」停下來。那編不過——
        // 該 requirement 回傳的是 Void——而為了省下「走訪一個 reader 通常持有的那一兩個捲動視圖」
        // 就去改動六個 backend 的 protocol,並不划算。
        for scroller in scrollers {
            scroller.perform(widget, anchor)
        }
    }

    /// Registers a container's scroll closure, replacing the entry for that
    /// same container rather than appending a second one.
    /// 登記某個容器的 scroll closure,替換掉**同一個容器**的既有項目,而不是再附加一個。
    func install(
        container: AnyWidget,
        perform: @escaping (AnyWidget, UnitPoint?) -> Void
    ) {
        if let index = scrollers.firstIndex(where: { $0.container === container }) {
            scrollers[index] = (container, perform)
        } else {
            scrollers.append((container, perform))
        }
    }
}
