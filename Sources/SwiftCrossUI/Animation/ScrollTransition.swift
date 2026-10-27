import Foundation

/// Where a scroll view is scrolled to and how big it and its content are --
/// what ``View/onScrollGeometryChange(for:of:action:)`` hands its transform.
///
/// GSAP's ScrollTrigger reads the same numbers: `progress` for a scrubbed
/// animation is `contentOffset.y / (contentSize.height - containerSize.height)`.
///
/// 捲動視圖捲到哪裡、它與內容各有多大——``View/onScrollGeometryChange(for:of:action:)`` 交給其
/// transform 的就是這個。GSAP 的 ScrollTrigger 讀的是同一組數字：擦洗動畫的 `progress` 就是
/// `contentOffset.y / (contentSize.height - containerSize.height)`。
public struct ScrollGeometry: Equatable, Sendable {
    /// How far the content's top-leading corner is scrolled past the
    /// viewport's, in points.
    /// 內容的左上角被捲過視口左上角多遠(點)。
    public var contentOffset: SIMD2<Double>
    public var contentSize: ViewSize
    public var containerSize: ViewSize

    public init(contentOffset: SIMD2<Double>, contentSize: ViewSize, containerSize: ViewSize) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.containerSize = containerSize
    }

    /// The part of the content inside the viewport, in content coordinates.
    /// 位於視口內的那一部分內容(內容座標)。
    public var visibleRect: Path.Rect {
        Path.Rect(origin: contentOffset, size: SIMD2(containerSize.width, containerSize.height))
    }
}

/// Which side of the viewport a view is on, as SwiftUI's `scrollTransition`
/// reports it.
/// 一個 view 位於視口的哪一側，與 SwiftUI 的 `scrollTransition` 回報的相同。
public enum ScrollTransitionPhase: Equatable, Sendable {
    /// Leaving or not yet arrived at the top (or leading) edge.
    /// 正離開、或尚未抵達頂端(或前緣)。
    case topLeading
    /// In the viewport, past the threshold.
    /// 在視口內、已過門檻。
    case identity
    /// Leaving or not yet arrived at the bottom (or trailing) edge.
    /// 正離開、或尚未抵達底端(或後緣)。
    case bottomTrailing

    public var isIdentity: Bool { self == .identity }

    /// -1, 0 or 1.
    public var value: Double {
        switch self {
            case .topLeading: -1
            case .identity: 0
            case .bottomTrailing: 1
        }
    }
}

/// How a `scrollTransition` moves between its phases.
/// `scrollTransition` 在各階段之間如何移動。
public struct ScrollTransitionConfiguration: Sendable {
    /// When a view counts as fully in the viewport.
    /// 一個 view 何時算是完全在視口內。
    public struct Threshold: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case visible(Double)
            case centered
        }

        var kind: Kind

        /// Identity once `amount` of the view (0...1) is inside the viewport.
        /// 當 view 有 `amount`(0...1)在視口內時即為 identity。
        public static func visible(_ amount: Double) -> Threshold {
            Threshold(kind: .visible(min(max(amount, 0), 1)))
        }

        /// Identity as soon as any of it is visible.
        /// 只要有任何部分可見即為 identity。
        public static let visible = Threshold(kind: .visible(0))

        /// Identity only at the centre of the viewport, moving away on either side.
        /// 只有在視口中央才是 identity,往任一側都會離開。
        public static let centered = Threshold(kind: .centered)
    }

    enum Mode: Sendable {
        /// The effect follows the scroll position: GSAP's `scrub: true`.
        /// 效果跟著捲動位置走:GSAP 的 `scrub: true`。
        case interactive(any TimingCurve)
        /// The effect is animated to each phase as it is entered: GSAP's
        /// `toggleActions: "play reverse play reverse"`.
        /// 進入每個階段時以動畫轉到該階段:GSAP 的 `toggleActions: "play reverse play reverse"`。
        case animated(Animation)
        case identity
    }

    var mode: Mode
    var threshold: Threshold = .visible(1)

    /// Follows the scroll position, eased by `timingCurve`.
    /// 跟隨捲動位置，以 `timingCurve` 緩動。
    public static func interactive(timingCurve: some TimingCurve = Animation.Curve.easeInOut)
        -> ScrollTransitionConfiguration
    {
        ScrollTransitionConfiguration(mode: .interactive(timingCurve))
    }

    public static var interactive: ScrollTransitionConfiguration { .interactive() }

    /// Animates to each phase with `animation`.
    /// 以 `animation` 動畫到每個階段。
    public static func animated(_ animation: Animation = .default) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(mode: .animated(animation))
    }

    public static var animated: ScrollTransitionConfiguration { .animated() }

    /// Always the identity phase: the transition is switched off.
    /// 永遠是 identity 階段：轉場關閉。
    public static let identity = ScrollTransitionConfiguration(mode: .identity)

    public func threshold(_ threshold: Threshold) -> ScrollTransitionConfiguration {
        var copy = self
        copy.threshold = threshold
        return copy
    }

    public func animation(_ animation: Animation) -> ScrollTransitionConfiguration {
        var copy = self
        if case .animated = mode {
            copy.mode = .animated(animation)
        }
        return copy
    }
}

