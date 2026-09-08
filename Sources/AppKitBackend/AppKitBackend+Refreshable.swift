import AppKit
import SwiftCrossUI

/// A refresh affordance for `NSScrollView`.
///
/// **macOS has no pull-to-refresh, and that is a checked claim rather than a
/// remembered one.** `NSScrollView` rubber-bands, and the elasticity can be
/// read back through `contentView.bounds.origin.y` going negative -- but only
/// for events carrying a gesture phase, which a trackpad produces and a mouse
/// wheel does not. `AppKit.NSEvent.Phase` is empty for every event a wheel or a
/// synthesised scroll generates, so a pull-only implementation would work on
/// one input device, do nothing at all on another, and report success either
/// way because no API fails.
///
/// So the action gets a button, pinned to the top-leading corner of the scroll
/// view and floating above the content. It is what a Mac application would do
/// anyway -- a refresh here is a toolbar item or ⌘R, not a gesture -- and it
/// can be pressed by a mouse, by a trackpad, and by an action file.
///
/// 給 `NSScrollView` 的重新整理操作方式。
///
/// **macOS 沒有下拉重新整理,而這是查證過的主張,不是憑印象的。** `NSScrollView` 會彈性回彈,而那份
/// 彈性可以透過 `contentView.bounds.origin.y` 轉為負值讀出來——但那只發生在帶有 gesture phase 的
/// 事件上,而觸控板會產生那種事件,滑鼠滾輪不會。對於滾輪或合成捲動所產生的每一個事件,
/// `AppKit.NSEvent.Phase` 都是空的,因此一個「只靠下拉」的實作會在某一種輸入裝置上可用、在另一種上
/// 完全沒有反應,而且兩種情況都會回報成功,因為沒有任何 API 失敗。
///
/// 所以這個動作得到的是一顆按鈕,釘在捲動視圖的左上角、浮在內容之上。那本來就是一個 Mac 應用程式
/// 會做的事——在這裡「重新整理」是一個工具列項目或 ⌘R,不是一個手勢——而且它按得動:滑鼠可以、
/// 觸控板可以、動作檔也可以。
final class RefreshButton: NSButton {
    var refreshAction: (@MainActor @Sendable () -> Void)?

    init(action: @escaping @MainActor @Sendable () -> Void) {
        super.init(frame: .zero)
        refreshAction = action
        title = "Refresh"
        bezelStyle = .rounded
        controlSize = .small
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        self.action = #selector(fire)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        MainActor.assumeIsolated { refreshAction?() }
    }
}

extension AppKitBackend {
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let container = scrollView as? NSScrollView else { return }
        let existing = container.subviews.compactMap { $0 as? RefreshButton }.first

        guard let handler else {
            existing?.removeFromSuperview()
            return
        }

        // Only the closure is replaced when the button is already there.
        // Rebuilding it would drop it out of the view hierarchy and back in on
        // every update, which is a visible flicker on a view that is meant to
        // sit still.
        // 按鈕已經在時只替換它的閉包。重建它會讓它在每一次更新時離開再回到 view 階層,而對一個
        // 「本來就該待著不動」的 view 來說,那是看得見的閃爍。
        if let existing {
            existing.refreshAction = handler
            return
        }

        let button = RefreshButton(action: handler)
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
        ])
    }
}
