import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.FrameClocks {
    /// `CADisplayLink`, which is where the API came from.
    ///
    /// Nothing conditional here, unlike the AppKit half: `CADisplayLink` has
    /// been in UIKit since iOS 3, so there is no fallback to be honest about.
    ///
    /// `.common` mode, not the default: in `.default` the clock STOPS while a
    /// scroll view is tracking a finger, which is exactly when an animation
    /// running alongside the scroll would be most visible stopping.
    ///
    /// 就是 `CADisplayLink`——這個 API 本來就是從這裡來的。
    ///
    /// 此處沒有任何條件判斷，這與 AppKit 那一半不同:`CADisplayLink` 自 iOS 3 起就在 UIKit 裡，
    /// 因此沒有任何「退而求其次」需要誠實說明。
    ///
    /// 使用 `.common` 模式而非預設:在 `.default` 之下，當某個 scroll view 正在追蹤手指時這個時鐘會
    /// **停止**——而那恰好正是「與捲動並行的動畫停下來」最明顯的時刻。
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        frameClockHandler = handler
        let target = UIKitFrameClockTarget()
        let link = CADisplayLink(target: target, selector: #selector(UIKitFrameClockTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        frameClockTarget = target
        frameClockLink = link
    }

    public func stopFrameClock() {
        frameClockLink?.invalidate()
        frameClockLink = nil
        frameClockTarget = nil
        frameClockHandler = nil
    }

    static func deliverFrame(at timestamp: Double) {
        UIKitBackend.currentFrameClockHandler?(timestamp)
    }
}

/// The target a `CADisplayLink` retains.
///
/// **A separate object, and it matters: a display link RETAINS its target.**
/// Making the backend the target would keep the backend alive for as long as
/// the link, and the link alive for as long as the backend -- a cycle that
/// looks like nothing at all until an app with several windows never releases
/// any of them.
///
/// `CADisplayLink` 所持有的那個 target。
///
/// **它是一個獨立的物件，而這件事很重要:display link 會**保留**它的 target。** 若讓 backend 自己
/// 當 target，backend 會活得和那個 link 一樣久、而那個 link 又活得和 backend 一樣久——那是一個
/// 「看起來什麼事都沒有」的循環，直到一支有多個視窗的 app 永遠不釋放它們之中的任何一個。
@MainActor
final class UIKitFrameClockTarget: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        UIKitBackend.deliverFrame(at: link.timestamp)
    }
}
