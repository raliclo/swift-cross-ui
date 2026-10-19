import Foundation

// Insert and remove transitions: `.transition(.opacity)`, `.scale`, `.slide`,
// `.move(edge:)`, `.offset`, `.push(from:)`, `.asymmetric`, `.combined(with:)` and
// `.identity`, SwiftUI's names and semantics. A view that an `if`, an `if`/`else`
// or a `ForEach` inserts or removes in an update running under an animation (a
// `withAnimation` assignment that cannot tween, or an `.animation(_:value:)` above
// the container that saw its value change) goes through its transition: an
// inserted view starts drawn in the transition's state and moves to its own, a
// removed view stays drawn where it was, moving to the transition's state, and is
// taken out of its container when that ends.
//
// **How a frame is drawn.** The transition modifier wraps its content in a
// geometric-effect container and a visual-effect container (the same backend
// containers `.offset` and `.opacity` use) and sets both on every frame of the
// tween from the frame clock, with no body evaluation and no re-layout -- the
// direct path of EffectAnimation.swift. A removed view is no longer laid out: its
// neighbours take their new places at once (or fly there under
// `matchedGeometryEffect`) while it is drawn at its last frame on top.
//
// **Which transition applies.** The container looks for a `.transition` from the
// root of the inserted or removed view down through views with a single child,
// so `Text("a").transition(.slide).padding()` uses `.slide`. Without one the view
// fades (`.opacity`, SwiftUI's default) under the same conditions; without an
// animation it is inserted and removed at once, and `.transition(.identity)` opts
// out. A view with a `matchedGeometryEffect` does not fade when it is removed, or
// when it is inserted with an id another view has held: it flies instead.
//
// **The default fade.** The view has no transition containers of its own, so the
// container wraps its widget in a visual-effect container (``DefaultTransitionSlot``):
// an inserted view before its widget enters the container, a removed one at the
// container's commit, which takes the widget out and puts the wrapper in its place,
// at the position the layout last gave it. The wrapper stays for the view's life
// and takes its size at each commit of the view.
//
// 插入與移除的轉場:`.transition(.opacity)`、`.scale`、`.slide`、`.move(edge:)`、`.offset`、
// `.push(from:)`、`.asymmetric`、`.combined(with:)` 與 `.identity`,SwiftUI 的名稱與語意。`if`、`if`/`else`
// 或 `ForEach` 在一次帶動畫的更新中(無法補間的 `withAnimation` 賦值，或容器上方看到值改變的
// `.animation(_:value:)`)插入或移除的 view 會走它的轉場：插入的 view 從轉場的狀態開始畫，移向自己的狀態;
// 移除的 view 留在原處繼續畫，移向轉場的狀態，結束時才從容器中拿掉。
//
// **每一幀怎麼畫。** 轉場 modifier 把內容包在一個幾何效果容器與一個視覺效果容器裡(與 `.offset`、`.opacity`
// 用的是同一種 backend 容器),在 frame clock 上補間的每一幀設定兩者，不求值 body、不重排版面——即
// EffectAnimation.swift 的直接路徑。被移除的 view 不再參與排版：鄰居立刻就位(在 `matchedGeometryEffect` 下則
// 飛過去),它則以最後的 frame 畫在上面。
//
// **套用哪一個轉場。** 容器從被插入或移除的 view 的根往下，沿著只有一個子節點的 view 尋找 `.transition`,所以
// `Text("a").transition(.slide).padding()` 用的是 `.slide`。沒有的話，view 在同樣的條件下淡入淡出(`.opacity`,
// SwiftUI 的預設);沒有動畫時立刻插入與移除,`.transition(.identity)` 則可退出。帶 `matchedGeometryEffect` 的 view
// 被移除時、或以另一個 view 持有過的 id 插入時不淡入淡出，而是飛過去。
//
// **預設的淡入淡出。** view 自己沒有轉場容器，所以由容器把它的 widget 包進一個視覺效果容器
// (``DefaultTransitionSlot``):插入的 view 在其 widget 進入容器之前;移除的 view 在容器 commit 時——把 widget 取出、
// 在原處(排版上次給它的位置)放上包裝容器。包裝容器在 view 的一生中都留著，並在 view 每次 commit 時取得它的尺寸。

/// How a view is drawn as it is inserted or removed -- SwiftUI's `AnyTransition`.
///
/// A transition gives the view's look at the "away" end of each phase; the view
/// moves between that and its own look (identity) on the animation's curve.
///
/// 插入或移除 view 時它怎麼畫——SwiftUI 的 `AnyTransition`。轉場給出每個階段「離開」那一端 view 的樣子;
/// view 沿著動畫的曲線在那個樣子與它自己的樣子(identity)之間移動。
public struct AnyTransition: Sendable {
    /// Inserting (from the transition's state to identity) or removing (from
    /// identity to the transition's state).
    /// 插入(從轉場狀態到 identity)或移除(從 identity 到轉場狀態)。
    public enum Phase: Sendable, Equatable {
        case insertion
        case removal
    }

