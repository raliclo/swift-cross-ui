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

    @objc func fire(_ sender: UIRefreshControl) {
        MainActor.assumeIsolated {
            action()
            // Ended here rather than left for the app. `.refreshable`'s action
            // is synchronous in this framework, so by the time it returns the
            // work it represents is done -- a spinner still turning after that
            // is telling the user about a fetch that finished.
            // 在此結束,而不是留給 app 處理。本框架中 `.refreshable` 的動作是同步的,因此當它返回時,
            // 它所代表的工作已經完成——那之後仍在轉的圈,是在向使用者描述一次已經結束的抓取。
            sender.endRefreshing()
        }
    }
}

private var refreshTargetKey: UInt8 = 0

extension UIKitBackend {
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let widget = scrollView as? ScrollWidget else { return }
        let container = widget.scrollView

        guard let handler else {
            container.refreshControl = nil
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

        let target = RefreshActionTarget(action: handler)
        let control = UIRefreshControl()
        control.addTarget(target, action: #selector(RefreshActionTarget.fire(_:)), for: .valueChanged)
        container.refreshControl = control
        objc_setAssociatedObject(container, &refreshTargetKey, target, .OBJC_ASSOCIATION_RETAIN)
    }
}
