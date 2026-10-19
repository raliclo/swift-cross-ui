import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Insert and remove transitions: what each transition draws at each point of
/// its two phases, the controller that drives a view's transition, and how a
/// container keeps departing views after its live children. The driver has no
/// clock here, so a started transition lands on its end at once.
///
/// 插入與移除轉場：每個轉場在兩個階段的每一點畫什麼、驅動 view 轉場的 controller,以及容器如何把離場中的 view
/// 留在存活子元件之後。這裡的 driver 沒有時鐘，所以啟動的轉場會立刻落在終點。
@MainActor
@Suite("Transitions (insert and remove)")
struct TransitionTests {
    let size = SIMD2<Double>(80, 40)

    func transaction(_ token: Int, _ animation: Animation? = .linear(duration: 1)) -> EffectTransaction {
        EffectTransaction(animation: animation, group: nil, token: .layout(token))
    }

    @Test("Each transition's state at the away end, per phase")
    func awayStates() {
        let opacity = AnyTransition.opacity.effects(for: .insertion, size: size)
        #expect(opacity.visual.opacity == 0)
        #expect(opacity.geometric == .identity)

        let scale = AnyTransition.scale.effects(for: .removal, size: size)
        #expect(scale.geometric.scale == SIMD2(0, 0))
        #expect(scale.geometric.anchor == .center)
        let scaleTop = AnyTransition.scale(scale: 0.5, anchor: .top).effects(for: .insertion, size: size)
        #expect(scaleTop.geometric.scale == SIMD2(0.5, 0.5))
        #expect(scaleTop.geometric.anchor == .top)

        // Slide: in from the leading edge, out towards the trailing edge.
        // slide:從前緣進來，往後緣出去。
        #expect(AnyTransition.slide.effects(for: .insertion, size: size).geometric.translation == SIMD2(-80, 0))
        #expect(AnyTransition.slide.effects(for: .removal, size: size).geometric.translation == SIMD2(80, 0))

        // Move: the same edge both ways, by the view's own size.
        // move:兩個方向都是同一個邊，距離為 view 自己的尺寸。
        let edges: [(Edge, SIMD2<Double>)] = [
            (.leading, SIMD2(-80, 0)), (.trailing, SIMD2(80, 0)),
            (.top, SIMD2(0, -40)), (.bottom, SIMD2(0, 40)),
        ]
        for (edge, expected) in edges {
            for phase in [AnyTransition.Phase.insertion, .removal] {
                #expect(AnyTransition.move(edge: edge).effects(for: phase, size: size).geometric.translation == expected)
            }
        }

        #expect(AnyTransition.offset(x: 10, y: -5).effects(for: .removal, size: size).geometric.translation == SIMD2(10, -5))
        #expect(AnyTransition.offset(SIMD2(3, 4)).effects(for: .insertion, size: size).geometric.translation == SIMD2(3, 4))
        #expect(AnyTransition.identity.effects(for: .insertion, size: size) == .identity)
    }

    @Test("Push comes in from its edge and leaves by the opposite one, fading")
    func push() {
        let push = AnyTransition.push(from: .bottom)
        let inserting = push.effects(for: .insertion, size: size)
        #expect(inserting.geometric.translation == SIMD2(0, 40))
        #expect(inserting.visual.opacity == 0)
        let removing = push.effects(for: .removal, size: size)
        #expect(removing.geometric.translation == SIMD2(0, -40))
        #expect(removing.visual.opacity == 0)
    }