    /// What the transition draws at its "away" end: a geometric effect and a
    /// visual effect, combined the way nested modifiers would combine them.
    /// 轉場在「離開」那一端畫的東西：一個幾何效果與一個視覺效果，以巢狀 modifier 的方式組合。
    public struct Effects: Equatable, Sendable {
        public var geometric: GeometricEffect
        public var visual: VisualEffect

        public init(geometric: GeometricEffect = .identity, visual: VisualEffect = .identity) {
            self.geometric = geometric
            self.visual = visual
        }

        public static let identity = Effects()

        /// The identity with this effect's anchor, so a tween between the two
        /// does not move the anchor.
        /// 帶著此效果錨點的 identity,讓兩者之間的補間不會移動錨點。
        var identityWithSameAnchor: Effects {
            Effects(geometric: GeometricEffect(anchor: geometric.anchor), visual: .identity)
        }

        /// Both applied, as `.offset(...).scaleEffect(...)` would draw them:
        /// translations add, scales and opacities multiply, rotations add, and
        /// the anchor is the one of whichever effect scales or rotates.
        /// 兩者都套用，與 `.offset(...).scaleEffect(...)` 畫出的相同：平移相加、縮放與不透明度相乘、旋轉相加，錨點
        /// 取有縮放或旋轉的那一個。
        public func combined(with other: Effects) -> Effects {
            func transforms(_ effect: GeometricEffect) -> Bool {
                effect.scale != SIMD2(1, 1) || effect.rotation != .zero
            }
            let geometric = GeometricEffect(
                translation: self.geometric.translation + other.geometric.translation,
                scale: self.geometric.scale * other.geometric.scale,
                rotation: Angle(radians: self.geometric.rotation.radians + other.geometric.rotation.radians),
                anchor: transforms(self.geometric) || !transforms(other.geometric)
                    ? self.geometric.anchor : other.geometric.anchor,
                matrix: self.geometric.matrix.followedBy(other.geometric.matrix)
            )
            var visual = self.visual
            visual.opacity *= other.visual.opacity
            visual.blurRadius += other.visual.blurRadius
            visual.saturation *= other.visual.saturation
            visual.brightness += other.visual.brightness
            visual.contrast *= other.visual.contrast
            visual.grayscale = max(visual.grayscale, other.visual.grayscale)
            visual.hueRotation = Angle(
                radians: visual.hueRotation.radians + other.visual.hueRotation.radians
            )
            return Effects(geometric: geometric, visual: visual)
        }

        static func interpolated(from start: Effects, to end: Effects, progress: Double) -> Effects {
            Effects(
                geometric: GeometricEffect.interpolated(
                    from: start.geometric, to: end.geometric, progress: progress
                ),
                visual: VisualEffect.interpolated(from: start.visual, to: end.visual, progress: progress)
            )
        }
    }

    let effectsAway: @Sendable (Phase, SIMD2<Double>) -> Effects
    /// The transition's own animation (``animation(_:)``), used instead of the
    /// one the change runs under.
    /// 轉場自己的動畫(``animation(_:)``),取代這次改變所用的動畫。
    public private(set) var animation: Animation?

    /// A transition from a function of the phase and the view's size to the
    /// effects at the "away" end.
    /// 由「階段與 view 尺寸」到「離開那一端的效果」的函數所構成的轉場。
    public init(_ effects: @escaping @Sendable (Phase, SIMD2<Double>) -> Effects) {
        self.effectsAway = effects
    }

    /// The effects at the "away" end of `phase` for a view of `size`.
    /// 尺寸為 `size` 的 view 在 `phase` 的「離開」那一端的效果。
    public func effects(for phase: Phase, size: SIMD2<Double>) -> Effects {
        effectsAway(phase, size)
    }

    /// The effects at `progress` through `phase`: `0` is the start of the
    /// phase and `1` its end, so an insertion goes from the transition's state
    /// to identity and a removal from identity to the transition's state.
    /// `phase` 進行到 `progress` 時的效果:`0` 是階段的開始、`1` 是結束，所以插入從轉場狀態走到 identity,
    /// 移除從 identity 走到轉場狀態。
    public func effects(for phase: Phase, size: SIMD2<Double>, progress: Double) -> Effects {
        let away = effects(for: phase, size: size)
        let identity = away.identityWithSameAnchor
        switch phase {
            case .insertion:
                return Effects.interpolated(from: away, to: identity, progress: progress)
            case .removal:
                return Effects.interpolated(from: identity, to: away, progress: progress)
        }
    }

    /// No change: the view appears and goes at once.
    /// 不改變:view 立刻出現與消失。
    public static let identity = AnyTransition { _, _ in .identity }

    /// Fades the view in and out.
    /// 讓 view 淡入淡出。
    public static let opacity = AnyTransition { _, _ in
        Effects(visual: VisualEffect(opacity: 0))
    }

    /// Scales the view from nothing on insertion and to nothing on removal,
    /// about its centre.
    /// 以中心為錨點，插入時從無放大、移除時縮小到無。
    public static var scale: AnyTransition { scale(scale: 0) }