/// The effect a `scrollTransition` closure builds from the content it is given,
/// with the modifiers SwiftUI's `VisualEffect` has: `content.opacity(...)
/// .scaleEffect(...)` reads as it does in SwiftUI.
///
/// Drawing only, as SwiftUI requires of a visual effect: the view keeps its
/// layout, so scrolling never re-lays out the content.
///
/// `scrollTransition` closure 由所得內容建構的效果，具有 SwiftUI `VisualEffect` 的那些 modifier:
/// `content.opacity(...).scaleEffect(...)` 讀起來與 SwiftUI 相同。只影響繪製，正如 SwiftUI 對 visual
/// effect 的要求:view 保持其版面，所以捲動永遠不會讓內容重新排版。
public struct ScrollTransitionEffect: Equatable, Sendable {
    public var visual = VisualEffect()
    public var geometric = GeometricEffect.identity

    public init() {}

    public func opacity(_ opacity: Double) -> Self {
        var copy = self
        copy.visual.opacity *= opacity
        return copy
    }

    public func blur(radius: Double) -> Self {
        var copy = self
        copy.visual.blurRadius += radius
        return copy
    }

    public func saturation(_ amount: Double) -> Self {
        var copy = self
        copy.visual.saturation *= amount
        return copy
    }

    public func brightness(_ amount: Double) -> Self {
        var copy = self
        copy.visual.brightness += amount
        return copy
    }

    public func contrast(_ amount: Double) -> Self {
        var copy = self
        copy.visual.contrast *= amount
        return copy
    }

    public func grayscale(_ amount: Double) -> Self {
        var copy = self
        copy.visual.grayscale = max(copy.visual.grayscale, amount)
        return copy
    }

    public func hueRotation(_ angle: Angle) -> Self {
        var copy = self
        copy.visual.hueRotation = copy.visual.hueRotation + angle
        return copy
    }

    public func offset(x: Double = 0, y: Double = 0) -> Self {
        var copy = self
        copy.geometric.translation += SIMD2(x, y)
        return copy
    }

    public func offset(_ offset: SIMD2<Double>) -> Self {
        self.offset(x: offset.x, y: offset.y)
    }

    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> Self {
        scaleEffect(x: scale, y: scale, anchor: anchor)
    }

    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> Self {
        var copy = self
        copy.geometric.scale *= SIMD2(x, y)
        copy.geometric.anchor = anchor
        return copy
    }

    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> Self {
        var copy = self
        copy.geometric.rotation = copy.geometric.rotation + angle
        copy.geometric.anchor = anchor
        return copy
    }

    /// Component by component, which is what "between two effects" means for
    /// numbers that each draw independently.
    /// 逐分量插值——對各自獨立繪製的數值而言,「兩個效果之間」就是這個意思。
    static func interpolated(from start: Self, to end: Self, progress p: Double) -> Self {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        var result = Self()
        result.visual = VisualEffect(
            opacity: lerp(start.visual.opacity, end.visual.opacity),
            blurRadius: lerp(start.visual.blurRadius, end.visual.blurRadius),
            saturation: lerp(start.visual.saturation, end.visual.saturation),
            brightness: lerp(start.visual.brightness, end.visual.brightness),
            contrast: lerp(start.visual.contrast, end.visual.contrast),
            grayscale: lerp(start.visual.grayscale, end.visual.grayscale),
            hueRotation: .radians(lerp(start.visual.hueRotation.radians, end.visual.hueRotation.radians))
        )
        result.geometric = GeometricEffect(
            translation: start.geometric.translation
                + (end.geometric.translation - start.geometric.translation) * p,
            scale: start.geometric.scale + (end.geometric.scale - start.geometric.scale) * p,
            rotation: .radians(lerp(start.geometric.rotation.radians, end.geometric.rotation.radians)),
            anchor: p < 0.5 ? start.geometric.anchor : end.geometric.anchor
        )
        return result
    }
}

