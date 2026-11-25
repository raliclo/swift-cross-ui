import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        UIKitContentShapes.set(region, for: widget.view)
    }
}

/// The content shapes of UIKit views, consulted by `BaseViewWidget.hitTest`
/// and by `TappableWidget`'s recogniser delegate.
///
/// Kept outside the views because a widget's view is not always a
/// `BaseViewWidget` -- a controller-backed widget such as `TappableWidget`
/// has a plain `UIView`. `BaseViewWidget.hitTest` asks about its own shape
/// and about each child's before calling into the child, so a shape on a
/// plain view under a backend container still makes the touch go on to the
/// next child underneath.
///
/// UIKit view 的 content shape,由 `BaseViewWidget.hitTest` 與 `TappableWidget` 的辨識器委派查詢。
///
/// 放在 view 之外，因為 widget 的 view 不一定是 `BaseViewWidget`——像 `TappableWidget` 這種由
/// controller 支撐的 widget,其 view 是一般的 `UIView`。`BaseViewWidget.hitTest` 會先過問自己的
/// 形狀，並在呼叫每個 child 之前過問該 child 的形狀，因此設在 backend 容器下一般 view 上的形狀，
/// 仍會讓觸控繼續前往下方的下一個 child。
@MainActor
enum UIKitContentShapes {
    private final class Box {
        let region: HitRegion
        init(_ region: HitRegion) { self.region = region }
    }

    /// Weak keys, so a removed view tree takes its entries with it.
    /// 弱引用的 key,讓被移除的 view 樹一併帶走自己的項目。
    private static let regions = NSMapTable<UIView, Box>.weakToStrongObjects()

    static func set(_ region: HitRegion?, for view: UIView) {
        if let region {
            regions.setObject(Box(region), forKey: view)
        } else {
            regions.removeObject(forKey: view)
        }
    }

    /// Whether `point`, in `view`'s own coordinates (top-left origin, y down,
    /// as the region is), is outside `view`'s shape.
    /// `point`(位於 `view` 自身座標，左上角為原點、y 向下，與區域相同)是否落在 `view` 的形狀之外。
    static func excludes(_ point: CGPoint, of view: UIView) -> Bool {
        guard regions.count > 0, let box = regions.object(forKey: view) else { return false }
        let x = point.x - view.bounds.minX
        let y = point.y - view.bounds.minY
        return !box.region.contains([Double(x), Double(y)])
    }

    /// Whether `point`, in `view`'s coordinates, is outside the shape of
    /// `view` or of any view above it. For input that is not decided by
    /// `hitTest` alone -- a hover recogniser keeps reporting while the pointer
    /// is anywhere over its view, pointer styles and drop sessions ask about a
    /// location -- and has to consult the shapes itself. `convert` carries
    /// each view's transform, so a geometric effect on the way is respected.
    ///
    /// `point`(位於 `view` 座標)是否落在 `view` 或其上任何 view 的形狀之外。給不只由 `hitTest`
    /// 決定的輸入使用——懸停辨識器只要指標在其 view 上任何位置就持續回報，指標樣式與拖放 session 會詢問
    /// 某個位置——它們必須自己查詢形狀。`convert` 會帶上每個 view 的 transform,因此途中的幾何效果
    /// 也會被考慮。
    static func excludes(_ point: CGPoint, from view: UIView) -> Bool {
        guard regions.count > 0 else { return false }
        var current: UIView? = view
        while let candidate = current {
            if regions.object(forKey: candidate) != nil,
                excludes(view.convert(point, to: candidate), of: candidate)
            {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}