    /// Scales the view from `scale` on insertion and to `scale` on removal,
    /// about `anchor`.
    /// 以 `anchor` 為錨點，插入時從 `scale` 開始、移除時縮放到 `scale`。
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition { _, _ in
            Effects(geometric: GeometricEffect(scale: SIMD2(scale, scale), anchor: anchor))
        }
    }

    /// Moves the view in from its leading edge and out towards its trailing
    /// edge, by its own width.
    /// 以自身的寬度，從前緣移入、往後緣移出。
    public static let slide = AnyTransition { phase, size in
        Effects(
            geometric: GeometricEffect(
                translation: SIMD2(phase == .insertion ? -size.x : size.x, 0)
            )
        )
    }

    /// Moves the view in from `edge` and out towards `edge`, by its own size.
    /// 以自身的尺寸，從 `edge` 移入、往 `edge` 移出。
    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition { _, size in
            Effects(geometric: GeometricEffect(translation: translation(towards: edge, size: size)))
        }
    }

    /// Offsets the view by a fixed distance at the "away" end of both phases.
    /// 在兩個階段的「離開」那一端，讓 view 位移固定的距離。
    public static func offset(x: Double = 0, y: Double = 0) -> AnyTransition {
        AnyTransition { _, _ in
            Effects(geometric: GeometricEffect(translation: SIMD2(x, y)))
        }
    }

    /// Offsets the view by `offset` (width, height) at the "away" end of both
    /// phases. / 在兩個階段的「離開」那一端，讓 view 位移 `offset`(寬、高)。
    public static func offset(_ offset: SIMD2<Double>) -> AnyTransition {
        Self.offset(x: offset.x, y: offset.y)
    }

    /// Moves the view in from `edge` while fading it in, and out towards the
    /// opposite edge while fading it out.
    /// 從 `edge` 移入並淡入，往相反的邊移出並淡出。
    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition { phase, size in
            let towards = phase == .insertion ? edge : edge.opposite
            return Effects(
                geometric: GeometricEffect(translation: translation(towards: towards, size: size)),
                visual: VisualEffect(opacity: 0)
            )
        }
    }

    /// `insertion` when the view is inserted, `removal` when it is removed.
    /// view 插入時用 `insertion`,移除時用 `removal`。
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        var transition = AnyTransition { phase, size in
            switch phase {
                case .insertion: insertion.effects(for: .insertion, size: size)
                case .removal: removal.effects(for: .removal, size: size)
            }
        }
        transition.phaseAnimations = (
            insertion.animation ?? insertion.phaseAnimations.insertion,
            removal.animation ?? removal.phaseAnimations.removal
        )
        return transition
    }

    /// The animations `asymmetric` took from its two transitions, per phase.
    /// `asymmetric` 從它的兩個轉場取來、各階段的動畫。
    var phaseAnimations: (insertion: Animation?, removal: Animation?) = (nil, nil)

    /// This transition and `other` together.
    /// 此轉場與 `other` 一起。
    public func combined(with other: AnyTransition) -> AnyTransition {
        var transition = AnyTransition { phase, size in
            effects(for: phase, size: size).combined(with: other.effects(for: phase, size: size))
        }
        transition.animation = animation ?? other.animation
        transition.phaseAnimations = (
            phaseAnimations.insertion ?? other.phaseAnimations.insertion,
            phaseAnimations.removal ?? other.phaseAnimations.removal
        )
        return transition
    }

    /// This transition drawn with `animation` instead of the animation the
    /// change runs under.
    /// 此轉場以 `animation` 畫出，取代這次改變所用的動畫。
    public func animation(_ animation: Animation?) -> AnyTransition {
        var transition = self
        transition.animation = animation
        return transition
    }

    /// The animation for `phase`: the transition's own, else `fallback`.
    /// `phase` 所用的動畫：轉場自己的，否則為 `fallback`。
    func animation(for phase: Phase, fallback: Animation?) -> Animation? {
        let own = phase == .insertion ? phaseAnimations.insertion : phaseAnimations.removal
        return animation ?? own ?? fallback
    }

    static func translation(towards edge: Edge, size: SIMD2<Double>) -> SIMD2<Double> {
        switch edge {
            case .leading: SIMD2(-size.x, 0)
            case .trailing: SIMD2(size.x, 0)
            case .top: SIMD2(0, -size.y)
            case .bottom: SIMD2(0, size.y)
        }
    }
}

extension Edge {
    /// The edge across from this one. / 與此邊相對的邊。
    var opposite: Edge {
        switch self {
            case .leading: .trailing
            case .trailing: .leading
            case .top: .bottom
            case .bottom: .top
        }
    }
}

extension View {
    /// How this view is drawn when an `if`, `if`/`else` or `ForEach` inserts or
    /// removes it under an animation -- SwiftUI's `transition(_:)`.
    ///
    /// Has no effect on a change made without an animation.
    ///
    /// `if`、`if`/`else` 或 `ForEach` 在動畫中插入或移除此 view 時它怎麼畫——SwiftUI 的 `transition(_:)`。
    /// 對不帶動畫的改變沒有作用。
    public func transition(_ transition: AnyTransition) -> some View {
        TransitionModifier(content: self, transition: transition)
    }
}

/// Drives one view's transition: what it draws now, and the tween that moves it.
/// 驅動一個 view 的轉場：它現在畫的東西，以及移動它的補間。
@MainActor
final class TransitionController {
    enum State: Equatable {
        /// Drawn as itself. / 畫成它自己。
        case shown
        case inserting
        case removing
        /// The removal ended; the container has been told.
        /// 移除已結束;已通知容器。
        case removed
    }

