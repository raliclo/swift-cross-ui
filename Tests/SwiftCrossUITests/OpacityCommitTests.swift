import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

/// What the shared core commits to a backend's ``BackendFeatures/VisualEffects``,
/// read back from DummyBackend's recording containers.
///
/// 共用核心交給 backend 的 ``BackendFeatures/VisualEffects`` 的值，從 DummyBackend 的記錄容器讀回。
@MainActor
@Suite("Opacity commits")
struct OpacityCommitTests {
    /// Every effect container under `root`, outermost first.
    /// `root` 之下的每個效果容器，由外而內。
    func containers(under root: DummyBackend.Widget) -> [DummyBackend.VisualEffectContainer] {
        var found: [DummyBackend.VisualEffectContainer] = []
        var queue = [root]
        while !queue.isEmpty {
            let widget = queue.removeFirst()
            queue += widget.getChildren()
            if let container = widget as? DummyBackend.VisualEffectContainer {
                found.append(container)
            }
        }
        return found
    }

    @Test("Nested opacities each commit their own value to their own container")
    func nestedOpacity() throws {
        let node = ViewGraphHelpers.committedNode(for: Text("a").opacity(0.5).opacity(0.5))
        let found = containers(under: node.widget)
        // Two containers, each 0.5: the product 0.25 comes from the nesting, so a
        // container that received 0.25 would be the effect applied twice.
        // 兩個容器，各為 0.5:乘積 0.25 來自巢狀，若某個容器收到 0.25 就是效果被套用了兩次。
        #expect(found.count == 2)
        #expect(found.map(\.effect.opacity) == [0.5, 0.5])
    }

    @Test("Out-of-range opacity is clamped to 0...1", arguments: [(1.5, 1.0), (-0.5, 0.0)])
    func clampedOpacity(given: Double, committed: Double) throws {
        let node = ViewGraphHelpers.committedNode(for: Text("a").opacity(given))
        let container = try #require(containers(under: node.widget).first)
        #expect(container.effect.opacity == committed)
        #expect(container.history.allSatisfy { (0...1).contains($0.opacity) })
    }

    @Test("A spring's overshoot is clamped where only a range makes sense")
    func clampedOvershoot() throws {
        // What a spring past its target hands the setter mid-flight.
        // 彈簧越過目標時在途中交給 setter 的值。
        let container = DummyBackend.VisualEffectContainer(child: ViewGraphHelpers.backend.createContainer())
        let setter = try #require(
            VisualEffectWidgets.setter(for: container, backend: ViewGraphHelpers.backend)
        )
        setter(VisualEffect(opacity: 1.08, blurRadius: -0.4, saturation: 1.3, grayscale: 1.1))
        #expect(container.effect.opacity == 1)
        #expect(container.effect.blurRadius == 0)
        #expect(container.effect.grayscale == 1)
        // Saturation above 1 is a real setting (oversaturation), so it passes.
        // 大於 1 的 saturation 是真實的設定(過飽和),所以原樣通過。
        #expect(container.effect.saturation == 1.3)
    }
}
