import Foundation

/// A namespace for ``View/matchedGeometryEffect(id:in:properties:anchor:isSource:)``
/// ids, kept for as long as the view that declares it.
///
/// ```swift
/// @Namespace var cards
/// ...
/// ForEach(order, id: \.self) { n in
///     Card(n).matchedGeometryEffect(id: n, in: cards)
/// }
/// Button("Shuffle") { withAnimation(.power2(.out)) { order.shuffle() } }
/// ```
///
/// 供 ``View/matchedGeometryEffect(id:in:properties:anchor:isSource:)`` 的 id 使用的命名空間，
/// 與宣告它的 view 存活一樣久。
@propertyWrapper
public struct Namespace: DynamicProperty {
    public struct ID: Hashable, Sendable {
        let raw: UUID
    }

    private let box: Box<ID>

    public init() {
        box = Box(ID(raw: UUID()))
    }

    public var wrappedValue: ID { box.value }

    /// The view struct is rebuilt on every update; the id it had first is the
    /// one it keeps, the same hand-over `@State` makes with its storage.
    /// view struct 每次更新都會重建;它保留第一次拿到的 id,與 `@State` 交接儲存的方式相同。
    public func update(with environment: EnvironmentValues, previousValue: Namespace?) {
        if let previousValue {
            box.value = previousValue.box.value
        }
    }
}

/// Which parts of the frame `matchedGeometryEffect` matches.
/// `matchedGeometryEffect` 要對齊 frame 的哪些部分。
public struct MatchedGeometryProperties: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The anchor point's position.
    /// 錨點的位置。
    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    /// The size, drawn as a scale about the anchor.
    /// 尺寸，以繞錨點的縮放繪製。
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

extension View {
    /// Animates this view from where a view with the same `id` was to where
    /// this one is, whenever its frame changes inside `withAnimation` --
    /// SwiftUI's name for what GSAP's Flip plugin does.
    ///
    /// ```swift
    /// withAnimation(.linear(duration: 0.6)) { order.reverse() }
    /// ```
    ///
    /// Two cases are one mechanism. A view that MOVES (a reordered `ForEach`
    /// item, a block that changes stack) flies from its old frame. A view that
    /// REPLACES another with the same id (a thumbnail that becomes a detail
    /// view) flies from the frame the other one had. Outside an animation the
    /// view simply takes its new place.
    ///
    /// **Drawn, not laid out, which is also how Flip works.** The layout jumps
    /// to the end at once; what animates is a translation and, with `.size`, a
    /// scale about `anchor`, set on the widget every frame through
    /// ``BackendFeatures/GeometricEffects`` with no re-layout and no re-render --
    /// so a scaled view's text is scaled too, as Flip's `scale: true` draws it.
    ///
    /// `isSource: false` makes this view follow the source's frame instead of
    /// its own: it is drawn mapped onto the source, and when the source moves
    /// inside an animation it follows with the same animation.
    ///
    /// The frame compared is the view's place in its window, so a view inside
    /// a ScrollView that scrolled between two animated updates flies by the
    /// distance scrolled.
    ///
    /// 每當此 view 的 frame 在 `withAnimation` 內改變時，從「同一個 `id` 的 view 原本所在之處」動畫到此
    /// view 現在的位置——SwiftUI 對 GSAP Flip 外掛所做之事的名稱。**移動**的 view(重排的 `ForEach`
    /// 項目、換了堆疊的方塊)從自己的舊 frame 飛過來;**取代**另一個同 id view 的 view(縮圖變成詳細
    /// 畫面)從對方原本的 frame 飛過來。不在動畫中時，view 直接到新位置。
    ///
    /// **是繪製，不是排版，Flip 也是如此。** 版面立刻跳到終點;動畫的是平移，以及(含 `.size` 時)繞
    /// `anchor` 的縮放，每一幀經由 ``BackendFeatures/GeometricEffects`` 設到 widget 上，不重新排版、不
    /// 重新算繪——因此被縮放的 view 裡的文字也一起縮放，與 Flip 的 `scale: true` 相同。
    ///
    /// `isSource: false` 讓此 view 跟隨來源的 frame 而非自己的：它被畫成對齊來源，來源在動畫中移動時
    /// 以同一個動畫跟過去。比較的是 view 在視窗中的位置，所以 ScrollView 裡的 view 若在兩次動畫更新
    /// 之間被捲動過，會飛過捲動的那段距離。
    ///
    /// **What triggers a flip is an assignment that cannot tween.** An `Int`,
    /// `Double` or `Color` assigned inside `withAnimation` is an
    /// ``AnimatableValue`` and tweens through every value in between, so a tab
    /// index set from 0 to 2 passes through tab 1 and the selection is
    /// re-laid-out at each step, with no flip; P100 measured exactly that.
    /// Hold a selection in a `String` or an enum, as SwiftUI code usually does.
    ///
    /// **觸發 flip 的是一次無法補間的賦值。** 在 `withAnimation` 內賦值的 `Int`、`Double` 或 `Color`
    /// 是 ``AnimatableValue``,會補間經過中間的每一個值，所以從 0 設到 2 的分頁索引會經過分頁 1,選取
    /// 在每一步都重新排版、沒有 flip;P100 量到的正是如此。選取請用 `String` 或 enum 保存，SwiftUI 程式
    /// 通常也是這麼寫的。
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        MatchedGeometryEffectModifier(
            body: TupleView1(self),
            key: MatchedGeometryKey(namespace: namespace, id: AnyHashable(id)),
            properties: properties,
            anchor: anchor,
            isSource: isSource
        )
    }
}