    var transition = AnyTransition.identity
    /// Sets the geometric effect on the outer container; replaced on every commit.
    /// 把幾何效果設到外層容器上;每次 commit 都會替換。
    var drawGeometric: ((AffineTransform) -> Void)?
    /// Sets the visual effect on the inner container; replaced on every commit.
    /// 把視覺效果設到內層容器上;每次 commit 都會替換。
    var drawVisual: ((VisualEffect) -> Void)?
    var diagnosticsLabel: String?
    /// Set by the container that inserted the view under an animation, before
    /// the view's first commit. / 由在動畫中插入此 view 的容器、於 view 第一次 commit 之前設定。
    var pendingInsertion: EffectTransaction?

    private(set) var state = State.shown
    /// How far the view is from the transition's state: `1` is identity.
    /// view 離轉場狀態多遠:`1` 是 identity。
    private(set) var presence = 1.0
    private(set) var phase = AnyTransition.Phase.insertion
    private(set) var size = SIMD2<Double>(0, 0)
    private var hasCommitted = false
    private var lastGeometric: AffineTransform?
    private var lastVisual: VisualEffect?
    private let key = UUID()

    init() {}

    deinit {
        AnimationDriver.shared.cancel(key: key)
    }

    /// Called on every commit of the view with its size.
    /// 每次 view commit 時以它的尺寸呼叫。
    func commit(size: SIMD2<Double>) {
        self.size = size
        if !hasCommitted {
            hasCommitted = true
            if let pending = pendingInsertion {
                pendingInsertion = nil
                if let animation = transition.animation(for: .insertion, fallback: pending.animation) {
                    insert(animation: animation, group: pending.group)
                    return
                }
            }
        }
        // A running tween draws its next frame with the new size.
        // 進行中的補間會以新的尺寸畫下一幀。
        if state == .shown {
            draw()
        }
    }

    /// Takes `size` as the committed size without drawing, for a default
    /// transition whose container is put in place by the container's commit
    /// after the removal has started.
    /// 把 `size` 當作已 commit 的尺寸而不繪製，供預設轉場使用：它的容器在移除開始之後，才由容器的 commit 放上。
    func adopt(size: SIMD2<Double>) {
        self.size = size
        hasCommitted = true
    }

    /// Starts the removal from what is drawn; `finished` runs when it ends.
    /// Returns false when there is nothing to animate (no animation), in which
    /// case `finished` is not called and the container removes the view now.
    /// 從畫出的狀態開始移除，結束時執行 `finished`。沒有東西要動畫(沒有動畫)時回傳 false,此時不會呼叫
    /// `finished`,由容器立刻移除 view。
    func remove(transaction: EffectTransaction, finished: @escaping @MainActor () -> Void) -> Bool {
        guard
            hasCommitted,
            let animation = transition.animation(for: .removal, fallback: transaction.animation)
        else { return false }
        let start = presence
        phase = .removal
        state = .removing
        AnimationDriver.shared.start(
            key: key,
            animation: animation,
            group: transaction.group,
            apply: { [weak self] progress in
                MainActor.assumeIsolated {
                    guard let self, self.state == .removing else { return }
                    self.presence = start * (1 - progress)
                    self.draw()
                }
            },
            finish: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state == .removing else { return }
                    self.state = .removed
                    finished()
                }
            }
        )
        return state == .removing || state == .removed
    }

    private func insert(animation: Animation, group: AnimationGroup?) {
        phase = .insertion
        state = .inserting
        presence = 0
        draw()
        AnimationDriver.shared.start(
            key: key,
            animation: animation,
            group: group,
            apply: { [weak self] progress in
                MainActor.assumeIsolated {
                    guard let self, self.state == .inserting else { return }
                    self.presence = progress
                    self.draw()
                }
            },
            finish: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state == .inserting else { return }
                    self.state = .shown
                    self.presence = 1
                    self.draw()
                }
            }
        )
    }

    /// The effects drawn now. / 現在畫出的效果。
    var effects: AnyTransition.Effects {
        // Presence 1 is identity in either phase, so a removal starting from a
        // shown view uses the removal's "away" state.
        // presence 為 1 時兩個階段都是 identity,所以從顯示狀態開始的移除用的是移除的「離開」狀態。
        switch phase {
            case .insertion:
                transition.effects(for: .insertion, size: size, progress: presence)
            case .removal:
                transition.effects(for: .removal, size: size, progress: 1 - presence)
        }
    }

    func draw() {
        var effects = effects
        // A zero scale is a singular transform, which GTK cannot invert to pick
        // the widget; a ten-thousandth draws the same nothing.
        // 縮放為零是奇異矩陣，GTK 無法反轉它來做點選;萬分之一畫出來同樣什麼都沒有。
        effects.geometric.scale = SIMD2(
            Self.awayFromZero(effects.geometric.scale.x),
            Self.awayFromZero(effects.geometric.scale.y)
        )
        let transform = effects.geometric.resolved(in: size)
        // Remembered only once set on a widget, so a container that arrives
        // later still gets the frame drawn now.
        // 只有真的設到 widget 上才記下，讓之後才到的容器仍會拿到現在這一幀。
        if transform != lastGeometric, let drawGeometric {
            lastGeometric = transform
            drawGeometric(transform)
        }
        if effects.visual != lastVisual, let drawVisual {
            lastVisual = effects.visual
            drawVisual(effects.visual)
        }
        if let diagnosticsLabel {
            TransitionDiagnostics.record(
                label: diagnosticsLabel,
                phase: phase,
                state: state,
                presence: presence,
                effects: effects,
                isDrawn: drawVisual != nil || drawGeometric != nil
            )
        }
    }

    static func awayFromZero(_ value: Double) -> Double {
        abs(value) < 0.0001 ? (value < 0 ? -0.0001 : 0.0001) : value
    }
}