/// The scroll arithmetic, pure so it is tested without a backend.
/// 捲動的算術，純函式，因此不需要 backend 就能測試。
enum ScrollTransitionMath {
    /// Where a view is relative to the viewport along one axis, from -1 (all
    /// the way past the top/leading edge) through 0 (identity) to 1.
    ///
    /// With `.visible(a)`: identity while at least `a` of the view is inside;
    /// below that, the hidden share moves it toward ±1, reaching it when the
    /// view is fully out. The sign is the side its centre is on.
    /// With `.centered`: the centre's distance from the viewport's centre over
    /// the distance at which the view has just left.
    ///
    /// 一個 view 沿某一軸相對於視口的位置，從 -1(完全越過頂端/前緣)經 0(identity)到 1。
    /// `.visible(a)`:只要 view 至少有 `a` 在視口內就是 identity;低於此時，被藏住的比例把它推向 ±1,
    /// 完全離開時抵達。正負號取決於其中心在哪一側。`.centered`:中心與視口中心的距離，除以 view 剛好
    /// 離開時的那個距離。
    static func position(
        start: Double,
        length: Double,
        viewport: Double,
        threshold: ScrollTransitionConfiguration.Threshold
    ) -> Double {
        let center = start + length / 2
        let side: Double = center < viewport / 2 ? -1 : 1
        switch threshold.kind {
            case .centered:
                let reach = (viewport + length) / 2
                guard reach > 0 else { return 0 }
                return min(max((center - viewport / 2) / reach, -1), 1)
            case .visible(let amount):
                let visible: Double
                if length > 0 {
                    let shown = min(start + length, viewport) - max(start, 0)
                    visible = min(max(shown, 0), length) / length
                } else {
                    visible = (start >= 0 && start <= viewport) ? 1 : 0
                }
                let toIdentity = amount > 0 ? min(visible / amount, 1) : (visible > 0 ? 1 : 0)
                return side * (1 - toIdentity)
        }
    }

    static func phase(_ position: Double) -> ScrollTransitionPhase {
        position < 0 ? .topLeading : position > 0 ? .bottomTrailing : .identity
    }

    /// The share of the view inside the viewport, 0...1, for `onScrollVisibilityChange`.
    /// view 在視口內的比例(0...1),供 `onScrollVisibilityChange` 使用。
    static func visibleShare(start: Double, length: Double, viewport: Double) -> Double {
        guard length > 0 else { return (start >= 0 && start <= viewport) ? 1 : 0 }
        let shown = min(start + length, viewport) - max(start, 0)
        return min(max(shown, 0), length) / length
    }
}

/// An `onScrollGeometryChange` registration, carried to its ScrollView by the
/// environment. Its last value is kept by the ScrollView's hub, by position.
/// 一筆 `onScrollGeometryChange` 登記，經由環境帶到它的 ScrollView。它的上一個值由該 ScrollView 的
/// hub 依位置保存。
struct ScrollGeometryObserver: @unchecked Sendable {
    /// Returns the new value, calling the action first if it differs from `previous`.
    /// 回傳新值;若與 `previous` 不同，先呼叫 action。
    var evaluate: @MainActor (ScrollGeometry, _ previous: Any?) -> Any
}

/// One ScrollView's geometry and everything that listens to it.
///
/// Created by the ScrollView and handed to its content in the environment, so a
/// `scrollTransition` inside reaches the scroll view it is in -- the innermost
/// one, because a nested ScrollView replaces it for its own content.
///
/// 一個 ScrollView 的幾何，以及所有聆聽它的東西。由 ScrollView 建立，經環境交給其內容，因此裡面的
/// `scrollTransition` 能找到它所在的那個捲動視圖——最內層的那一個，因為巢狀 ScrollView 會為自己的
/// 內容換掉它。
@MainActor
final class ScrollGeometryHub {
    private(set) var geometry = ScrollGeometry(
        contentOffset: .zero, contentSize: .zero, containerSize: .zero
    )
    /// Which axes scroll; a transition with no axis of its own uses vertical
    /// when it scrolls, else horizontal.
    /// 哪些軸會捲動;沒有自訂軸的轉場，可垂直捲動時用垂直，否則用水平。
    var axes: Axis.Set = .vertical
    /// Where the scrolled content's top-leading corner is in the window, asked
    /// after a commit; a tracked view's place in the content is its own origin
    /// minus this, which scrolling does not change.
    /// 被捲動內容的左上角在視窗中的位置(commit 之後詢問);被追蹤 view 在內容中的位置是它自己的原點
    /// 減去這個值，而捲動不會改變它。
    var contentOrigin: (@MainActor () -> SIMD2<Int>?)?
    private var trackers: [ObjectIdentifier: WeakTracker] = [:]
    private var observers: [ScrollGeometryObserver] = []
    private var observerValues: [Any?] = []

