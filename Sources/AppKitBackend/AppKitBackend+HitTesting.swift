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

/// A backend-owned container that can skip a disabled topmost sibling.
/// Returning nil after calling `super.hitTest` is insufficient: AppKit would
/// stop searching and never reach a clickable sibling underneath. Searching
/// children from front to back gives disabled overlays pass-through semantics.
///
/// 這是 backend 自己擁有、能略過上層停用 sibling 的 container。只呼叫
/// `super.hitTest` 後回傳 nil 並不足夠：AppKit 會停止搜尋，永遠不會抵達
/// 下方可點擊的 sibling。由前到後搜尋 children，才能讓停用 overlay 穿透。
final class AppKitHitTestingContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        for child in subviews.reversed() {
            guard !child.isHidden, child.alphaValue > 0 else { continue }
            let childPoint = convert(point, to: child)
            guard child.bounds.contains(childPoint),
                let candidate = child.hitTest(childPoint)
            else { continue }

            if !AppKitHitTestingRegistry.isDisabled(candidate, through: self) {
                return candidate
            }
        }
        return nil
    }
}