/// The children of a transition modifier, with its controller.
/// 轉場 modifier 的 children,帶著它的 controller。
final class TransitionChildren<Content: View>: TupleViewChildren1<Content>, TransitionHosting {
    /// Made on first use, on the main actor. / 第一次使用時(於 main actor 上)建立。
    private var controller: TransitionController?
    /// The visual-effect container inside the geometric one.
    /// 幾何容器之內的視覺效果容器。
    var visualWidget: AnyWidget?

    var transitionController: TransitionController {
        if let controller {
            return controller
        }
        let made = TransitionController()
        controller = made
        return made
    }
}

/// Children that carry a view's transition, found by ``TransitionLookup``.
/// 帶著 view 轉場的 children,由 ``TransitionLookup`` 找到。
@MainActor
protocol TransitionHosting: AnyObject {
    var transitionController: TransitionController { get }
}

struct TransitionModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var transition: AnyTransition

    var body: TupleView1<Content> { content }

    typealias Children = TransitionChildren<Content>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(content, backend: backend, snapshots: snapshots, environment: environment)
    }

    /// The content inside a visual-effect container inside a geometric-effect
    /// container. A backend without one of the two draws that half unchanged.
    /// 內容包在視覺效果容器裡，再包在幾何效果容器裡。缺少其中一種的 backend,那一半畫成不變。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let inner = body.asWidget(children, backend: backend)
        let visual = VisualEffectWidgets.wrap(inner, backend: backend) ?? inner
        children.visualWidget = AnyWidget(visual)
        return GeometricEffectWidgets.wrap(visual, backend: backend) ?? visual
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    /// Unchanged from the child: a transition draws, it does not lay out.
    /// 與子元件相同：轉場只影響繪製，不影響排版。
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        let visual: Backend.Widget = children.visualWidget?.into() ?? widget
        backend.setSize(of: visual, to: size.vector)
        backend.setSize(of: widget, to: size.vector)

        let controller = children.transitionController
        controller.transition = transition
        controller.drawGeometric = GeometricEffectWidgets.setter(for: widget, backend: backend)
        controller.drawVisual = VisualEffectWidgets.setter(for: visual, backend: backend)
        controller.diagnosticsLabel = environment.effectDiagnosticsLabel
        controller.commit(size: SIMD2(Double(size.vector.x), Double(size.vector.y)))
    }
}

/// Finds the transition of an inserted or removed view: from its root down
/// through nodes with a single child, the first ``TransitionModifier``.
/// 找出被插入或移除之 view 的轉場：從它的根沿著只有一個子節點的節點往下，第一個 ``TransitionModifier``。
@MainActor
enum TransitionLookup {
    private struct Children: ErasedViewGraphNodeTransformer {
        func transform<V: View, Backend: BaseAppBackend>(
            node: ViewGraphNode<V, Backend>
        ) -> any ViewGraphNodeChildren {
            node.children
        }
    }

    static func controller(in node: ErasedViewGraphNode) -> TransitionController? {
        var children = node.transform(with: Children())
        for _ in 0..<64 {
            if let host = children as? any TransitionHosting {
                return host.transitionController
            }
            let nodes = children.erasedNodes
            guard nodes.count == 1 else { return nil }
            children = nodes[0].transform(with: Children())
        }
        return nil
    }

    static func controller<V: View>(in node: AnyViewGraphNode<V>) -> TransitionController? {
        controller(in: ErasedViewGraphNode(wrapping: node))
    }

    private struct CommittedSize: ErasedViewGraphNodeTransformer {
        func transform<V: View, Backend: BaseAppBackend>(
            node: ViewGraphNode<V, Backend>
        ) -> SIMD2<Int> {
            node.currentLayout?.size.vector ?? .zero
        }
    }

    /// The size `node` was last laid out at. / `node` 上次排版的尺寸。
    static func committedSize(of node: ErasedViewGraphNode) -> SIMD2<Int> {
        node.transform(with: CommittedSize())
    }

    /// The transaction a container's insertion or removal in this update runs
    /// under, if it is animated.
    /// 容器在這次更新中的插入或移除所在的 transaction(若帶動畫)。
    static func animatedTransaction(in environment: EnvironmentValues) -> EffectTransaction? {
        guard let transaction = EffectTransaction.current(in: environment),
            transaction.animation != nil
        else { return nil }
        return transaction
    }

