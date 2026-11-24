@_spi(Backends) import SwiftCrossUI

// A recording conformance, as for visual effects, so tests can read the
// transform the shared core gives a geometric-effect container -- for
// `controlSize(_:)`'s scale among others.
// 記錄用的 conformance(與視覺效果相同)，讓測試能讀到共用核心交給幾何效果容器的變換——
// `controlSize(_:)` 的縮放即為其一。
extension DummyBackend: BackendFeatures.GeometricEffects {
    public class GeometricEffectContainer: Widget {
        public var child: Widget
        /// The transform last set; `.identity` before the first.
        /// 最後一次設定的變換；第一次之前為 `.identity`。
        public var transform = AffineTransform.identity

        public init(child: Widget) {
            self.child = child
        }

        public override func getChildren() -> [Widget] {
            [child]
        }
    }

    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        GeometricEffectContainer(child: child)
    }

    public func setGeometricEffect(_ transform: AffineTransform, ofWidget widget: Widget) {
        (widget as? GeometricEffectContainer)?.transform = transform
    }
}