    struct WeakTracker {
        weak var node: ScrollTrackingNode?
    }

    var defaultAxis: Axis {
        axes.contains(.vertical) ? .vertical : .horizontal
    }

    func register(_ node: ScrollTrackingNode) {
        trackers[ObjectIdentifier(node)] = WeakTracker(node: node)
    }

    func setObservers(_ observers: [ScrollGeometryObserver]) {
        if observers.count != self.observers.count {
            observerValues = Array(repeating: nil, count: observers.count)
        }
        self.observers = observers
    }

    /// Takes new numbers, and tells every listener when any of them changed.
    /// 接收新數字;只要有任何一個改變，就通知每個聆聽者。
    func update(
        contentOffset: SIMD2<Double>? = nil,
        contentSize: ViewSize? = nil,
        containerSize: ViewSize? = nil,
        force: Bool = false
    ) {
        var next = geometry
        if let contentOffset { next.contentOffset = contentOffset }
        if let contentSize { next.contentSize = contentSize }
        if let containerSize { next.containerSize = containerSize }
        guard force || next != geometry else { return }
        geometry = next
        for (index, observer) in observers.enumerated() {
            observerValues[index] = observer.evaluate(next, observerValues[index])
        }
        trackers = trackers.filter { $0.value.node != nil }
        for tracker in trackers.values {
            tracker.node?.scrolled(self)
        }
    }
}

/// One `scrollTransition` or `onScrollVisibilityChange` view's state, kept
/// across updates by its node.
/// 一個 `scrollTransition` 或 `onScrollVisibilityChange` view 的狀態，由其節點跨更新保留。
@MainActor
final class ScrollTrackingNode {
    /// The view's frame in the scrolled content's coordinates.
    /// view 在被捲動內容座標中的 frame。
    var frameInContent: Path.Rect?
    weak var hub: ScrollGeometryHub?
    /// What to do with the view's place in the viewport: (start, length,
    /// viewport length) along the axis it was given.
    /// 拿 view 在視口中的位置做什麼:沿指定軸的 (起點、長度、視口長度)。
    var onScroll: (@MainActor (_ start: Double, _ length: Double, _ viewport: Double) -> Void)?
    var axis: Axis?

    func scrolled(_ hub: ScrollGeometryHub) {
        guard let frame = frameInContent, let onScroll else { return }
        let geometry = hub.geometry
        switch axis ?? hub.defaultAxis {
            case .vertical:
                onScroll(
                    frame.origin.y - geometry.contentOffset.y,
                    frame.size.y,
                    geometry.containerSize.height
                )
            case .horizontal:
                onScroll(
                    frame.origin.x - geometry.contentOffset.x,
                    frame.size.x,
                    geometry.containerSize.width
                )
        }
    }
}

extension View {
    /// Draws this view through `transition` according to where it is in the
    /// enclosing ScrollView's viewport -- SwiftUI's name for a GSAP
    /// ScrollTrigger tween.
    ///
    /// ```swift
    /// ScrollView {
    ///     ForEach(cards) { card in
    ///         CardView(card)
    ///             .scrollTransition { content, phase in
    ///                 content
    ///                     .opacity(phase.isIdentity ? 1 : 0.3)
    ///                     .scaleEffect(phase.isIdentity ? 1 : 0.8)
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// The closure is evaluated for the three phases and the view is drawn
    /// between them: in proportion to the scroll for `.interactive` (GSAP's
    /// `scrub`), or animated to each phase as it is entered for `.animated`
    /// (GSAP's `toggleActions`). The effect is set on the widget directly when
    /// the scroll view reports a scroll, with no re-render. Outside a
    /// ScrollView the view stays in the identity phase.
    ///
    /// 依照此 view 在外層 ScrollView 視口中的位置，以 `transition` 繪製它——SwiftUI 對 GSAP ScrollTrigger
    /// 補間的名稱。closure 會針對三個階段求值，view 被畫在它們之間:`.interactive` 依捲動比例(GSAP 的
    /// `scrub`),`.animated` 在進入每個階段時以動畫轉過去(GSAP 的 `toggleActions`)。捲動視圖回報捲動時，
    /// 效果直接設到 widget 上，不重新算繪。不在 ScrollView 內時，view 停在 identity 階段。
    public func scrollTransition(
        _ configuration: ScrollTransitionConfiguration = .interactive,
        axis: Axis? = nil,
        transition: @escaping @MainActor (ScrollTransitionEffect, ScrollTransitionPhase) ->
            ScrollTransitionEffect
    ) -> some View {
        scrollTransition(
            topLeading: configuration,
            bottomTrailing: configuration,
            axis: axis,
            transition: transition
        )
    }

