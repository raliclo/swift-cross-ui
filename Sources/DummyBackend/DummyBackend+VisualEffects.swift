@_spi(Backends) import SwiftCrossUI

// A recording conformance, so tests can read what the shared core commits to a
// backend: the effect each container was last given, and every one in order.
// 記錄用的 conformance,讓測試能讀到共用核心交給 backend 的值：每個容器最後拿到的效果，
// 以及依序拿到的每一個。
extension DummyBackend: BackendFeatures.VisualEffects {
    public class VisualEffectContainer: Widget {
        public var child: Widget
        /// The effect last set; `.identity` before the first.
        /// 最後一次設定的效果;第一次之前為 `.identity`。
        public var effect = VisualEffect.identity
        /// Every effect set, in order. / 依序設定過的每個效果。
        public var history: [VisualEffect] = []

        public init(child: Widget) {
            self.child = child
        }

        public override func getChildren() -> [Widget] {
            [child]
        }
    }

    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        VisualEffectContainer(child: child)
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        let container = widget as! VisualEffectContainer
        container.effect = effect
        container.history.append(effect)
    }
}
