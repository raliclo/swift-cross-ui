import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        AppKitContentShapes.set(region, for: widget)
    }
}

/// The content shapes of AppKit views, consulted by
/// `AppKitHitTestingContainer.hitTest`.
///
/// Kept outside the views for the reason `AppKitHitTestingRegistry` is: the
/// widget may be any `NSView`, not a subclass this backend can give an
/// override. The container asks about every view between itself and the view
/// a child's `hitTest` returned, so a shape on a plain `NSView` wrapper -- the
/// tap gesture container, whose click target is a sibling drawn over the
/// content -- still counts. A point outside makes the container go on to the
/// next child underneath, which is what passing through means.
///
/// AppKit view 的 content shape,由 `AppKitHitTestingContainer.hitTest` 查詢。
///
/// 與 `AppKitHitTestingRegistry` 相同的理由而放在 view 之外：widget 可能是任何 `NSView`,不一定
/// 是本 backend 能加上覆寫的 subclass。容器會詢問自身與 child 的 `hitTest` 所回傳之 view 之間的每一個
/// view,因此設在一般 `NSView` 包裝層上的形狀——點擊手勢的容器，其點擊目標是覆蓋在內容之上的兄弟
/// 元件——仍然算數。點落在形狀外時，容器會繼續詢問下方的下一個 child,那就是「穿透」的意思。
@MainActor
enum AppKitContentShapes {
    private final class Box {
        let region: HitRegion
        init(_ region: HitRegion) { self.region = region }
    }

    /// Weak keys, so a removed view tree takes its entries with it.
    /// 弱引用的 key,讓被移除的 view 樹一併帶走自己的項目。
    private static let regions = NSMapTable<NSView, Box>.weakToStrongObjects()

    static func set(_ region: HitRegion?, for view: NSView) {
        if let region {
            regions.setObject(Box(region), forKey: view)
        } else {
            regions.removeObject(forKey: view)
        }
    }

    /// Whether `point`, in `view`'s own coordinates, is outside `view`'s shape.
    /// `point`(位於 `view` 自身座標)是否落在 `view` 的形狀之外。
    static func excludes(_ point: NSPoint, of view: NSView) -> Bool {
        guard regions.count > 0, let box = regions.object(forKey: view) else { return false }
        // The region is top-left origin, y down; an unflipped view counts y up.
        // 區域以左上角為原點、y 向下;未翻轉的 view 的 y 則向上計。
        let x = point.x - view.bounds.minX
        let y = view.isFlipped ? point.y - view.bounds.minY : view.bounds.maxY - point.y
        return !box.region.contains([Double(x), Double(y)])
    }

    /// Whether `point`, in `container`'s coordinates, is outside the shape of
    /// `candidate` or of any view between it and `container`.
    /// `point`(位於 `container` 座標)是否落在 `candidate` 或它與 `container` 之間任何 view 的形狀之外。
    static func excludes(_ point: NSPoint, in container: NSView, below candidate: NSView) -> Bool {
        guard regions.count > 0 else { return false }
        var current: NSView? = candidate
        while let view = current, view !== container {
            if regions.object(forKey: view) != nil,
                excludes(view.convert(point, from: container), of: view)
            {
                return true
            }
            current = view.superview
        }
        return false
    }
}