    /// Sets up the transition of a view a container inserts under
    /// `transaction`, before its widget enters the container: its own
    /// `.transition`, or else the default fade.
    /// 為容器在 `transaction` 之下插入的 view 準備轉場，在它的 widget 進入容器之前：它自己的 `.transition`,否則是
    /// 預設的淡入。
    static func prepareInsertion(of node: ErasedViewGraphNode, transaction: EffectTransaction) {
        if let controller = controller(in: node) {
            controller.pendingInsertion = transaction
            return
        }
        guard let host = defaultTransitionHost(for: node, inserting: true),
            host.installDefaultTransitionWrapper() != nil
        else { return }
        host.defaultTransition?.controller.pendingInsertion = transaction
    }

    static func prepareInsertion<V: View>(of node: AnyViewGraphNode<V>, transaction: EffectTransaction) {
        prepareInsertion(of: ErasedViewGraphNode(wrapping: node), transaction: transaction)
    }

    /// The node that takes the default fade, or nil when the view does not fade:
    /// a view with a `matchedGeometryEffect` flies instead when it is removed,
    /// or inserted with an id another view has held.
    /// 接受預設淡入淡出的節點;view 不淡入淡出時為 nil:帶 `matchedGeometryEffect` 的 view 被移除時、或以另一個
    /// view 持有過的 id 插入時，改為飛過去。
    static func defaultTransitionHost(
        for node: ErasedViewGraphNode,
        inserting: Bool
    ) -> (any DefaultTransitionNode)? {
        if let key = matchedKey(in: node) {
            guard inserting, MatchedGeometryRegistry.shared.existing(key) == nil else { return nil }
        }
        return node.node as? any DefaultTransitionNode
    }

    /// The `matchedGeometryEffect` id at the root of `node`, down through
    /// nodes with a single child. / `node` 的根(沿著只有一個子節點的節點往下)上的 `matchedGeometryEffect` id。
    static func matchedKey(in node: ErasedViewGraphNode) -> MatchedGeometryKey? {
        var children = node.transform(with: Children())
        for _ in 0..<64 {
            if let host = children as? any MatchedGeometryHosting {
                return host.matchedKey
            }
            let nodes = children.erasedNodes
            guard nodes.count == 1 else { return nil }
            children = nodes[0].transform(with: Children())
        }
        return nil
    }

    /// The widget a container holds for `node`: the default fade's wrapper when
    /// it has one, else the node's own widget.
    /// 容器為 `node` 持有的 widget:有預設淡入淡出的包裝容器時是它，否則是節點自己的 widget。
    static func outerWidget(of node: ErasedViewGraphNode) -> AnyWidget {
        (node.node as? any DefaultTransitionNode)?.defaultTransition?.wrapper ?? node.getWidget()
    }

    static func outerWidget<V: View>(of node: AnyViewGraphNode<V>) -> AnyWidget {
        ((node.node as AnyObject) as? any DefaultTransitionNode)?.defaultTransition?.wrapper ?? node.widget
    }
}

/// The fade a view gets when a container inserts or removes it under an
/// animation and it has no `.transition` -- SwiftUI's default, `.opacity`: a
/// visual-effect container around the view's widget and the controller that
/// sets it each frame.
/// 容器在動畫中插入或移除一個沒有 `.transition` 的 view 時，它得到的淡入淡出——SwiftUI 的預設 `.opacity`:包在 view 的
/// widget 外的視覺效果容器，以及每一幀設定它的 controller。
@MainActor
final class DefaultTransitionSlot {
    let controller = TransitionController()
    /// The visual-effect container; nil until installed.
    /// 視覺效果容器;放上之前為 nil。
    private(set) var wrapper: AnyWidget?
    private var setWrapperSize: ((SIMD2<Int>) -> Void)?

    init() {
        controller.transition = .opacity
    }

    var isInstalled: Bool { wrapper != nil }

    /// Wraps `widget`, which must have no parent, in a visual-effect container;
    /// nil on a backend without one, or when already installed.
    /// 把沒有父層的 `widget` 包進一個視覺效果容器;backend 沒有這種容器、或已經放上時回傳 nil。
    func install<Backend: BaseAppBackend>(
        around widget: Backend.Widget,
        backend: Backend
    ) -> Backend.Widget? {
        guard wrapper == nil, let wrapped = VisualEffectWidgets.wrap(widget, backend: backend) else {
            return nil
        }
        wrapper = AnyWidget(wrapped)
        setWrapperSize = { size in backend.setSize(of: wrapped, to: size) }
        controller.drawVisual = VisualEffectWidgets.setter(for: wrapped, backend: backend)
        return wrapped
    }

    /// Called on every commit of the view: the wrapper takes its size, and the
    /// transition starts (on the first) or draws.
    /// view 每次 commit 時呼叫：包裝容器取得它的尺寸，轉場開始(第一次)或繪製。
    func commit(size: SIMD2<Int>, environment: EnvironmentValues) {
        guard isInstalled else { return }
        setWrapperSize?(size)
        controller.diagnosticsLabel = environment.effectDiagnosticsLabel
        controller.commit(size: SIMD2(Double(size.x), Double(size.y)))
    }