    /// The same, with a configuration for each edge.
    /// 同上，兩個邊緣各用一個設定。
    public func scrollTransition(
        topLeading: ScrollTransitionConfiguration,
        bottomTrailing: ScrollTransitionConfiguration,
        axis: Axis? = nil,
        transition: @escaping @MainActor (ScrollTransitionEffect, ScrollTransitionPhase) ->
            ScrollTransitionEffect
    ) -> some View {
        ScrollTrackingModifier(
            body: TupleView1(self),
            axis: axis,
            drawsEffects: true,
            makeHandler: { node, drawer in
                ScrollTransitionHandler.make(
                    node: node,
                    drawer: drawer,
                    topLeading: topLeading,
                    bottomTrailing: bottomTrailing,
                    transition: transition
                )
            }
        )
    }

    /// Calls `action` with true when at least `threshold` of this view is
    /// inside the enclosing ScrollView's viewport and false when it no longer
    /// is -- GSAP's ScrollTrigger `onEnter`/`onLeave`. Called once with the
    /// first answer.
    /// 當此 view 至少有 `threshold` 在外層 ScrollView 的視口內時以 true 呼叫 `action`,不再如此時以 false
    /// 呼叫——GSAP ScrollTrigger 的 `onEnter`/`onLeave`。第一個答案出現時呼叫一次。
    public func onScrollVisibilityChange(
        threshold: Double = 0.5,
        _ action: @escaping @MainActor (Bool) -> Void
    ) -> some View {
        ScrollTrackingModifier(
            body: TupleView1(self),
            axis: nil,
            drawsEffects: false,
            makeHandler: { node, _ in
                var last: Bool?
                return { start, length, viewport in
                    let share = ScrollTransitionMath.visibleShare(
                        start: start, length: length, viewport: viewport
                    )
                    let visible = share >= max(threshold, 1e-9)
                    if visible != last {
                        last = visible
                        action(visible)
                    }
                }
            }
        )
    }

    /// Calls `action` when the value `transform` reads from the scroll
    /// geometry changes. Apply it to a ScrollView.
    ///
    /// ```swift
    /// ScrollView { ... }
    ///     .onScrollGeometryChange(for: Double.self) { geometry in
    ///         geometry.contentOffset.y
    ///     } action: { _, offset in
    ///         player.seek(progress: offset / 600)   // a scrubbed GSAP timeline
    ///     }
    /// ```
    ///
    /// 當 `transform` 從捲動幾何讀出的值改變時呼叫 `action`。套用在 ScrollView 上。
    public func onScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping @MainActor (ScrollGeometry) -> T,
        action: @escaping @MainActor (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        let observer = ScrollGeometryObserver { geometry, previous in
            let value = transform(geometry)
            if let old = previous as? T, old != value {
                action(old, value)
            }
            return value
        }
        return EnvironmentModifier(self) { environment in
            environment.with(
                \.scrollGeometryObservers,
                environment.scrollGeometryObservers + [observer]
            )
        }
    }
}

/// The widgets a scroll-tracked view draws through.
/// 被捲動追蹤的 view 用來繪製的 widget。
@MainActor
struct ScrollEffectDrawer {
    var draw: (ScrollTransitionEffect) -> Void
}

