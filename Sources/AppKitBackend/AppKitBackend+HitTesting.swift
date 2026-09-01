import AppKit
import Foundation
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.HitTesting {
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        if allowsHitTesting {
            AppKitHitTestingRegistry.disabledViews.remove(widget)
        } else {
            AppKitHitTestingRegistry.disabledViews.add(widget)
        }
    }
}

/// Keeps hit-testing state outside widgets because a modifier may receive an
/// AppKit control that this backend did not create as a subclass. Weak storage
/// lets removed view trees disappear without a cleanup pass.
///
/// 將 hit-testing 狀態放在 widget 外部，因為 modifier 可能收到 backend 沒有以
/// subclass 建立的 AppKit control。弱引用儲存可讓移除的 view tree 自動消失，
/// 不需要額外清理流程。
@MainActor
private enum AppKitHitTestingRegistry {
    static let disabledViews = NSHashTable<NSView>.weakObjects()

    static func isDisabled(_ view: NSView, through ancestor: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if disabledViews.contains(view) {
                return true
            }
            if view === ancestor {
                break
            }
            current = view.superview
        }
        return false
    }
}

/// **This was reverted once, on 2026-08-27, and had to be restored.**
/// `e25b3a65 Fix AppKit hit testing and Swift 6 replay build` replaced the
/// implementation below with the one it describes as previous -- treating
/// `point` as though it were already in this view's space, and converting it
/// into each child's -- and rewrote the comment to assert that AppKit "supplies
/// `point` in this view's own coordinate system". It does not; the header for
/// `hitTest(_:)` says "a point that is in the coordinate system of the
/// receiver's superview". The commit message claimed a fix, so for five days
/// the tree carried a wrong implementation under a comment stating the wrong
/// premise, and a todo entry recording it as fixed.
///
/// Measured again 2026-09-01 with that version in the tree: P21's button
/// reported `clicks: 0` for a click at its own centre, P28's counter stayed at
/// 0, and P26's tab strip still worked -- the same split as before the first
/// fix, because the container-at-superview-origin case is the one both wrong
/// versions get right.
///
/// **此處曾於 2026-08-27 被反轉一次，必須重新還原。**
/// `e25b3a65 Fix AppKit hit testing and Swift 6 replay build` 把下方的實作換成了它自己稱為「舊實作」
/// 的那一個——把 `point` 當成已位於本 view 的座標系，再轉換進每個 child 的座標系——並改寫註解，
/// 斷言 AppKit「傳入的 `point` 已位於本 view 自身的座標系」。並非如此；`hitTest(_:)` 的標頭寫的是
/// 「位於接收者之 superview 座標系中的點」。由於該 commit 訊息宣稱這是一次修復，這棵樹在五天之內
/// 帶著一個錯誤的實作、一段陳述錯誤前提的註解，以及一則記錄「已修復」的 todo 條目。
///
/// 2026-09-01 在該版本仍在樹中的情況下再次量測：P21 的按鈕對其自身中心的點擊回報 `clicks: 0`、
/// P28 的計數器停留在 0，而 P26 的分頁列仍然可用——與第一次修復之前完全相同的分界，因為
/// 「container 恰好位於 superview 原點」正是兩個錯誤版本都會答對的那個情況。
///
/// A backend-owned container that can skip a disabled topmost sibling.
/// Returning nil after calling `super.hitTest` is insufficient: AppKit would
/// stop searching and never reach a clickable sibling underneath. Searching
/// children from front to back gives disabled overlays pass-through semantics.
///
/// 這是 backend 自己擁有、能略過上層停用 sibling 的 container。只呼叫
/// `super.hitTest` 後回傳 nil 並不足夠：AppKit 會停止搜尋，永遠不會抵達
/// 下方可點擊的 sibling。由前到後搜尋 children，才能讓停用 overlay 穿透。
/// `point` arrives in this view's **superview** coordinate space, and
/// `child.hitTest(_:)` wants a point in the *child's* superview space -- which
/// is this view's own space. So exactly one conversion is needed, at the top,
/// and the same converted point then goes to every child unchanged.
///
/// This had two frame-of-reference errors at once, which is why fixing either
/// one alone made it fail differently rather than work. It converted `point`
/// into each child's own space, having first treated it as though it were
/// already in this view's space:
///
///     let childPoint = convert(point, to: child)      // wrong source space
///     child.hitTest(childPoint)                       // wrong argument space
///
/// Measured on macOS 2026-08-27: `hitTest` returned nil for an NSButton and an
/// NSScrollView at their exact centres, while a text field still resolved. Work
/// it through for the button at frame (114, 212, 52, 27) and point (140, 225):
/// `childPoint` is (26, 13), which *is* inside the button's bounds, so the
/// containment check passed -- and then `button.hitTest((26, 13))` read (26, 13)
/// as a point in this container's space, compared it against the button's own
/// frame at x 114...166, y 212...239, and correctly answered nil.
///
/// Passing `point` straight to `child.hitTest` was tried on the Mac and made
/// the text field stop resolving too. That is consistent rather than
/// contradictory: it corrects the second error and leaves the first, so it is
/// right only while this container sits at its superview's origin.
///
/// `point` 抵達時位於本 view 的 **superview** 座標系，而 `child.hitTest(_:)` 要的是 child 的
/// superview 座標系——也就是本 view 自己的座標系。因此只需要在最上方做一次轉換，之後同一個轉換
/// 後的點原封不動交給每一個 child。
///
/// 此處原本同時存在兩個座標系錯誤，這正是「只修其中一個」會換一種方式壞掉、而非修好的原因。它把
/// `point` 當成已經位於本 view 的座標系，再轉換進每個 child 自己的座標系。
///
/// 於 2026-08-27 在 macOS 上實測：對 NSButton 與 NSScrollView 的正中心，`hitTest` 回傳 nil，而文字
/// 欄位仍可解析。以 frame 為 (114, 212, 52, 27) 的按鈕、點 (140, 225) 推算：`childPoint` 為
/// (26, 13)，它**確實**落在該按鈕的 bounds 內，因此第二道 containment 檢查通過——接著
/// `button.hitTest((26, 13))` 把 (26, 13) 讀作 container 座標系中的點，拿去與自己位於
/// x 114...166、y 212...239 的 frame 比對，於是正確地回答了 nil。
///
/// Mac 端試過把 `point` 直接傳給 `child.hitTest`，結果連文字欄位也無法解析。這與上述並不矛盾，
/// 反而一致：那修正了第二個錯誤卻留下第一個，因此只有在本 container 恰好位於其 superview 原點時
/// 才會是對的。
final class AppKitHitTestingContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        // No superview means no conversion to make, and `point` is already in
        // the only space there is.
        // 沒有 superview 就沒有轉換可做，此時 `point` 已位於唯一存在的那個座標系。
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(localPoint) else { return nil }

        for child in subviews.reversed() {
            guard !child.isHidden, child.alphaValue > 0 else { continue }
            // No containment check of our own: `hitTest` already answers nil
            // for a point outside the child, and it accounts for the child's
            // own overrides, which a `frame.contains` here would not.
            // 不再自行做 containment 檢查：對落在 child 之外的點，`hitTest` 本來就會回答 nil，
            // 而且它會把 child 自己的覆寫也算進去——那是在此處寫 `frame.contains` 做不到的。
            guard let candidate = child.hitTest(localPoint) else { continue }

            if !AppKitHitTestingRegistry.isDisabled(candidate, through: self) {
                return candidate
            }
        }
        return nil
    }
}