struct MatchedGeometryKey: Hashable {
    var namespace: Namespace.ID
    var id: AnyHashable
}

/// The translation and scale that draw a view's layout frame somewhere else.
/// Pure, so the arithmetic is tested without a backend.
/// 把一個 view 的版面 frame 畫到別處的平移與縮放。純函式，因此不需要 backend 就能測試。
struct FlipComponents: Equatable {
    var translation = SIMD2<Double>(0, 0)
    var scale = SIMD2<Double>(1, 1)

    static let identity = FlipComponents()

    /// The components that draw `frame` over `target`.
    ///
    /// With `.position`, the anchor points coincide: t = T.o - F.o + a(T.s - F.s).
    /// With `.size`, the scale is T.s / F.s about the anchor, and with both the
    /// whole frame lands on the target whatever the anchor is.
    ///
    /// 把 `frame` 畫在 `target` 上的分量。含 `.position` 時兩個錨點重合:t = T.o - F.o + a(T.s - F.s)。
    /// 含 `.size` 時縮放為繞錨點的 T.s / F.s;兩者都含時，不論錨點為何，整個 frame 都落在目標上。
    static func mapping(
        _ frame: Path.Rect,
        onto target: Path.Rect,
        properties: MatchedGeometryProperties,
        anchor: UnitPoint
    ) -> FlipComponents {
        var components = FlipComponents()
        if properties.contains(.size) {
            components.scale = SIMD2(
                frame.size.x > 0 ? target.size.x / frame.size.x : 1,
                frame.size.y > 0 ? target.size.y / frame.size.y : 1
            )
        }
        if properties.contains(.position) {
            let a = SIMD2(anchor.x, anchor.y)
            components.translation = target.origin - frame.origin + a * (target.size - frame.size)
        }
        return components
    }

    func interpolated(to end: FlipComponents, progress: Double) -> FlipComponents {
        FlipComponents(
            translation: translation + (end.translation - translation) * progress,
            scale: scale + (end.scale - scale) * progress
        )
    }

    /// Where `frame` is drawn under these components: the inverse of ``mapping``.
    /// 在這些分量之下 `frame` 被畫在哪裡:``mapping`` 的反函式。
    func visualFrame(of frame: Path.Rect, anchor: UnitPoint) -> Path.Rect {
        let a = SIMD2(anchor.x, anchor.y)
        return Path.Rect(
            origin: frame.origin + a * frame.size * (SIMD2(1, 1) - scale) + translation,
            size: frame.size * scale
        )
    }

    func effect(anchor: UnitPoint) -> GeometricEffect {
        GeometricEffect(translation: translation, scale: scale, anchor: anchor)
    }
}

extension Path.Rect {
    /// Within half a point on every edge: a frame measured twice in whole points
    /// is the same frame.
    /// 每一邊都在半點之內：以整數點量兩次的 frame 是同一個 frame。
    func isClose(to other: Path.Rect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5 && abs(origin.y - other.origin.y) < 0.5
            && abs(size.x - other.size.x) < 0.5 && abs(size.y - other.size.y) < 0.5
    }
}

/// Every matched id's last known frame and the view that holds it.
///
/// Keyed by id, not by view: a reordered `ForEach` may hand an item to a
/// different node, and the frame an item flies from belongs to the item.
///
/// 每個對齊 id 最後已知的 frame,以及持有它的 view。以 id 而非 view 為索引：重排的 `ForEach` 可能把
/// 某個項目交給另一個節點，而項目飛出的起點屬於項目本身。
@MainActor
final class MatchedGeometryRegistry {
    static let shared = MatchedGeometryRegistry()