    /// The wrapper was put in place by the container's commit during a
    /// removal: it takes the size and the frame the removal is at.
    /// 包裝容器在移除期間由容器的 commit 放上：取得尺寸，以及移除進行到的那一幀。
    func placed(size: SIMD2<Int>) {
        setWrapperSize?(size)
        controller.draw()
    }
}

/// A view graph node that can take the default fade.
/// 可以接受預設淡入淡出的 view graph node。
@MainActor
protocol DefaultTransitionNode: AnyObject {
    var defaultTransition: DefaultTransitionSlot? { get set }
    /// Where the parent's layout last placed the node's widget (or wrapper).
    /// 父層排版上次放置節點 widget(或包裝容器)的位置。
    var committedPosition: SIMD2<Int>? { get set }
    /// Wraps the node's widget, which must have no parent, in its slot's
    /// container (made if needed); nil when that cannot be done.
    /// 把沒有父層的節點 widget 包進它的 slot 的容器(需要時建立);做不到時回傳 nil。
    func installDefaultTransitionWrapper() -> AnyWidget?
}

extension ViewGraphNode: DefaultTransitionNode {
    func installDefaultTransitionWrapper() -> AnyWidget? {
        let slot = defaultTransition ?? DefaultTransitionSlot()
        defaultTransition = slot
        return slot.install(around: widget, backend: backend).map { AnyWidget($0) }
    }
}

/// Children that carry a `matchedGeometryEffect` id, found by ``TransitionLookup``.
/// 帶著 `matchedGeometryEffect` id 的 children,由 ``TransitionLookup`` 找到。
@MainActor
protocol MatchedGeometryHosting: AnyObject {
    var matchedKey: MatchedGeometryKey { get }
}

/// Views a container removed under an animation, kept in the container after
/// its live children until their removal transitions end.
///
/// The container's children are its live ones followed by ``committed``, in
/// that order. A departure that ends is removed from the container by index,
/// counted from the live children the last commit left (``liveCount``); one
/// that ends before it was committed is dropped at the commit.
///
/// 容器在動畫中移除的 view,放在容器中的存活子元件之後，直到它們的移除轉場結束。容器的子元件依序是存活的子元件，
/// 然後是 ``committed``。結束的離場以索引從容器中移除，從上次 commit 留下的存活子元件數(``liveCount``)起算;
/// 在 commit 之前就結束的，則在 commit 時捨棄。
@MainActor
final class DepartingViews {
    final class Departure {
        let widget: AnyWidget
        /// Keeps the view graph node (and its transition) alive.
        /// 讓 view graph node(以及它的轉場)保持存活。
        let node: AnyObject
        let size: SIMD2<Int>
        var isFinished = false
        /// The node whose default fade needs its wrapper put in place at the
        /// container's commit; nil once done or when none is needed.
        /// 預設淡出需要在容器 commit 時放上包裝容器的節點;完成後或不需要時為 nil。
        var wrapsAtCommit: (any DefaultTransitionNode)?

        init(widget: AnyWidget, node: AnyObject, size: SIMD2<Int>) {
            self.widget = widget
            self.node = node
            self.size = size
        }

        /// Puts the default fade's wrapper where the departing widget is, at
        /// `index` in `container`: the widget comes out, goes into the wrapper,
        /// and the wrapper goes in at the same index and position.
        /// 把預設淡出的包裝容器放到離場 widget 所在之處，即 `container` 中的 `index`:widget 取出、放進包裝容器，
        /// 包裝容器放回同一個索引與位置。
        @MainActor func installWrapper<Backend: BaseAppBackend>(
            at index: Int,
            in container: Backend.Widget,
            backend: Backend
        ) {
            guard let host = wrapsAtCommit else { return }
            wrapsAtCommit = nil
            backend.remove(childAt: index, from: container)
            guard let wrapper = host.installDefaultTransitionWrapper() else {
                backend.insert(widget.into(), into: container, at: index)
                backend.setPosition(ofChildAt: index, in: container, to: host.committedPosition ?? .zero)
                return
            }
            backend.insert(wrapper.into(), into: container, at: index)
            backend.setPosition(ofChildAt: index, in: container, to: host.committedPosition ?? .zero)
            host.defaultTransition?.placed(size: size)
        }
    }

    /// In the container, after the live children, in order.
    /// 在容器中、存活子元件之後，依序排列。
    private(set) var committed: [Departure] = []
    /// Live children the last commit left in the container.
    /// 上次 commit 在容器中留下的存活子元件數。
    var liveCount = 0
    /// Removes the container's child at an index; set at each commit.
    /// 移除容器中某個索引的子元件;每次 commit 時設定。
    var removeChild: ((Int) -> Void)?

    init() {}

    var isEmpty: Bool { committed.isEmpty }