    @Test("Asymmetric uses one transition per phase; combined applies both")
    func asymmetricAndCombined() {
        let asymmetric = AnyTransition.asymmetric(insertion: .move(edge: .top), removal: .opacity)
        #expect(asymmetric.effects(for: .insertion, size: size).geometric.translation == SIMD2(0, -40))
        #expect(asymmetric.effects(for: .insertion, size: size).visual.opacity == 1)
        #expect(asymmetric.effects(for: .removal, size: size).geometric.translation == .zero)
        #expect(asymmetric.effects(for: .removal, size: size).visual.opacity == 0)

        let combined = AnyTransition.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity)
            .combined(with: .offset(x: 4))
        let away = combined.effects(for: .insertion, size: size)
        #expect(away.geometric.scale == SIMD2(0.5, 0.5))
        #expect(away.geometric.anchor == .bottom)
        #expect(away.geometric.translation == SIMD2(4, 0))
        #expect(away.visual.opacity == 0)
    }

    @Test("Progress runs from the away state to identity on insertion and back on removal")
    func progress() {
        let half = AnyTransition.slide.effects(for: .insertion, size: size, progress: 0.5)
        #expect(half.geometric.translation == SIMD2(-40, 0))
        let quarter = AnyTransition.opacity.effects(for: .removal, size: size, progress: 0.25)
        #expect(abs(quarter.visual.opacity - 0.75) < 1e-12)
        // The anchor stays put while a scale runs. / 縮放進行時錨點不動。
        let scaling = AnyTransition.scale(scale: 0, anchor: .topLeading)
            .effects(for: .insertion, size: size, progress: 0.3)
        #expect(scaling.geometric.anchor == .topLeading)
        #expect(abs(scaling.geometric.scale.x - 0.3) < 1e-12)
        #expect(AnyTransition.opacity.effects(for: .insertion, size: size, progress: 1) == .identity)
    }

    @Test("A transition's own animation wins over the change's, per phase for asymmetric")
    func animations() {
        let fallback = Animation.linear(duration: 1)
        #expect(AnyTransition.opacity.animation(for: .insertion, fallback: fallback) == fallback)
        let own = Animation.easeIn(duration: 0.2)
        #expect(AnyTransition.opacity.animation(own).animation(for: .removal, fallback: fallback) == own)
        let asymmetric = AnyTransition.asymmetric(
            insertion: .opacity.animation(own),
            removal: .slide
        )
        #expect(asymmetric.animation(for: .insertion, fallback: fallback) == own)
        #expect(asymmetric.animation(for: .removal, fallback: fallback) == fallback)
        #expect(AnyTransition.opacity.animation(for: .insertion, fallback: nil) == nil)
    }

    @MainActor
    final class Draws {
        var opacities: [Double] = []
        var transforms: [AffineTransform] = []
    }

    func controller(_ transition: AnyTransition, _ draws: Draws) -> TransitionController {
        let controller = TransitionController()
        controller.transition = transition
        controller.drawVisual = { draws.opacities.append($0.opacity) }
        controller.drawGeometric = { draws.transforms.append($0) }
        return controller
    }

    @Test("An inserted view is drawn in the away state first, then ends as itself")
    func insertion() {
        let draws = Draws()
        let controller = controller(.opacity, draws)
        controller.pendingInsertion = transaction(1)
        controller.commit(size: size)
        #expect(draws.opacities.first == 0)
        #expect(draws.opacities.last == 1)
        #expect(controller.state == .shown)
        #expect(controller.pendingInsertion == nil)
    }

    @Test("A view that appears without an insertion is drawn as itself at once")
    func appearance() {
        let draws = Draws()
        let controller = controller(.opacity, draws)
        controller.commit(size: size)
        #expect(draws.opacities == [1])
    }

    @Test("Removal needs a committed view and an animation; it ends in the away state")
    func removal() {
        let draws = Draws()
        let controller = controller(.slide, draws)
        var finished = 0
        #expect(!controller.remove(transaction: transaction(1)) { finished += 1 })
        controller.commit(size: size)
        #expect(!controller.remove(transaction: transaction(2, nil)) { finished += 1 })
        #expect(controller.remove(transaction: transaction(3)) { finished += 1 })
        #expect(finished == 1)
        #expect(controller.state == .removed)
        #expect(draws.transforms.last?.translation == SIMD2(80, 0))
    }

    @Test("A zero scale is drawn as a ten-thousandth, which a backend can invert")
    func zeroScale() {
        let draws = Draws()
        let controller = controller(.scale, draws)
        controller.pendingInsertion = transaction(1)
        controller.commit(size: size)
        let first = draws.transforms.first
        #expect(first.map { abs($0.linearTransform.x - 0.0001) < 1e-12 } == true)
        #expect(draws.transforms.last == .identity)
    }

    func departure(_ widget: DummyBackend.Widget, size: SIMD2<Int> = SIMD2(10, 10)) -> DepartingViews.Departure {
        DepartingViews.Departure(widget: AnyWidget(widget), node: widget, size: size)
    }

    func children(_ container: DummyBackend.Widget) -> [ObjectIdentifier] {
        (container as! DummyBackend.Container).children.map { ObjectIdentifier($0.widget) }
    }

    @Test("A departing child stays behind the new one until its transition ends")
    func switchKeepsDeparture() {
        let backend = DummyBackend()
        let container = backend.createContainer()
        let a = backend.createContainer()
        let b = backend.createContainer()
        let c = backend.createContainer()
        let departing = DepartingViews()
        departing.commitSwitch(container: container, backend: backend, hadChild: false, departure: nil, newChild: a)
        #expect(children(container) == [ObjectIdentifier(a)])

        let leavingA = departure(a, size: SIMD2(30, 5))
        departing.commitSwitch(container: container, backend: backend, hadChild: true, departure: leavingA, newChild: b)
        #expect(children(container) == [ObjectIdentifier(b), ObjectIdentifier(a)])
        #expect(departing.containerSize(SIMD2(10, 20)) == SIMD2(30, 20))

        let leavingB = departure(b)
        departing.commitSwitch(container: container, backend: backend, hadChild: true, departure: leavingB, newChild: c)
        #expect(children(container) == [ObjectIdentifier(c), ObjectIdentifier(b), ObjectIdentifier(a)])

        // The older departure ends first, then the newer one.
        // 較早的離場先結束，然後是較新的。
        departing.finished(leavingA)
        #expect(children(container) == [ObjectIdentifier(c), ObjectIdentifier(b)])
        departing.finished(leavingB)
        #expect(children(container) == [ObjectIdentifier(c)])
        #expect(departing.isEmpty)
    }

    @Test("A departure that ended before the commit is removed at it; nil child leaves the slot empty")
    func switchDropsFinished() {
        let backend = DummyBackend()
        let container = backend.createContainer()
        let a = backend.createContainer()
        let departing = DepartingViews()
        departing.commitSwitch(container: container, backend: backend, hadChild: false, departure: nil, newChild: a)
        let leaving = departure(a)
        leaving.isFinished = true
        departing.commitSwitch(container: container, backend: backend, hadChild: true, departure: leaving, newChild: nil)
        #expect(children(container).isEmpty)
        #expect(departing.isEmpty)

        // An `if` going to nil while its child departs: the child alone, at index 0.
        // `if` 變成 nil 而子元件正在離場：只剩那個子元件，在索引 0。
        departing.commitSwitch(container: container, backend: backend, hadChild: false, departure: nil, newChild: a)
        let departingA = departure(a)
        departing.commitSwitch(container: container, backend: backend, hadChild: true, departure: departingA, newChild: nil)
        #expect(children(container) == [ObjectIdentifier(a)])
        #expect(departing.liveCount == 0)
        departing.finished(departingA)
        #expect(children(container).isEmpty)
    }

    @Test("Later departures go in front of earlier ones, as a ForEach leaves them")
    func commitOrder() {
        let backend = DummyBackend()
        let departing = DepartingViews()
        let first = departure(backend.createContainer())
        let second = departure(backend.createContainer())
        let third = departure(backend.createContainer())
        departing.commit([first])
        departing.commit([second, third])
        #expect(departing.committed.map(ObjectIdentifier.init) == [second, third, first].map(ObjectIdentifier.init))
        var removed: [Int] = []
        departing.liveCount = 4
        departing.removeChild = { removed.append($0) }
        departing.finished(third)
        departing.finished(first)
        #expect(removed == [5, 5])
    }

    struct Toggled: View {
        var show: Bool
        var body: some View {
            if show {
                Text("a").transition(.opacity)
            }
        }
    }

    @Test("Without a frame clock an animated removal takes the child out in the same commit")
    func noClockRemoval() {
        let node = ViewGraphHelpers.committedNode(for: Toggled(show: true))
        #expect(leaves(node.widget) == 1)
        var animated = ViewGraphHelpers.environment
        animated.effectAnimationOverride = transaction(1)
        _ = node.computeLayout(with: Toggled(show: false), proposedSize: .unspecified, environment: animated)
        _ = node.commit()
        #expect(leaves(node.widget) == 0)
        // And it comes back, through its insertion. / 而且會經由插入轉場回來。
        animated.effectAnimationOverride = transaction(2)
        _ = node.computeLayout(with: Toggled(show: true), proposedSize: .unspecified, environment: animated)
        _ = node.commit()
        #expect(leaves(node.widget) == 1)
    }

    /// Widgets under `widget` that are not containers. / `widget` 之下不是容器的 widget。
    func leaves(_ widget: DummyBackend.Widget) -> Int {
        guard let container = widget as? DummyBackend.Container else { return 1 }
        return container.children.map { leaves($0.widget) }.reduce(0, +)
    }

    @Test("Without a .transition a view fades, SwiftUI's default: from 0 on insertion, to 0 on removal")
    func defaultFade() {
        let draws = Draws()
        let slot = DefaultTransitionSlot()
        #expect(
            slot.controller.transition.effects(for: .insertion, size: size)
                == AnyTransition.opacity.effects(for: .insertion, size: size)
        )
        slot.controller.drawVisual = { draws.opacities.append($0.opacity) }
        slot.controller.pendingInsertion = transaction(1)
        slot.controller.commit(size: size)
        #expect(draws.opacities.first == 0)
        #expect(draws.opacities.last == 1)
        #expect(slot.controller.remove(transaction: transaction(2)) {})
        #expect(draws.opacities.last == 0)
    }

    @Test("A default fade started before its container arrives draws the current frame once it does")
    func defaultFadeLateContainer() {
        let draws = Draws()
        let controller = TransitionController()
        controller.transition = .opacity
        controller.adopt(size: size)
        #expect(controller.remove(transaction: transaction(1)) {})
        #expect(draws.opacities.isEmpty)
        controller.drawVisual = { draws.opacities.append($0.opacity) }
        controller.draw()
        #expect(draws.opacities == [0])
    }

    struct Plain: View {
        var body: some View { Text("a").padding() }
    }

    struct Matched: View {
        var namespace: Namespace.ID
        var body: some View { Text("a").matchedGeometryEffect(id: 1, in: namespace) }
    }

    @Test("A plain view takes the default fade; a matched view flies instead when it replaces another")
    func defaultFadeHost() {
        let plain = ErasedViewGraphNode(wrapping: ViewGraphHelpers.committedNode(for: Plain()))
        #expect(TransitionLookup.defaultTransitionHost(for: plain, inserting: true) != nil)
        #expect(TransitionLookup.defaultTransitionHost(for: plain, inserting: false) != nil)
        #expect(TransitionLookup.matchedKey(in: plain) == nil)

        let namespace = Namespace().wrappedValue
        let matched = ErasedViewGraphNode(wrapping: ViewGraphHelpers.committedNode(for: Matched(namespace: namespace)))
        let key = MatchedGeometryKey(namespace: namespace, id: AnyHashable(1))
        #expect(TransitionLookup.matchedKey(in: matched) == key)
        // Removed: no fade. Inserted with an id nobody has held: it fades.
        // 被移除：不淡出。以沒有人持有過的 id 插入：淡入。
        #expect(TransitionLookup.defaultTransitionHost(for: matched, inserting: false) == nil)
        #expect(TransitionLookup.defaultTransitionHost(for: matched, inserting: true) != nil)
        // Once another view has held the id, it flies from there instead.
        // 一旦另一個 view 持有過這個 id,它改為從那裡飛過來。
        _ = MatchedGeometryRegistry.shared.entry(key)
        #expect(TransitionLookup.defaultTransitionHost(for: matched, inserting: true) == nil)
    }

    @Test("A container's child is its default fade's wrapper once it has one")
    func outerWidget() {
        let node = ViewGraphHelpers.committedNode(for: Plain())
        let erased = ErasedViewGraphNode(wrapping: node)
        #expect(TransitionLookup.outerWidget(of: erased).widget as AnyObject === node.widget)
        // DummyBackend has no visual-effect container, so nothing wraps it.
        // DummyBackend 沒有視覺效果容器，所以不會被包起來。
        #expect(node.installDefaultTransitionWrapper() == nil)
        #expect(TransitionLookup.outerWidget(of: erased).widget as AnyObject === node.widget)
    }
}