/// Turns a phase position into drawn effects for `scrollTransition`.
/// 把階段位置轉成 `scrollTransition` 的繪製效果。
@MainActor
enum ScrollTransitionHandler {
    static func make(
        node: ScrollTrackingNode,
        drawer: ScrollEffectDrawer,
        topLeading: ScrollTransitionConfiguration,
        bottomTrailing: ScrollTransitionConfiguration,
        transition: @escaping @MainActor (ScrollTransitionEffect, ScrollTransitionPhase) ->
            ScrollTransitionEffect
    ) -> @MainActor (Double, Double, Double) -> Void {
        let state = ScrollTransitionState()
        var isAnimated = false
        if case .animated = topLeading.mode {
            isAnimated = true
        }
        ScrollTransitionDiagnostics.track(node: node, state: state, isAnimated: isAnimated)
        return { start, length, viewport in
            let configuration = start + length / 2 < viewport / 2 ? topLeading : bottomTrailing
            let position = ScrollTransitionMath.position(
                start: start, length: length, viewport: viewport,
                threshold: configuration.threshold
            )
            let identity = transition(ScrollTransitionEffect(), .identity)
            switch configuration.mode {
                case .identity:
                    state.show(identity, drawer)
                case .interactive(let curve):
                    let phase = ScrollTransitionMath.phase(position)
                    let edge = transition(ScrollTransitionEffect(), phase)
                    let amount = curve.progress(at: abs(position))
                    state.show(
                        ScrollTransitionEffect.interpolated(from: identity, to: edge, progress: amount),
                        drawer
                    )
                case .animated(let animation):
                    // Discrete: only a full crossing changes the phase.
                    // 離散：只有完整越過才會改變階段。
                    let phase: ScrollTransitionPhase =
                        abs(position) >= 1 ? ScrollTransitionMath.phase(position)
                        : position == 0 ? .identity : (state.phase ?? .identity)
                    guard phase != state.phase else { return }
                    let target = transition(ScrollTransitionEffect(), phase)
                    if state.phase == nil {
                        state.phase = phase
                        state.show(target, drawer)
                        return
                    }
                    state.phase = phase
                    state.animate(to: target, with: animation, drawer)
            }
        }
    }
}

/// What one `scrollTransition` view is drawing now.
/// 一個 `scrollTransition` view 此刻正在繪製的東西。
@MainActor
final class ScrollTransitionState {
    var shown = ScrollTransitionEffect()
    var phase: ScrollTransitionPhase?
    let tweenKey = UUID()

    func show(_ effect: ScrollTransitionEffect, _ drawer: ScrollEffectDrawer) {
        guard effect != shown else { return }
        shown = effect
        drawer.draw(effect)
    }

    func animate(to target: ScrollTransitionEffect, with animation: Animation, _ drawer: ScrollEffectDrawer) {
        let start = shown
        AnimationDriver.shared.start(key: tweenKey, animation: animation, group: nil) {
            [weak self] progress in
            MainActor.assumeIsolated {
                self?.show(
                    ScrollTransitionEffect.interpolated(from: start, to: target, progress: progress),
                    drawer
                )
            }
        }
    }
}

final class ScrollTrackingChildren<Content: View>: ViewGraphNodeChildren {
    let children: TupleViewChildren1<Content>
    let node = ScrollTrackingNode()
    var visual: AnyWidget?
    var geometric: AnyWidget?
    var drawer: ScrollEffectDrawer?
    var handlerInstalled = false
    var retryScheduled = false

    init(_ children: TupleViewChildren1<Content>) {
        self.children = children
    }

    var widgets: [AnyWidget] { children.widgets }
    var erasedNodes: [ErasedViewGraphNode] { children.erasedNodes }
}

