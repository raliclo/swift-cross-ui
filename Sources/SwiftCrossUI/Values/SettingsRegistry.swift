import Foundation
/// Where the ``Settings`` scene leaves its content, and where ``OpenSettingsAction``
/// looks for a way to show it.
///
/// A class carried in the environment, for the same reason ``ScrollAnchorRegistry``
/// is one: the scene that OWNS the settings content and the view that can PRESENT
/// it are in different parts of the tree, and the environment only travels
/// downwards. The scene writes; whichever side can act reads.
///
/// **There are two ways to show settings and the registry holds both, because
/// which one is available is a property of the backend rather than of the app.**
/// A backend with multiple windows opens a window; one without presents a sheet
/// over the window it already has. Android is why the second exists and is not
/// optional: `AndroidBackend.createWindow` returns a fresh `Window()` value with
/// a `TODO` beside it, so a window-based Settings there would be **silently
/// invisible** -- the exact shape CLAUDE.md forbids, since a truthful report of
/// a missing feature is not the same as a working feature.
///
/// ``Settings`` 這個 scene 把它的內容留在哪裡,以及 ``OpenSettingsAction`` 到哪裡去找「顯示它的辦法」。
///
/// 這是一個放在 environment 中傳遞的 class,理由與 ``ScrollAnchorRegistry`` 相同:**擁有**設定內容的
/// 那個 scene,與**能夠呈現**它的那個 view,位於樹的不同部分,而 environment 只會往下走。scene 負責寫,
/// 有能力動作的那一方負責讀。
///
/// **顯示設定有兩種方式,而 registry 兩種都持有,因為「哪一種可用」是 backend 的性質、不是 app 的。**
/// 有多視窗的 backend 開一個視窗;沒有的則在既有的視窗上呈現一個 sheet。第二種之所以存在、而且不是選配,
/// 原因是 Android:`AndroidBackend.createWindow` 回傳的是一個旁邊還留著 `TODO` 的新 `Window()` 值,
/// 因此在那裡以視窗為基礎的 Settings 會**靜默地隱形**——那正是 CLAUDE.md 所禁止的形狀,因為「如實回報
/// 一項缺失的功能」與「擁有一項可運作的功能」是兩回事。
///
/// **Not `@MainActor`, and that is a compiler constraint rather than a choice.**
/// `EnvironmentValues` builds its defaults in a nonisolated context, so a
/// main-actor-isolated default is rejected outright:
/// *"main actor-isolated default value in a nonisolated context"*. Both stored
/// properties are only ever touched during scene and view updates, which are
/// already on the main actor, so `@unchecked Sendable` states what is true
/// rather than papering over a race.
///
/// **不標 `@MainActor`,而那是編譯器的限制而非選擇。** `EnvironmentValues` 是在 nonisolated 的情境下
/// 建構它的預設值,因此一個以 main actor 隔離的預設值會被直接拒絕:
/// *「main actor-isolated default value in a nonisolated context」*。這兩個儲存屬性只會在 scene 與
/// view 的更新期間被碰到,而那些本來就在 main actor 上,因此 `@unchecked Sendable` 陳述的是事實,
/// 而不是把一個競爭條件糊過去。
public final class SettingsRegistry: @unchecked Sendable {
    /// The settings content, type-erased.
    ///
    /// ``AnyView`` because the presenting side cannot name the app's content
    /// type: the sheet is attached inside ``WindowReference``, which is generic
    /// over the WINDOW's content, not over the settings scene's. Erasure costs
    /// an extra node per presentation and buys the only arrangement in which one
    /// window can show another scene's view.
    ///
    /// 那份設定內容,型別已被抹除。
    ///
    /// 使用 ``AnyView``,是因為呈現的那一方無法指名 app 的內容型別:那個 sheet 是在
    /// ``WindowReference`` 內部掛上的,而它泛型化的對象是**該視窗**的內容,不是設定 scene 的內容。
    /// 型別抹除的代價是每次呈現多一個節點,換來的是「一個視窗能顯示另一個 scene 的 view」的唯一安排。
    var content: (@MainActor () -> AnyView)?