    final class Entry {
        weak var holder: FlipNode?
        /// The holder's layout frame, or where the last holder was drawn when it let go.
        /// 持有者的版面 frame,或上一個持有者放手時被畫在的位置。
        var frame: Path.Rect?
        var followers: [WeakFlipNode] = []
    }

    struct WeakFlipNode {
        weak var node: FlipNode?
    }

    private(set) var entries: [MatchedGeometryKey: Entry] = [:]

    func entry(_ key: MatchedGeometryKey) -> Entry {
        if let entry = entries[key] {
            return entry
        }
        let entry = Entry()
        entries[key] = entry
        return entry
    }

    func existing(_ key: MatchedGeometryKey) -> Entry? {
        entries[key]
    }
}

/// One `matchedGeometryEffect` view's state, kept across updates by its node.
/// 一個 `matchedGeometryEffect` view 的狀態，由其節點跨更新保留。
@MainActor
final class FlipNode {
    var key: MatchedGeometryKey?
    var properties = MatchedGeometryProperties.frame
    var anchor = UnitPoint.center
    var isSource = true

    /// The layout frame in window coordinates, as last measured.
    /// 最後一次量到的版面 frame(視窗座標)。
    private(set) var layoutFrame: Path.Rect?
    private(set) var current = FlipComponents.identity
    private(set) var isAnimating = false
    private let tweenKey = UUID()
    private let registry: MatchedGeometryRegistry

    /// Sets the drawn components on the widget; nil until committed, and nil on
    /// a backend with no geometric effects.
    /// 把繪製用的分量設到 widget 上;commit 之前為 nil,沒有幾何效果的 backend 上也為 nil。
    var draw: ((FlipComponents, UnitPoint) -> Void)?

    init(registry: MatchedGeometryRegistry = .shared) {
        self.registry = registry
    }

    var visualFrame: Path.Rect? {
        layoutFrame.map { current.visualFrame(of: $0, anchor: anchor) }
    }

    /// Takes the frame measured after a commit, and flies there if `transaction`
    /// says the change was animated.
    /// 接收 commit 之後量到的 frame;若 `transaction` 表示這次改變帶動畫，就飛過去。
    func settle(frame: Path.Rect, transaction: LayoutTransactionState.Pending?) {
        guard let key else { return }
        if isSource {
            settleSource(key: key, frame: frame, transaction: transaction)
        } else {
            settleFollower(key: key, frame: frame, transaction: transaction)
        }
    }

    /// Called before `key` changes, so the id it held keeps where it was drawn.
    /// 在 `key` 改變之前呼叫，讓它原本持有的 id 記住自己被畫在哪裡。
    func release(_ oldKey: MatchedGeometryKey) {
        guard let entry = registry.existing(oldKey), entry.holder === self else { return }
        entry.frame = visualFrame ?? entry.frame
        entry.holder = nil
    }

    private func settleSource(
        key: MatchedGeometryKey,
        frame: Path.Rect,
        transaction: LayoutTransactionState.Pending?
    ) {
        let entry = registry.entry(key)
        let from: Path.Rect?
        if entry.holder === self {
            // Its own layout did not move: an update that redraws it mid-flight
            // (a state change, a relayout) must leave the flip running rather
            // than start another from where it is drawn.
            // 它自己的版面沒有移動：在飛行途中重畫它的更新(狀態改變、重新排版)必須讓 flip 繼續，
            // 而不是從它被畫出的位置再開始一個。
            if let previous = layoutFrame, previous.isClose(to: frame) {
                layoutFrame = frame
                entry.frame = frame
                if !isAnimating {
                    show(.identity)
                }
                return
            }
            from = visualFrame
        } else if let other = entry.holder {
            from = other.visualFrame ?? entry.frame
        } else {
            from = entry.frame
        }
        layoutFrame = frame
        entry.holder = self
        entry.frame = frame

        if let from, !from.isClose(to: frame) {
            if let transaction {
                let start = FlipComponents.mapping(
                    frame, onto: from, properties: properties, anchor: anchor
                )
                animate(from: start, to: .identity, with: transaction)
            } else {
                stop(at: .identity)
            }
        } else if !isAnimating {
            show(.identity)
        }

        entry.followers.removeAll { $0.node == nil }
        for follower in entry.followers {
            follower.node?.retarget(transaction: transaction)
        }
    }

    private func settleFollower(
        key: MatchedGeometryKey,
        frame: Path.Rect,
        transaction: LayoutTransactionState.Pending?
    ) {
        layoutFrame = frame
        let entry = registry.entry(key)
        if !entry.followers.contains(where: { $0.node === self }) {
            entry.followers.append(MatchedGeometryRegistry.WeakFlipNode(node: self))
        }
        retarget(transaction: transaction)
    }

