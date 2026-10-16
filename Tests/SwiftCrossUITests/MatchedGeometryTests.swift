import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// GSAP's Flip under SwiftUI's name: the arithmetic of `matchedGeometryEffect`,
/// the layout transaction that carries `withAnimation` to the update, and the
/// flip nodes themselves, with a registry of their own and no backend -- the
/// driver has no clock here, so a started flip lands on its end at once and the
/// draws it made are what the tests read.
///
/// GSAP 的 Flip,以 SwiftUI 的名稱:`matchedGeometryEffect` 的算術、把 `withAnimation` 帶到更新的版面
/// transaction,以及 flip 節點本身——使用自己的 registry、不需要 backend。這裡的 driver 沒有時鐘，所以
/// 啟動的 flip 會立刻落在終點，測試讀的是它途中做過的繪製。
@MainActor
@Suite("Matched geometry (Flip)")
struct MatchedGeometryTests {
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path.Rect {
        Path.Rect(origin: SIMD2(x, y), size: SIMD2(w, h))
    }

    func apply(_ t: AffineTransform, _ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(
            t.linearTransform.x * p.x + t.linearTransform.y * p.y + t.translation.x,
            t.linearTransform.z * p.x + t.linearTransform.w * p.y + t.translation.y
        )
    }

    func close(_ a: Path.Rect, _ b: Path.Rect) -> Bool {
        abs(a.origin.x - b.origin.x) < 1e-9 && abs(a.origin.y - b.origin.y) < 1e-9
            && abs(a.size.x - b.size.x) < 1e-9 && abs(a.size.y - b.size.y) < 1e-9
    }

    @Test("A frame mapped onto a target is drawn over the target, for any anchor")
    func mappingInverts() {
        let frame = rect(100, 40, 80, 20)
        let target = rect(10, 200, 40, 60)
        for anchor in [UnitPoint.center, .topLeading, .bottomTrailing, UnitPoint(x: 0.2, y: 0.9)] {
            let components = FlipComponents.mapping(
                frame, onto: target, properties: .frame, anchor: anchor
            )
            #expect(close(components.visualFrame(of: frame, anchor: anchor), target))
            // And the effect a backend receives agrees: the corners land on the target's.
            // backend 收到的效果也一致：四個角落在目標的角上。
            let transform = components.effect(anchor: anchor).resolved(in: frame.size)
            let topLeft = apply(transform, SIMD2(0, 0))
            let bottomRight = apply(transform, frame.size)
            #expect(abs(frame.origin.x + topLeft.x - target.origin.x) < 1e-9)
            #expect(abs(frame.origin.y + topLeft.y - target.origin.y) < 1e-9)
            #expect(abs(frame.origin.x + bottomRight.x - (target.origin.x + target.size.x)) < 1e-9)
            #expect(abs(frame.origin.y + bottomRight.y - (target.origin.y + target.size.y)) < 1e-9)
        }
    }

    @Test("Position alone moves the anchor point there and keeps the size")
    func positionOnly() {
        let frame = rect(0, 0, 100, 50)
        let target = rect(200, 100, 20, 10)
        let components = FlipComponents.mapping(
            frame, onto: target, properties: .position, anchor: .center
        )
        #expect(components.scale == SIMD2(1, 1))
        let drawn = components.visualFrame(of: frame, anchor: .center)
        #expect(close(drawn, rect(160, 80, 100, 50)))
        // Size alone scales about the anchor and leaves it where it was.
        // 只有尺寸時繞錨點縮放，錨點留在原處。
        let sized = FlipComponents.mapping(frame, onto: target, properties: .size, anchor: .center)
        #expect(sized.translation == SIMD2(0, 0))
        #expect(close(sized.visualFrame(of: frame, anchor: .center), rect(40, 20, 20, 10)))
    }

    @Test("Halfway through, the drawn frame is halfway between")
    func interpolation() {
        let frame = rect(0, 0, 40, 40)
        let start = FlipComponents.mapping(
            frame, onto: rect(100, 0, 80, 40), properties: .frame, anchor: .topLeading
        )
        let half = start.interpolated(to: .identity, progress: 0.5)
        #expect(close(half.visualFrame(of: frame, anchor: .topLeading), rect(50, 0, 60, 40)))
        #expect(start.interpolated(to: .identity, progress: 1) == .identity)
    }

    @Test("A layout transaction is seen within its window and not after")
    func transactionWindow() {
        var state = LayoutTransactionState()
        #expect(state.current(now: 0) == nil)
        _ = state.arm(.linear(duration: 1), group: nil, now: 10)
        #expect(state.current(now: 10.1)?.animation == .linear(duration: 1))
        #expect(state.current(now: 10 + LayoutTransactionState.window + 0.01) == nil)
        let token = state.armed!.token
        // The hold is released once, whoever asks first.
        // hold 只釋放一次，不論誰先要求。
        let firstRelease = state.releaseHold(token: token)
        let secondRelease = state.releaseHold(token: token)
        let expiredAfterRelease = state.expire(token: token)
        #expect(firstRelease)
        #expect(!secondRelease)
        #expect(expiredAfterRelease == nil)
        #expect(state.armed == nil)
        // A second arm replaces the first and hands it back for its hold.
        // 第二次上膛取代第一次，並把它交回以釋放 hold。
        _ = state.arm(.linear(duration: 1), group: nil, now: 20)
        let replaced = state.arm(.easeIn(duration: 1), group: nil, now: 20.1)
        #expect(replaced?.animation == .linear(duration: 1))
        let expiredReplaced = state.expire(token: replaced!.token)
        let expiredCurrent = state.expire(token: state.armed!.token)
        #expect(expiredReplaced == nil)
        #expect(expiredCurrent != nil)
    }