    /// Set by whichever presenter is in play, and called by ``OpenSettingsAction``.
    ///
    /// `nil` means nothing can show settings yet -- no ``Settings`` scene in the
    /// app's body, or the window hosting the sheet has not appeared. The action
    /// warns in that case rather than doing nothing, because "I pressed the menu
    /// item and no window appeared" is otherwise indistinguishable from a
    /// feature that was never declared.
    ///
    /// 由當下負責呈現的那一方設定,並由 ``OpenSettingsAction`` 呼叫。
    ///
    /// `nil` 代表目前沒有任何東西能顯示設定——app 的 body 裡沒有 ``Settings`` scene,或是承載該 sheet
    /// 的視窗尚未出現。此時該 action 會發出警告而不是默不作聲,因為「我按了選單項目,卻沒有視窗出現」
    /// 否則會與「這項功能從未被宣告過」無從分辨。
    var open: (@MainActor () -> Void)?

    /// Installs a presenter and, if a request is already waiting, honours it.
    ///
    /// A method rather than a `didSet` on ``open``: the closure is
    /// `@MainActor`, and a property observer runs in the nonisolated context of
    /// the property itself, where calling it is *"call to main actor-isolated
    /// let 'open' in a synchronous nonisolated context"*. The presenter installs
    /// from a view update, which is already on the main actor, so the isolation
    /// belongs on the method.
    ///
    /// 安裝一個呈現者；若已有請求在等待，則就地履行它。
    ///
    /// 使用方法而非 ``open`` 上的 `didSet`：那個 closure 是 `@MainActor` 的，而屬性觀察器執行於該屬性
    /// 自身的 nonisolated 情境中，在那裡呼叫它會得到
    /// *「call to main actor-isolated let 'open' in a synchronous nonisolated context」*。
    /// 呈現者是在一次 view 更新中安裝的，而那本來就在 main actor 上，因此隔離標註屬於這個方法。
    @MainActor
    func installPresenter(_ presenter: @escaping @MainActor () -> Void) {
        open = presenter
        guard hasPendingOpen else { return }
        hasPendingOpen = false
        // **Next turn, not this one, and calling it inline does nothing
        // visible.** The presenter on a single-window backend sets a view's
        // `@State`, and this method is reached from that view's `onAppear`,
        // which runs inside the update that is already committing it. The flip
        // is swallowed there: measured 2026-09-09 on UIKit, an inline call
        // logged the presenter running and left the sheet unpresented, while
        // the identical request two seconds later presented it.
        //
        // **下一輪，而不是這一輪；直接就地呼叫不會產生任何看得見的效果。** 在單視窗的 backend 上，
        // 那個 presenter 設定的是某個 view 的 `@State`，而本方法是從該 view 的 `onAppear` 抵達的
        // ——那正處於「已經在提交它」的那一次更新之內。狀態翻轉會在那裡被吞掉：2026-09-09 於 UIKit
        // 實測，就地呼叫記錄了 presenter 有執行，而 sheet 未被呈現；兩秒後完全相同的請求則呈現了它。
        DispatchQueue.main.async {
            presenter()
        }
    }

    /// Set when ``open`` was called before anything could present settings.
    ///
    /// **This exists because of an ordering that is invisible and reasonable.**
    /// On a single-window backend the presenter is installed from the sheet
    /// host's `onAppear`, and a root view's own `onAppear` fires FIRST -- so an
    /// app calling `openSettings()` as it appears got the warning and nothing
    /// else. Measured 2026-09-09 on UIKit: the immediate call logged
    /// "nothing can present settings" while the identical call two seconds later
    /// presented the sheet. Nothing had failed and nothing was misconfigured;
    /// the request simply arrived first.
    ///
    /// One pending request rather than a queue: two `openSettings()` calls
    /// before the presenter exists still mean one settings screen.
    ///
    /// 當 ``open`` 在「還沒有任何東西能呈現設定」之前就被呼叫時設立。
    ///
    /// **它之所以存在，是因為一個看不見、卻又合情合理的順序。** 在單視窗的 backend 上，呈現者是由
    /// sheet host 的 `onAppear` 安裝的，而 root view 自己的 `onAppear` 會**先**觸發——因此一個
    /// 「在出現時就呼叫 `openSettings()`」的 app，得到的只有那句警告。2026-09-09 於 UIKit 實測：
    /// 立即呼叫記下了「nothing can present settings」，而兩秒後完全相同的呼叫則呈現出了 sheet。
    /// 沒有任何東西失敗，也沒有任何設定有誤；那個請求只是先到了。
    ///
    /// 只記一個待處理請求而非一個佇列：在呈現者存在之前呼叫兩次 `openSettings()`，仍然只代表一個
    /// 設定畫面。
    var hasPendingOpen = false

    public init() {}

}