    /// Starts `node`'s removal transition when the update runs under an
    /// animation: its own `.transition`, or else the default fade. Nil when it
    /// should go at once (no animation, or a matched view).
    /// 當更新帶動畫時，啟動 `node` 的移除轉場：它自己的 `.transition`,否則是預設的淡出。應立刻移除時(沒有動畫，或是
    /// 對齊的 view)回傳 nil。
    func depart(
        _ node: ErasedViewGraphNode,
        environment: EnvironmentValues
    ) -> Departure? {
        guard let transaction = TransitionLookup.animatedTransaction(in: environment) else { return nil }
        let size = TransitionLookup.committedSize(of: node)
        let controller: TransitionController
        var wrapsAtCommit: (any DefaultTransitionNode)?
        if let own = TransitionLookup.controller(in: node) {
            controller = own
        } else if let host = TransitionLookup.defaultTransitionHost(for: node, inserting: false) {
            let slot = host.defaultTransition ?? DefaultTransitionSlot()
            host.defaultTransition = slot
            if !slot.isInstalled {
                // Its wrapper goes in at the container's commit.
                // 它的包裝容器在容器 commit 時放上。
                slot.controller.adopt(size: SIMD2(Double(size.x), Double(size.y)))
                slot.controller.diagnosticsLabel = environment.effectDiagnosticsLabel
                wrapsAtCommit = host
            }
            controller = slot.controller
        } else {
            return nil
        }
        let departure = Departure(
            widget: node.getWidget(),
            node: node.node,
            size: size
        )
        departure.wrapsAtCommit = wrapsAtCommit
        let started = controller.remove(transaction: transaction) { [weak self, weak departure] in
            guard let departure else { return }
            departure.isFinished = true
            self?.finished(departure)
        }
        // Without a frame clock the removal ends inside `remove`.
        // 沒有 frame clock 時，移除在 `remove` 之內就結束了。
        guard started, !departure.isFinished else { return nil }
        return departure
    }

    /// Puts `departures` (in container order) in front of the committed ones,
    /// which is where a container's removed children sit after a commit.
    /// 把 `departures`(依容器順序)放在已 commit 的離場之前——那正是容器被移除的子元件在 commit 之後所在的位置。
    func commit(_ departures: [Departure]) {
        committed.insert(contentsOf: departures.filter { !$0.isFinished }, at: 0)
    }

    /// A change of child at a commit, for a container whose live child is at
    /// index 0 (an `if`, an `if`/`else`). The previous child stays at index 0
    /// when it departs and is removed otherwise; `newChild` goes in front of it.
    /// 在 commit 時換子元件，供存活子元件位於索引 0 的容器(`if`、`if`/`else`)使用。前一個子元件若離場則留在
    /// 索引 0,否則移除;`newChild` 插在它前面。
    func commitSwitch<Backend: BaseAppBackend>(
        container: Backend.Widget,
        backend: Backend,
        hadChild: Bool,
        departure: Departure?,
        newChild: Backend.Widget?
    ) {
        let previousStays = departure.map { !$0.isFinished } ?? false
        if hadChild && !previousStays {
            backend.remove(childAt: 0, from: container)
        }
        if previousStays, let departure {
            departure.installWrapper(at: 0, in: container, backend: backend)
        }
        if let newChild {
            backend.insert(newChild, into: container, at: 0)
            backend.setPosition(ofChildAt: 0, in: container, to: .zero)
        }
        liveCount = newChild == nil ? 0 : 1
        if let departure {
            commit([departure])
        }
        removeChild = { index in
            backend.remove(childAt: index, from: container)
        }
    }

    /// The container's size: `size`, grown to hold the departing views, which
    /// sit at its origin, so a backend that clips to a container still draws them.
    /// 容器的尺寸:`size`,放大到容得下位於其原點的離場 view,讓會裁切到容器的 backend 仍畫得出它們。
    func containerSize(_ size: SIMD2<Int>) -> SIMD2<Int> {
        committed.reduce(size) { size, departure in
            SIMD2(max(size.x, departure.size.x), max(size.y, departure.size.y))
        }
    }

    func finished(_ departure: Departure) {
        guard let index = committed.firstIndex(where: { $0 === departure }) else { return }
        committed.remove(at: index)
        removeChild?(liveCount + index)
    }
}

/// What each labelled transition last drew, for test apps (P105) to compare a
/// frame in flight against the curve. Not SwiftUI API.
/// 每個加了標籤的轉場最後畫出的東西，供測試 app(P105)把飛行中的一幀與曲線比較。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum TransitionDiagnostics {
    public struct Sample: Sendable {
        public var time: Double
        public var phase: AnyTransition.Phase
        /// `1` is identity, `0` the transition's state.
        /// `1` 是 identity,`0` 是轉場狀態。
        public var presence: Double
        public var effects: AnyTransition.Effects
        public var isRunning: Bool
        /// Whether the effects were set on a widget (false while a default
        /// fade's container is not in place yet).
        /// 效果是否設到了 widget 上(預設淡入淡出的容器尚未放上時為 false)。
        public var isDrawn: Bool
    }

    public private(set) static var samples: [String: [Sample]] = [:]

    static func record(
        label: String,
        phase: AnyTransition.Phase,
        state: TransitionController.State,
        presence: Double,
        effects: AnyTransition.Effects,
        isDrawn: Bool
    ) {
        samples[label, default: []].append(
            Sample(
                time: ProcessInfo.processInfo.systemUptime,
                phase: phase,
                presence: presence,
                effects: effects,
                isRunning: state == .inserting || state == .removing,
                isDrawn: isDrawn
            )
        )
    }

    public static func clear() {
        samples = [:]
    }
}
