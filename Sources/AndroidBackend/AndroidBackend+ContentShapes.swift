import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

// contentShape: the region is scaled to pixels here and kept by ContentShapes.kt;
// CustomContainer's touch dispatch passes a down outside a child's shape on to
// the next child underneath.
// contentShape:區域在此換算為像素，由 ContentShapes.kt 保存;CustomContainer 的觸控分派會把落在子元件
// 形狀外的 down 交給下方的下一個子元件。
extension AndroidBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        guard let region else {
            helpers.setContentShape(widget, [], [], false, true)
            return
        }
        let density = AndroidBackend.density { widget.getResources().getDisplayMetrics().density }
        let pixels = region.scaled(by: Double(density))
        helpers.setContentShape(
            widget,
            pixels.flattenedPoints.map { Float($0) },
            pixels.contourPointCounts.map { Int32($0) },
            pixels.evenOdd,
            false
        )
    }
}