    /// A follower aims at the source's layout frame.
    /// 跟隨者瞄準來源的版面 frame。
    func retarget(transaction: LayoutTransactionState.Pending?) {
        guard !isSource, let key, let frame = layoutFrame else { return }
        let entry = registry.entry(key)
        guard let source = entry.holder?.layoutFrame ?? entry.frame else {
            stop(at: .identity)
            return
        }
        let target = FlipComponents.mapping(
            frame, onto: source, properties: properties, anchor: anchor
        )
        guard target != current else { return }
        if let transaction {
            animate(from: current, to: target, with: transaction)
        } else {
            stop(at: target)
        }
    }

    private func show(_ components: FlipComponents) {
        current = components
        draw?(components, anchor)
    }

    private func stop(at components: FlipComponents) {
        if isAnimating {
            AnimationDriver.shared.cancel(key: tweenKey)
            isAnimating = false
        }
        show(components)
    }

    private func animate(
        from start: FlipComponents,
        to end: FlipComponents,
        with transaction: LayoutTransactionState.Pending
    ) {
        show(start)
        isAnimating = true
        AnimationDriver.shared.start(
            key: tweenKey,
            animation: transaction.animation,
            group: transaction.group
        ) { [weak self] progress in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.show(start.interpolated(to: end, progress: progress))
                if progress >= 1 {
                    self.isAnimating = false
                }
            }
        }
    }
}

/// Where a matched view is drawn right now, for test apps that check a flip
/// mid-flight. Not SwiftUI API: SwiftUI has no way to ask.
/// 一個對齊 view 此刻被畫在哪裡，供在飛行途中檢查 flip 的測試 app 使用。不是 SwiftUI API:SwiftUI 沒有
/// 可以詢問的方式。
@_spi(Backends)
@MainActor
public enum MatchedGeometryDiagnostics {
    /// The holder's drawn frame in window coordinates, or nil when no view holds `id`.
    /// 持有者被畫出的 frame(視窗座標);沒有 view 持有 `id` 時為 nil。
    public static func drawnFrame(of id: some Hashable, in namespace: Namespace.ID) -> Path.Rect? {
        let key = MatchedGeometryKey(namespace: namespace, id: AnyHashable(id))
        return MatchedGeometryRegistry.shared.existing(key)?.holder?.visualFrame
    }

    /// The holder's layout frame: where it ends up.
    /// 持有者的版面 frame:它最終所在之處。
    public static func layoutFrame(of id: some Hashable, in namespace: Namespace.ID) -> Path.Rect? {
        let key = MatchedGeometryKey(namespace: namespace, id: AnyHashable(id))
        return MatchedGeometryRegistry.shared.existing(key)?.holder?.layoutFrame
    }

    /// The drawn frames of the `isSource: false` views following `id`.
    /// 跟隨 `id` 的 `isSource: false` view 被畫出的 frame。
    public static func followerFrames(of id: some Hashable, in namespace: Namespace.ID) -> [Path.Rect] {
        let key = MatchedGeometryKey(namespace: namespace, id: AnyHashable(id))
        let followers = MatchedGeometryRegistry.shared.existing(key)?.followers ?? []
        return followers.compactMap { $0.node?.visualFrame }
    }
}

final class MatchedGeometryChildren<Content: View>: ViewGraphNodeChildren, MatchedGeometryHosting {
    let children: TupleViewChildren1<Content>
    let node = FlipNode()
    /// The id the view was made with, until its first commit sets the node's.
    /// view 建立時的 id,直到第一次 commit 設定節點的 id 為止。
    private let initialKey: MatchedGeometryKey
    /// The geometric-effect container between the outer container and the
    /// child; nil on a backend without geometric effects.
    /// 外層容器與子元件之間的幾何效果容器;沒有幾何效果的 backend 上為 nil。
    var effect: AnyWidget?
    var retryScheduled = false

    init(_ children: TupleViewChildren1<Content>, key: MatchedGeometryKey) {
        self.children = children
        initialKey = key
    }

    var matchedKey: MatchedGeometryKey { node.key ?? initialKey }

    var widgets: [AnyWidget] { children.widgets }
    var erasedNodes: [ErasedViewGraphNode] { children.erasedNodes }
}

