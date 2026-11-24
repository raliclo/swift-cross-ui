import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// zIndex(_:) orders siblings for drawing without touching layout.
/// zIndex(_:) 為兄弟元件排定繪製順序，不影響排版。
@MainActor
struct ZIndexTests {
    func zIndex<V: View>(of view: V) -> Double {
        ViewGraphHelpers.computeLayout(of: view).preferences.zIndex
    }

    @Test("zIndex survives a one-child wrapper and is not taken by a stack")
    func travelsLikeLayoutPriority() {
        #expect(zIndex(of: Color.red) == 0)
        #expect(zIndex(of: Color.red.zIndex(2)) == 2)
        #expect(zIndex(of: Color.red.zIndex(2).padding(4).frame(width: 10, height: 10)) == 2)
        #expect(zIndex(of: HStack { Color.red.zIndex(2); Color.blue }) == 0)
    }

    @Test("Drawing order sorts by zIndex and keeps declaration order for ties")
    func drawingOrder() {
        func results(_ values: [Double]) -> [ViewLayoutResult] {
            values.map {
                ViewLayoutResult(size: .zero, preferences: PreferenceValues.default.with(\.zIndex, $0))
            }
        }
        #expect(LayoutSystem.drawingOrder(of: results([0, 0, 0])) == nil)
        #expect(LayoutSystem.drawingOrder(of: results([2, 0, 0])) == [1, 2, 0])
        #expect(LayoutSystem.drawingOrder(of: results([0, -1, 0])) == [1, 0, 2])
        #expect(LayoutSystem.drawingOrder(of: results([1, 3, 1, 0.5])) == [3, 0, 2, 1])
    }

    @Test("zIndex leaves the layout alone")
    func layoutUnchanged() {
        let plain = ViewGraphHelpers.computeLayout(
            of: ZStack { Color.red.frame(width: 40, height: 20); Color.blue.frame(width: 10, height: 30) }
        )
        let ordered = ViewGraphHelpers.computeLayout(
            of: ZStack {
                Color.red.frame(width: 40, height: 20).zIndex(1)
                Color.blue.frame(width: 10, height: 30)
            }
        )
        #expect(plain.size == ordered.size)
    }
}
