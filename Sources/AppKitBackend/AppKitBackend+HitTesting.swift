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

/// A backend-owned container that skips disabled topmost siblings.
/// AppKit supplies `point` in this view's own coordinate system. Each child
/// receives a point in its own coordinate system, so the conversion belongs
/// inside the child loop. Returning nil for a disabled candidate then lets the
/// search continue to a clickable sibling underneath.
///
/// 這是 backend 自己擁有、能略過上層停用 sibling 的 container。AppKit 傳入的 `point` 已位於本 view
/// 自身的座標系；每個 child 則需要自己的座標系，因此轉換必須放在 child 迴圈內。若候選 view 被停用，
/// 回傳 nil 讓搜尋繼續尋找下方可點擊的 sibling。
///
/// The previous implementation converted the incoming point from the
/// superview and then passed that container-space point to every child. Both
/// operations used the wrong coordinate space, which made controls such as
/// NSButton and NSScrollView return nil during the Mac P28 test.
///
/// 舊實作先把傳入點從 superview 轉換，再把仍屬於 container 座標系的點傳給每個 child。兩個操作都使用
/// 錯誤的座標系，導致 Mac P28 測試中的 NSButton 與 NSScrollView 回傳 nil。
final class AppKitHitTestingContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        guard bounds.contains(point) else { return nil }

        for child in subviews.reversed() {
            guard !child.isHidden, child.alphaValue > 0 else { continue }
            // No containment check of our own: `hitTest` already answers nil
            // for a point outside the child, and it accounts for the child's
            // own overrides, which a `frame.contains` here would not.
            // 不再自行做 containment 檢查：對落在 child 之外的點，`hitTest` 本來就會回答 nil，
            // 而且它會把 child 自己的覆寫也算進去——那是在此處寫 `frame.contains` 做不到的。
            let childPoint = convert(point, to: child)
            guard let candidate = child.hitTest(childPoint) else { continue }

            if !AppKitHitTestingRegistry.isDisabled(candidate, through: self) {
                return candidate
            }
        }
        return nil
    }
}