struct MatchedGeometryEffectModifier<Content: View>: TypeSafeView {
    var body: TupleView1<Content>
    var key: MatchedGeometryKey
    var properties: MatchedGeometryProperties
    var anchor: UnitPoint
    var isSource: Bool

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> MatchedGeometryChildren<Content> {
        MatchedGeometryChildren(
            TupleViewChildren1(
                body.view0,
                backend: backend,
                snapshots: snapshots,
                environment: environment
            ),
            key: key
        )
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: MatchedGeometryChildren<Content>
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    /// An outer container that is measured, holding the effect container that
    /// is moved. Measuring the moved widget would read the flip back on UIKit,
    /// whose `convert(_:to:)` applies the view's own transform.
    /// 外層容器負責被量測，裡面是被移動的效果容器。量測被移動的 widget 會在 UIKit 上把 flip 讀回來，
    /// 因為它的 `convert(_:to:)` 會套用 view 自己的 transform。
    func asWidget<Backend: BaseAppBackend>(
        _ children: MatchedGeometryChildren<Content>,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.children.child0.widget.into()
        guard let effect = GeometricEffectWidgets.wrap(child, backend: backend) else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support geometric effects; matchedGeometryEffect jumps"
            )
            return child
        }
        children.effect = AnyWidget(effect)
        let outer = backend.createContainer()
        backend.insert(effect, into: outer, at: 0)
        return outer
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: MatchedGeometryChildren<Content>,
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
        children: MatchedGeometryChildren<Content>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        let node = children.node
        if let effect = children.effect {
            let effectWidget: Backend.Widget = effect.into()
            backend.setSize(of: effectWidget, to: size.vector)
            backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
            let set = GeometricEffectWidgets.setter(for: effectWidget, backend: backend)
            let sizeVector = SIMD2(Double(size.vector.x), Double(size.vector.y))
            node.draw = { components, anchor in
                set?(components.effect(anchor: anchor).resolved(in: sizeVector))
            }
        }

        if let oldKey = node.key, oldKey != key {
            node.release(oldKey)
        }
        node.key = key
        node.properties = properties
        node.anchor = anchor
        node.isSource = isSource

        let transaction = LayoutTransaction.active
        let measured = AnyWidget(widget)
        let sizeVector = SIMD2(Double(size.vector.x), Double(size.vector.y))
        LayoutSettleQueue.enqueue(backend) { [weak children] in
            guard let children else { return }
            let origin = GeometryReader<EmptyView>.originInWindow(
                of: measured.into() as Backend.Widget,
                backend: backend
            )
            if let origin {
                children.node.settle(
                    frame: Path.Rect(
                        origin: SIMD2(Double(origin.x), Double(origin.y)),
                        size: sizeVector
                    ),
                    transaction: transaction
                )
            } else if !children.retryScheduled {
                // Not in a window yet: once more on the next turn, as GeometryReader does.
                // 還不在視窗裡：與 GeometryReader 一樣，在下一輪再問一次。
                children.retryScheduled = true
                backend.runInMainThread { [weak children] in
                    guard let children else { return }
                    children.retryScheduled = false
                    guard
                        let later = GeometryReader<EmptyView>.originInWindow(
                            of: measured.into() as Backend.Widget,
                            backend: backend
                        )
                    else { return }
                    children.node.settle(
                        frame: Path.Rect(
                            origin: SIMD2(Double(later.x), Double(later.y)),
                            size: sizeVector
                        ),
                        transaction: transaction
                    )
                }
            }
        }
    }
}

/// Opens a backend's ``BackendFeatures/GeometricEffects`` for the modifiers
/// that drive a geometric effect themselves rather than through a re-render.
/// 為「自行驅動幾何效果、而不是經由重新算繪」的 modifier 開啟 backend 的 ``BackendFeatures/GeometricEffects``。
@MainActor
enum GeometricEffectWidgets {
    static func wrap<Backend: BaseAppBackend>(
        _ child: Backend.Widget,
        backend: Backend
    ) -> Backend.Widget? {
        guard let capable = backend as? any BackendFeatures.GeometricEffects else { return nil }
        func open<B: BackendFeatures.GeometricEffects>(_ backend: B) -> Backend.Widget {
            backend.createGeometricEffectContainer(wrapping: child as! B.Widget) as! Backend.Widget
        }
        return open(capable)
    }

    static func setter<Backend: BaseAppBackend>(
        for widget: Backend.Widget,
        backend: Backend
    ) -> ((AffineTransform) -> Void)? {
        guard let capable = backend as? any BackendFeatures.GeometricEffects else { return nil }
        func open<B: BackendFeatures.GeometricEffects>(_ backend: B) -> (AffineTransform) -> Void {
            let widget = widget as! B.Widget
            return { backend.setGeometricEffect($0, ofWidget: widget) }
        }
        return open(capable)
    }
}
