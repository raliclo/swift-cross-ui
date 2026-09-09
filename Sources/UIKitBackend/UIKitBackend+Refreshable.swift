import SwiftCrossUI
import UIKit

/// Holds a refresh action and receives the control's target-action.
///
/// A separate object because `UIRefreshControl` keeps an unowned target, and a
/// closure cannot be one. Kept alive by the control's `associatedObject`, since
/// the control does not retain its target either.
///
/// 持有一個 refresh 動作,並接收該控制項的 target-action。
///
/// 之所以是一個獨立物件,是因為 `UIRefreshControl` 以 unowned 方式持有其 target,而閉包無法擔任
/// target。它由該控制項的 `associatedObject` 保持存活,因為該控制項同樣不會保留它的 target。
final class RefreshActionTarget: NSObject {
    var action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    // `@MainActor` on the method rather than `assumeIsolated` inside it. Under
    // Swift 6 the closure form is `sending 'self' risks causing data races`:
    // `assumeIsolated` takes a closure that captures `self`, and the compiler
    // cannot see that a UIKit target-action only ever arrives on the main
    // thread. `@objc` and `@MainActor` compose, so saying it directly is both
    // true and checkable.
    //
    // 把 `@MainActor` 加在方法上,而不是在方法內部使用 `assumeIsolated`。在 Swift 6 之下,閉包的寫法
    // 會得到 `sending 'self' risks causing data races`:`assumeIsolated` 收的閉包會捕捉 `self`,而
    // 編譯器看不出「UIKit 的 target-action 只會從主執行緒抵達」。`@objc` 與 `@MainActor` 可以並存,
    // 因此直接說出這件事既為真、也可被檢查。
    @MainActor @objc func fire(_ sender: UIRefreshControl) {
        action()
        // Ended here rather than left for the app. `.refreshable`'s action is
        // synchronous in this framework, so by the time it returns the work it
        // represents is done -- a spinner still turning after that is telling
        // the user about a fetch that finished.
        // 在此結束,而不是留給 app 處理。本框架中 `.refreshable` 的動作是同步的,因此當它返回時,
        // 它所代表的工作已經完成——那之後仍在轉的圈,是在向使用者描述一次已經結束的抓取。
        sender.endRefreshing()
    }
}

// `nonisolated(unsafe)` because only this variable's ADDRESS is ever used.
//
// `objc_setAssociatedObject` takes a key by pointer identity; the `UInt8` it
// points at is never read and never written. Swift 6 cannot see that and calls
// a mutable global not concurrency-safe, which is the right default and the
// wrong answer here -- there is no value to race over.
//
// `nonisolated(unsafe)`,因為被用到的只有這個變數的**位址**。
//
// `objc_setAssociatedObject` 是以指標identity 取用 key 的;它所指向的那個 `UInt8` 從未被讀取、
// 也從未被寫入。Swift 6 看不出這一點,於是把一個可變的全域變數判定為非並行安全——那是正確的預設值,
// 但在此處是錯的答案:根本沒有任何值可供競爭。
private nonisolated(unsafe) var refreshTargetKey: UInt8 = 0

extension UIKitBackend {
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let widget = scrollView as? ScrollWidget else { return }