struct ScrollTrackingModifier<Content: View>: TypeSafeView {
    var body: TupleView1<Content>
    var axis: Axis?
    var drawsEffects: Bool
    var makeHandler:
        @MainActor (ScrollTrackingNode, ScrollEffectDrawer) -> @MainActor (Double, Double, Double) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> ScrollTrackingChildren<Content> {
        ScrollTrackingChildren(
            TupleViewChildren1(
                body.view0,
                backend: backend,
                snapshots: snapshots,
                environment: environment
            )
        )
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: ScrollTrackingChildren<Content>
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    /// outer container (measured) > visual effect container > geometric effect
    /// container > child. The outer one is measured for the reason given on
    /// `matchedGeometryEffect`: a transform must not be read back as a position.
    /// 外層容器(被量測)> 視覺效果容器 > 幾何效果容器 > 子元件。量測外層的理由與
    /// `matchedGeometryEffect` 相同:transform 不可被讀回成位置。
    func asWidget<Backend: BaseAppBackend>(
        _ children: ScrollTrackingChildren<Content>,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.children.child0.widget.into()
        let outer = backend.createContainer()
        guard drawsEffects else {
            backend.insert(child, into: outer, at: 0)
            return outer
        }
        var top = child
        if let geometric = GeometricEffectWidgets.wrap(top, backend: backend) {
            children.geometric = AnyWidget(geometric)
            top = geometric
        } else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support geometric effects; scrollTransition draws no transforms"
            )
        }
        if let visual = VisualEffectWidgets.wrap(top, backend: backend) {
            children.visual = AnyWidget(visual)
            top = visual
        } else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support visual effects; scrollTransition draws no opacity or filters"
            )
        }
        backend.insert(top, into: outer, at: 0)
        return outer
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ScrollTrackingChildren<Content>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: ScrollTrackingChildren<Content>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
        let sizeVector = SIMD2(Double(size.vector.x), Double(size.vector.y))

        var setVisual: ((VisualEffect) -> Void)?
        var setGeometric: ((AffineTransform) -> Void)?
        if let visual = children.visual {
            let visualWidget: Backend.Widget = visual.into()
            backend.setSize(of: visualWidget, to: size.vector)
            setVisual = VisualEffectWidgets.setter(for: visualWidget, backend: backend)
        }
        if let geometric = children.geometric {
            let geometricWidget: Backend.Widget = geometric.into()
            backend.setSize(of: geometricWidget, to: size.vector)
            setGeometric = GeometricEffectWidgets.setter(for: geometricWidget, backend: backend)
        }
        let drawer = ScrollEffectDrawer { effect in
            setVisual?(effect.visual)
            setGeometric?(effect.geometric.resolved(in: sizeVector))
        }
        let node = children.node
        node.axis = axis
        if !children.handlerInstalled {
            children.handlerInstalled = true
            children.drawer = drawer
            node.onScroll = makeHandler(node, ScrollEffectDrawer { effect in
                children.drawer?.draw(effect)
            })
        } else {
            children.drawer = drawer
        }

        guard let hub = environment.scrollGeometryHub else { return }
        node.hub = hub
        hub.register(node)
        let measured = AnyWidget(widget)
        LayoutSettleQueue.enqueue(backend) { [weak children] in
            guard let children else { return }
            Self.measure(children, measured: measured, size: sizeVector, hub: hub, backend: backend)
        }
    }

    /// Takes the view's place in the content, then draws it for the current scroll.
    /// 取得 view 在內容中的位置，然後依目前的捲動繪製它。
    @MainActor
    static func measure<Backend: BaseAppBackend>(
        _ children: ScrollTrackingChildren<Content>,
        measured: AnyWidget,
        size: SIMD2<Double>,
        hub: ScrollGeometryHub,
        backend: Backend
    ) {
        let origin = GeometryReader<EmptyView>.originInWindow(
            of: measured.into() as Backend.Widget, backend: backend
        )
        if let origin, let content = hub.contentOrigin?() {
            children.node.frameInContent = Path.Rect(
                origin: SIMD2(Double(origin.x - content.x), Double(origin.y - content.y)),
                size: size
            )
            children.node.scrolled(hub)
        } else if !children.retryScheduled {
            children.retryScheduled = true
            retry(children, measured: measured, size: size, hub: hub, backend: backend, attempt: 1)
        }
    }

    /// Measures again until the view has a place: WinUI lays out on a pass of
    /// its own, after the dispatcher turn that ran `commit`, so a single retry
    /// could still find the rows unplaced. P101's START read 0 of 20 rows on
    /// WinUI (2026-10-19 and 2026-10-21) and the rows were measured only when
    /// a scroll committed them again. The first retry is the next main-thread
    /// turn; the rest are 50 ms apart, for up to two seconds.
    ///
    /// 重新量測，直到 view 有了位置:WinUI 以自己的一輪排版，在執行 `commit` 的那一輪 dispatcher 之後，
    /// 所以只重試一次仍可能找不到列的位置。P101 的 START 在 WinUI 上 20 列只量到 0 列(2026-10-19 與
    /// 2026-10-21),要等一次捲動讓它們重新 commit 才量到。第一次重試是下一輪主執行緒;其餘間隔 50 毫秒，
    /// 最多兩秒。
    @MainActor
    static func retry<Backend: BaseAppBackend>(
        _ children: ScrollTrackingChildren<Content>,
        measured: AnyWidget,
        size: SIMD2<Double>,
        hub: ScrollGeometryHub,
        backend: Backend,
        attempt: Int
    ) {
        let again: @MainActor () -> Void = { [weak children] in
            guard let children else { return }
            if let origin = GeometryReader<EmptyView>.originInWindow(
                of: measured.into() as Backend.Widget, backend: backend
            ),
                let content = hub.contentOrigin?()
            {
                children.retryScheduled = false
                children.node.frameInContent = Path.Rect(
                    origin: SIMD2(Double(origin.x - content.x), Double(origin.y - content.y)),
                    size: size
                )
                children.node.scrolled(hub)
            } else if attempt < 40 {
                retry(
                    children, measured: measured, size: size, hub: hub, backend: backend,
                    attempt: attempt + 1
                )
            } else {
                children.retryScheduled = false
            }
        }
        if attempt == 1 {
            backend.runInMainThread(action: again)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated(again)
            }
        }
    }
}

