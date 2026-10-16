import Testing

@testable import SwiftCrossUI

/// GSAP's ScrollTrigger under SwiftUI's names: where a view is relative to the
/// viewport, the phase and effect `scrollTransition` draws from it, and the hub
/// that hands a scroll view's geometry to its listeners -- all without a backend.
///
/// GSAP 的 ScrollTrigger,以 SwiftUI 的名稱:view 相對於視口的位置、`scrollTransition` 據此畫出的階段與
/// 效果，以及把捲動視圖幾何交給聆聽者的 hub——全部不需要 backend。
@MainActor
@Suite("Scroll transitions (ScrollTrigger)")
struct ScrollTransitionTests {
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test("visible(1): identity while whole, toward ±1 as it leaves either edge")
    func visibleWhole() {
        let threshold = ScrollTransitionConfiguration.Threshold.visible(1)
        func at(_ start: Double) -> Double {
            ScrollTransitionMath.position(start: start, length: 100, viewport: 400, threshold: threshold)
        }
        #expect(at(0) == 0)
        #expect(at(300) == 0)
        #expect(near(at(-25), -0.25))
        #expect(near(at(350), 0.5))
        #expect(at(-100) == -1)
        #expect(at(500) == 1)
        #expect(at(-300) == -1)
    }

    @Test("visible(0.5) reaches identity at half shown; .visible at any part")
    func visibleHalf() {
        let half = ScrollTransitionConfiguration.Threshold.visible(0.5)
        #expect(ScrollTransitionMath.position(start: 350, length: 100, viewport: 400, threshold: half) == 0)
        #expect(near(
            ScrollTransitionMath.position(start: 375, length: 100, viewport: 400, threshold: half), 0.5))
        let any = ScrollTransitionConfiguration.Threshold.visible
        #expect(ScrollTransitionMath.position(start: 399, length: 100, viewport: 400, threshold: any) == 0)
        #expect(ScrollTransitionMath.position(start: 400, length: 100, viewport: 400, threshold: any) == 1)
    }

    @Test("centered: identity only at the centre, ±1 once it has left")
    func centered() {
        let centered = ScrollTransitionConfiguration.Threshold.centered
        #expect(ScrollTransitionMath.position(start: 150, length: 100, viewport: 400, threshold: centered) == 0)
        #expect(near(
            ScrollTransitionMath.position(start: 275, length: 100, viewport: 400, threshold: centered), 0.5))
        #expect(ScrollTransitionMath.position(start: -100, length: 100, viewport: 400, threshold: centered) == -1)
    }

    @Test("Phase follows the sign; the visible share is what onScrollVisibilityChange reads")
    func phaseAndShare() {
        #expect(ScrollTransitionMath.phase(-0.2) == .topLeading)
        #expect(ScrollTransitionMath.phase(0) == .identity)
        #expect(ScrollTransitionMath.phase(1) == .bottomTrailing)
        #expect(ScrollTransitionPhase.topLeading.value == -1)
        #expect(ScrollTransitionPhase.identity.isIdentity)
        #expect(near(ScrollTransitionMath.visibleShare(start: 360, length: 80, viewport: 400), 0.5))
        #expect(ScrollTransitionMath.visibleShare(start: 0, length: 80, viewport: 400) == 1)
        #expect(ScrollTransitionMath.visibleShare(start: -90, length: 80, viewport: 400) == 0)
    }

    @Test("Effects compose as SwiftUI's VisualEffect modifiers do, and interpolate")
    func effects() {
        let edge = ScrollTransitionEffect()
            .opacity(0.5).opacity(0.5)
            .scaleEffect(0.8)
            .offset(x: 10).offset(y: 4)
            .rotationEffect(.degrees(30))
            .blur(radius: 2)
        #expect(edge.visual.opacity == 0.25)
        #expect(near(edge.geometric.scale.x, 0.8))
        #expect(edge.geometric.translation == SIMD2(10, 4))
        #expect(near(edge.geometric.rotation.radians, .pi / 6))
        let half = ScrollTransitionEffect.interpolated(
            from: ScrollTransitionEffect(), to: edge, progress: 0.5
        )
        #expect(near(half.visual.opacity, 0.625))
        #expect(near(half.geometric.scale.y, 0.9))
        #expect(half.geometric.translation == SIMD2(5, 2))
        #expect(near(half.visual.blurRadius, 1))
    }

    final class Seen {
        var changes: [String] = []
        var positions: [Double] = []
    }

    @Test("The hub calls onScrollGeometryChange only on change, and moves trackers")
    func hub() {
        let hub = ScrollGeometryHub()
        let seen = Seen()
        let observer = ScrollGeometryObserver { geometry, previous in
            let value = geometry.contentOffset.y >= 100
            if let old = previous as? Bool, old != value {
                seen.changes.append("\(old) -> \(value)")
            }
            return value
        }
        hub.setObservers([observer])
        hub.update(
            contentOffset: SIMD2(0, 0),
            contentSize: ViewSize(300, 1000),
            containerSize: ViewSize(300, 400)
        )
        hub.update(contentOffset: SIMD2(0, 50))
        hub.update(contentOffset: SIMD2(0, 150))
        hub.update(contentOffset: SIMD2(0, 150))
        hub.update(contentOffset: SIMD2(0, 20))
        #expect(seen.changes == ["false -> true", "true -> false"])
        #expect(hub.geometry.visibleRect.size == SIMD2(300, 400))

        let node = ScrollTrackingNode()
        node.frameInContent = Path.Rect(origin: SIMD2(0, 500), size: SIMD2(300, 100))
        node.onScroll = { start, _, _ in seen.positions.append(start) }
        hub.register(node)
        hub.update(contentOffset: SIMD2(0, 200))
        node.axis = .horizontal
        hub.update(contentOffset: SIMD2(30, 200))
        #expect(seen.positions == [300, -30])
    }
}