        // The control goes on the scroll view the user can actually drag, and
        // that is not always this one.
        //
        // Every app on this backend is hosted inside a `RootScrollHost`, which
        // is itself a UIScrollView. When the app's own ScrollView sits directly
        // inside it, the two pan gestures compete and the host wins: a
        // UIRefreshControl on the inner view is installed, bounces, and never
        // fires. Measured on P54 -- the control was created with
        // `bounces=true`, `alwaysBounceVertical` was turned on, and a 420 pt
        // drag from the top left the counter at 0. Nothing failed at any point.
        //
        // Perceptually the host IS the scroll view: it is what moves under the
        // finger and what fills the window. Putting the control there is not a
        // workaround for the harness, it is the surface the user pulls.
        //
        // Restricted to `RootScrollHost` rather than "the outermost enclosing
        // UIScrollView", because a ScrollView deliberately nested in another
        // ScrollView should refresh the one it was attached to.
        //
        // 這個控制項要裝在使用者真的拖得動的那個捲動視圖上,而那不一定是眼前這一個。
        //
        // 本 backend 上的每一支 app 都被裝在一個 `RootScrollHost` 之中,而它本身就是一個 UIScrollView。
        // 當 app 自己的 ScrollView 直接位於其中時,兩者的 pan 手勢會競爭,而 host 會勝出:裝在內層
        // view 上的 UIRefreshControl 會被建立、會回彈、而且永遠不會觸發。這在 P54 上實測過——該控制項
        // 以 `bounces=true` 建立、`alwaysBounceVertical` 已開啟,而一次從頂端往下 420 點的拖曳讓計數器
        // 停在 0。整個過程中沒有任何一步失敗。
        //
        // 就感知而言,那個 host **就是**捲動視圖:它才是隨手指移動、並填滿整個視窗的東西。把控制項放在
        // 那裡不是為了遷就測試工具,那就是使用者所拉動的那個表面。
        //
        // 限定為 `RootScrollHost` 而非「最外層的 UIScrollView」,因為一個刻意巢狀在另一個 ScrollView
        // 之中的 ScrollView,應該重新整理它被附加的那一個。
        let container = Self.rootHost(above: widget.view) ?? widget.scrollView

        guard let handler else {
            container.refreshControl = nil
            container.alwaysBounceVertical = false
            objc_setAssociatedObject(container, &refreshTargetKey, nil, .OBJC_ASSOCIATION_RETAIN)
            return
        }

        // Reused when one already exists, and only its closure replaced. A new
        // UIRefreshControl on every update would cancel a refresh already
        // spinning, and `updateScrollContainer` runs on every state change --
        // including the ones the refresh action itself causes.
        // 已經存在時就沿用它,只替換它的閉包。每次更新都建立新的 UIRefreshControl 會取消一次正在轉動
        // 的重新整理,而 `updateScrollContainer` 在每一次狀態改變時都會執行——包括那些由 refresh
        // 動作本身所引起的改變。
        if let existing = objc_getAssociatedObject(container, &refreshTargetKey)
            as? RefreshActionTarget
        {
            existing.action = handler
            return
        }

        // Bouncing is what a pull IS. A UIScrollView whose content is no taller
        // than its frame does not bounce vertically unless told to, and a
        // refresh control on a view that cannot be pulled is installed,
        // correct, and unreachable -- measured on P54, where the probe showed
        // `bounces=true alwaysBounceVertical=false` and two drags produced
        // `refreshes: 0`.
        //
        // Set alongside the control rather than in `updateScrollContainer`,
        // because it is this feature's requirement and not the scroll view's:
        // a scroll view with no refresh handler should keep whatever bounce
        // behaviour its axes asked for.
        //
        // 「會回彈」正是「下拉」這件事本身。一個內容不高於自身框架的 UIScrollView,若不特別交代就不會
        // 在垂直方向回彈,而一個裝在「拉不動的 view」上的 refresh 控制項:裝好了、正確、且碰不到——
        // 這在 P54 上實測過,探針顯示 `bounces=true alwaysBounceVertical=false`,而兩次拖曳的結果是
        // `refreshes: 0`。
        //
        // 與該控制項一起設定,而不是放在 `updateScrollContainer` 裡,因為這是本功能的需求、不是捲動
        // 視圖的需求:一個沒有 refresh handler 的捲動視圖,應該保留它的 axes 所要求的回彈行為。
        container.alwaysBounceVertical = true

        let target = RefreshActionTarget(action: handler)
        let control = UIRefreshControl()
        control.addTarget(target, action: #selector(RefreshActionTarget.fire(_:)), for: .valueChanged)
        container.refreshControl = control
        objc_setAssociatedObject(container, &refreshTargetKey, target, .OBJC_ASSOCIATION_RETAIN)
    }

    /// The `RootScrollHost` this view is inside, if any.
    /// 這個 view 所在的 `RootScrollHost`(若有的話)。
    private static func rootHost(above view: UIView) -> UIScrollView? {
        var candidate: UIView? = view.superview
        while let current = candidate {
            if let host = current as? RootScrollHost { return host }
            candidate = current.superview
        }
        return nil
    }
}