/// Opens a backend's ``BackendFeatures/VisualEffects`` for modifiers that set
/// the effect themselves.
/// 為自行設定效果的 modifier 開啟 backend 的 ``BackendFeatures/VisualEffects``。
@MainActor
enum VisualEffectWidgets {
    static func wrap<Backend: BaseAppBackend>(
        _ child: Backend.Widget,
        backend: Backend
    ) -> Backend.Widget? {
        guard let capable = backend as? any BackendFeatures.VisualEffects else { return nil }
        func open<B: BackendFeatures.VisualEffects>(_ backend: B) -> Backend.Widget {
            backend.createVisualEffectContainer(wrapping: child as! B.Widget) as! Backend.Widget
        }
        return open(capable)
    }

    static func setter<Backend: BaseAppBackend>(
        for widget: Backend.Widget,
        backend: Backend
    ) -> ((VisualEffect) -> Void)? {
        guard let capable = backend as? any BackendFeatures.VisualEffects else { return nil }
        func open<B: BackendFeatures.VisualEffects>(_ backend: B) -> (VisualEffect) -> Void {
            let widget = widget as! B.Widget
            return { backend.setVisualEffect($0, ofWidget: widget) }
        }
        return open(capable)
    }
}

/// Opens a backend's ``BackendFeatures/ScrollOffsetReporting`` for ScrollView.
/// 為 ScrollView 開啟 backend 的 ``BackendFeatures/ScrollOffsetReporting``。
@MainActor
enum ScrollOffsets {
    /// Connects `scrollView` to `hub`: the offset now, and every scroll after.
    /// 把 `scrollView` 接到 `hub`:現在的位移，以及之後的每一次捲動。
    static func connect<Backend: BaseAppBackend>(
        _ scrollView: Backend.Widget,
        backend: Backend,
        hub: ScrollGeometryHub
    ) -> SIMD2<Double>? {
        guard let capable = backend as? any BackendFeatures.ScrollOffsetReporting else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't report scroll offsets; scrollTransition and onScrollGeometryChange see no scrolling"
            )
            return nil
        }
        func open<B: BackendFeatures.ScrollOffsetReporting>(_ backend: B) -> SIMD2<Double> {
            let widget = scrollView as! B.Widget
            backend.setContentOffsetHandler(ofScrollContainer: widget) { [weak hub] offset in
                hub?.update(contentOffset: offset)
            }
            return backend.contentOffset(ofScrollContainer: widget)
        }
        return open(capable)
    }
}

/// What every live `scrollTransition` view is drawing, for test apps that
/// check it against the scroll position. Not SwiftUI API.
/// 每個存活的 `scrollTransition` view 正在繪製什麼，供拿它對照捲動位置的測試 app 使用。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum ScrollTransitionDiagnostics {
    public struct Entry {
        /// The view's frame in the scrolled content; nil until measured.
        /// view 在被捲動內容中的 frame;量到之前為 nil。
        public var frameInContent: Path.Rect?
        public var effect: ScrollTransitionEffect
        public var isAnimated: Bool
    }

    private struct Tracked {
        weak var node: ScrollTrackingNode?
        weak var state: ScrollTransitionState?
        var isAnimated: Bool
    }

    private static var tracked: [Tracked] = []

    static func track(node: ScrollTrackingNode, state: ScrollTransitionState, isAnimated: Bool) {
        tracked.removeAll { $0.node == nil || $0.state == nil }
        tracked.append(Tracked(node: node, state: state, isAnimated: isAnimated))
    }

    public static func entries() -> [Entry] {
        tracked.compactMap { item in
            guard let node = item.node, let state = item.state else { return nil }
            return Entry(frameInContent: node.frameInContent, effect: state.shown, isAnimated: item.isAnimated)
        }
    }
}
