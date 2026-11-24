@_spi(Backends) import SwiftCrossUI

// A recording conformance, so tests can read the region the shared core
// resolved for each widget.
// 記錄用的 conformance,讓測試能讀到共用核心為每個 widget 解析出的區域。
extension DummyBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        widget.contentShape = region
    }
}