    final class Draws {
        var all: [FlipComponents] = []
    }

    func node(
        _ id: Int,
        _ registry: MatchedGeometryRegistry,
        _ namespace: Namespace.ID,
        isSource: Bool = true,
        properties: MatchedGeometryProperties = .frame
    ) -> (FlipNode, Draws) {
        let node = FlipNode(registry: registry)
        let draws = Draws()
        node.key = MatchedGeometryKey(namespace: namespace, id: AnyHashable(id))
        node.isSource = isSource
        node.properties = properties
        node.anchor = .topLeading
        node.draw = { components, _ in draws.all.append(components) }
        return (node, draws)
    }

    var transaction: LayoutTransactionState.Pending {
        LayoutTransactionState.Pending(
            animation: .linear(duration: 1), group: nil, armedAt: 0, token: 1
        )
    }

    @Test("A moved view starts where it was and ends where it is")
    func moveFlips() {
        let registry = MatchedGeometryRegistry()
        let namespace = Namespace().wrappedValue
        let (block, draws) = node(1, registry, namespace)
        block.settle(frame: rect(0, 0, 50, 50), transaction: nil)
        #expect(draws.all == [.identity])

        block.settle(frame: rect(200, 0, 50, 50), transaction: transaction)
        // First draw: back at x 0. Last: at rest at x 200.
        // 第一次繪製：回到 x 0。最後：停在 x 200。
        #expect(draws.all.count >= 3)
        #expect(close(draws.all[1].visualFrame(of: rect(200, 0, 50, 50), anchor: .topLeading),
            rect(0, 0, 50, 50)))
        #expect(draws.all.last == .identity)
        #expect(!block.isAnimating)

        // Without an animation it jumps.
        // 沒有動畫就直接跳過去。
        draws.all = []
        block.settle(frame: rect(0, 100, 50, 50), transaction: nil)
        #expect(draws.all == [.identity])
    }

    @Test("A view that takes over an id flies from the old holder's frame")
    func handOff() {
        let registry = MatchedGeometryRegistry()
        let namespace = Namespace().wrappedValue
        let (thumbnail, _) = node(7, registry, namespace)
        thumbnail.settle(frame: rect(10, 10, 40, 40), transaction: nil)

        let (detail, draws) = node(7, registry, namespace)
        detail.settle(frame: rect(0, 100, 200, 200), transaction: transaction)
        #expect(close(draws.all[0].visualFrame(of: rect(0, 100, 200, 200), anchor: .topLeading),
            rect(10, 10, 40, 40)))
        #expect(draws.all.last == .identity)
    }

    @Test("Two nodes swapping ids each fly from the other's old place")
    func swap() {
        let registry = MatchedGeometryRegistry()
        let namespace = Namespace().wrappedValue
        let (first, firstDraws) = node(1, registry, namespace)
        let (second, secondDraws) = node(2, registry, namespace)
        first.settle(frame: rect(0, 0, 50, 50), transaction: nil)
        second.settle(frame: rect(100, 0, 50, 50), transaction: nil)

        // A ForEach that reuses nodes by position: node one now shows id 2.
        // 依位置重用節點的 ForEach:第一個節點現在顯示 id 2。
        let one = MatchedGeometryKey(namespace: namespace, id: AnyHashable(1))
        let two = MatchedGeometryKey(namespace: namespace, id: AnyHashable(2))
        first.release(one)
        first.key = two
        second.release(two)
        second.key = one
        first.settle(frame: rect(0, 0, 50, 50), transaction: transaction)
        second.settle(frame: rect(100, 0, 50, 50), transaction: transaction)
        #expect(close(firstDraws.all[1].visualFrame(of: rect(0, 0, 50, 50), anchor: .topLeading),
            rect(100, 0, 50, 50)))
        #expect(close(secondDraws.all[1].visualFrame(of: rect(100, 0, 50, 50), anchor: .topLeading),
            rect(0, 0, 50, 50)))
    }

    @Test("A follower is drawn over its source and follows it")
    func follower() {
        let registry = MatchedGeometryRegistry()
        let namespace = Namespace().wrappedValue
        let (source, _) = node(3, registry, namespace)
        source.settle(frame: rect(100, 0, 60, 30), transaction: nil)
        let (underline, draws) = node(3, registry, namespace, isSource: false, properties: .position)
        underline.settle(frame: rect(0, 40, 60, 2), transaction: nil)
        #expect(close(underline.visualFrame!, rect(100, 0, 60, 2)))

        source.settle(frame: rect(200, 0, 60, 30), transaction: nil)
        #expect(close(underline.visualFrame!, rect(200, 0, 60, 2)))
        #expect(draws.all.count == 2)
    }

    @Test("A namespace keeps its first id across updates")
    func namespaceKeepsID() {
        let first = Namespace()
        let rebuilt = Namespace()
        #expect(first.wrappedValue != rebuilt.wrappedValue)
        rebuilt.update(with: EnvironmentValues(backend: DummyBackend()), previousValue: first)
        #expect(first.wrappedValue == rebuilt.wrappedValue)
    }
}
