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
        // `addFloatingSubview`, not `addSubview`. A plain subview of an
        // NSScrollView goes BEHIND the clip view, which fills the scroll view
        // and draws the document over it -- the button is created, laid out and
        // never seen, which is the failure that looks like the feature was
        // never wired. Measured: P54 rendered with no button at all until this
        // line changed.
        //
        // The axis argument says which direction the view must not scroll with.
        // `.vertical` pins it against vertical scrolling, which is the one this
        // app scrolls in.
        //
        // 使用 `addFloatingSubview` 而非 `addSubview`。NSScrollView 的一般子 view 會被放到 clip view
        // **後方**,而 clip view 填滿整個捲動視圖並在其上繪製 document——那顆按鈕會被建立、被排版,
        // 然後從來沒有人看得到它,而那正是那種「看起來像是這個功能根本沒接上」的失敗。實測:在這一行
        // 改掉之前,P54 畫出來完全沒有按鈕。
        //
        // axis 引數說的是「這個 view 不可以隨哪個方向捲動」。`.vertical` 讓它固定住不隨垂直捲動,
        // 而垂直正是這支 app 會捲的方向。
        button.translatesAutoresizingMaskIntoConstraints = true
        button.sizeToFit()
        // AppKit's origin is bottom-left, so `y: 4` is four points from the
        // BOTTOM. Measured: the button rendered in the bottom-left corner of
        // P54's window while every comment and the app's own text said
        // top-left. Nothing failed -- a button in the wrong corner is still a
        // button, and it is only wrong against a sentence.
        //
        // `.minYMargin` keeps the gap to the top fixed as the window resizes;
        // the default mask would keep the gap to the BOTTOM fixed and walk the
        // button back down the window.
        //
        // AppKit 的原點在左下角,因此 `y: 4` 是距離**底部**四點。實測:那顆按鈕畫在 P54 視窗的
        // 左下角,而每一段註解與這支 app 自己的文字都說是左上角。沒有任何東西失敗——一顆位置錯誤的
        // 按鈕仍然是一顆按鈕,它只是與一句話不符。
        //
        // `.minYMargin` 讓「與頂端的間距」在視窗改變大小時維持固定;預設的 mask 會固定「與**底部**
        // 的間距」,並讓按鈕沿著視窗一路走回下方。
        button.setFrameOrigin(
            NSPoint(x: 4, y: container.bounds.height - button.frame.height - 4)
        )
        button.autoresizingMask = [.minYMargin]
        container.addFloatingSubview(button, for: .vertical)
    }
}
