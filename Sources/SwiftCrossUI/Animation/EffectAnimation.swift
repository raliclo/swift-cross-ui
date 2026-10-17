import Foundation

// The direct path for `.offset`, `.scaleEffect`, `.rotationEffect`, `.transformEffect`
// and `.opacity` (and the other compositing effects): when an update changes one of
// them under an animation, the modifier tweens its widget from what is drawn to the
// new value on the frame clock, the way `matchedGeometryEffect` flies a frame --
// no body re-evaluation and no re-layout per frame.
//
// **When it applies.** An update runs under an animation when
//   - a `withAnimation` assignment that cannot tween (a `Bool`, an enum, an array)
//     armed a ``LayoutTransaction`` -- SwiftUI's `withAnimation { isOn.toggle() }`
//     with `.offset(x: isOn ? 100 : 0)`; or
//   - an `.animation(_:value:)` above the modifier saw its value change.
// A tweenable `@State` (a `Double`) assigned inside `withAnimation` keeps its own
// tween: the state passes through every intermediate value, which GSAP's model and
// P66, P96-P99 rely on, and the body is re-evaluated each frame as before. That
// path cannot be made direct without knowing which views read the state for
// something other than an effect, which the view graph does not record.
//
// **What the tween interpolates.** The modifier's own value, from the one drawn to
// the new one -- SwiftUI's semantics, where an offset computed from a state moves
// in a straight line between the two renders whatever function produced it. A view
// that should follow a curve gives that coordinate its own animation, e.g.
// `.offset(y: y).animation(.timingCurve(curve, duration: 3), value: isRunning)`.
//
// 直接路徑：`.offset`、`.scaleEffect`、`.rotationEffect`、`.transformEffect` 與 `.opacity`(以及其他合成
// 效果)在一次「帶動畫」的更新中改變時，modifier 在 frame clock 上把它的 widget 從目前畫出的值補間到新值，
// 與 `matchedGeometryEffect` 飛動 frame 的方式相同——每一幀不重算 body、不重排版面。
//
// **何時適用。** 一次更新帶動畫，當:無法補間的 `withAnimation` 賦值(Bool、enum、陣列)上膛了
// ``LayoutTransaction``——SwiftUI 的 `withAnimation { isOn.toggle() }` 配 `.offset(x: isOn ? 100 : 0)`;
// 或 modifier 上方的 `.animation(_:value:)` 看到它的值改變。在 `withAnimation` 內被賦值、可補間的
// `@State`(Double)維持自己的補間：狀態會經過每一個中間值(GSAP 的模型，P66、P96-P99 依賴它),body 照舊
// 每幀重算。那條路徑要變成直接路徑，必須知道哪些 view 讀這個狀態是為了效果以外的事，而 view graph 沒有記錄。
//
// **補間的對象。** modifier 自己的值，從畫出的值到新值——SwiftUI 的語意：由狀態算出的 offset,不論由
// 什麼函數產生，都在兩次算繪之間走直線。要沿曲線走的 view,為那個座標指定自己的動畫，例如
// `.offset(y: y).animation(.timingCurve(curve, duration: 3), value: isRunning)`。

/// The animation an effect change in the current update is drawn with.
/// 目前這次更新中，效果改變所用的動畫。
struct EffectTransaction: Sendable {
    enum Token: Equatable {
        case layout(Int)
        case value(Int)
    }

    /// `nil` turns animation off for the change (`.animation(nil, value:)`).
    /// `nil` 表示這次改變不帶動畫(`.animation(nil, value:)`)。
    var animation: Animation?
    var group: AnimationGroup?
    /// One change, so a modifier starts at most one tween for it however many
    /// updates the armed window covers.
    /// 一次改變；不論上膛的時間窗涵蓋幾次更新，一個 modifier 對它最多啟動一個補間。
    var token: Token

    nonisolated(unsafe) private static var lastValueToken = 0

    static func nextValueToken() -> Token {
        lastValueToken += 1
        return .value(lastValueToken)
    }

    /// The transaction for an effect committed with `environment`: an
    /// `.animation(_:value:)` above it, else the `withAnimation` the update runs under.
    /// 以 `environment` commit 的效果所用的 transaction:上方的 `.animation(_:value:)`,否則為這次更新所在的
    /// `withAnimation`。
    static func current(in environment: EnvironmentValues) -> EffectTransaction? {
        if let override = environment.effectAnimationOverride {
            return override
        }
        // The armed window as well as the update it began: on iOS the tiles of
        // P96 were committed by an update that did not start in
        // observeAsUIUpdater (active nil, 14 ms after arming), so the change drew
        // without animation. The token keeps it to one tween per modifier.
        // 也看上膛的時間窗，而不只是它所開始的那次更新:iOS 上 P96 的格子是由一次不是在 observeAsUIUpdater
        // 中開始的更新 commit 的(active 為 nil,上膛後 14 毫秒),改變因此沒有動畫。token 讓每個 modifier 只補間一次。
        guard
            let active = LayoutTransaction.active
                ?? LayoutTransaction.state.current(now: LayoutTransaction.now)
        else { return nil }
        return EffectTransaction(
            animation: active.animation,
            group: active.group,
            token: .layout(active.token)
        )
    }
}

/// An effect value the direct path can interpolate.
/// 直接路徑可以插值的效果值。
protocol InterpolatableEffect: Equatable {
    static func interpolated(from start: Self, to end: Self, progress: Double) -> Self
}

extension GeometricEffect: InterpolatableEffect {
    /// Component by component: translation, scale, rotation (in radians, so a turn
    /// from 0 to 360 degrees goes all the way round), anchor and the free matrix.
    /// 逐分量：平移、縮放、旋轉(以弧度，所以 0 到 360 度會轉完整一圈)、錨點與任意矩陣。
    static func interpolated(
        from start: GeometricEffect,
        to end: GeometricEffect,
        progress: Double
    ) -> GeometricEffect {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }
        return GeometricEffect(
            translation: start.translation + (end.translation - start.translation) * progress,
            scale: start.scale + (end.scale - start.scale) * progress,
            rotation: Angle(radians: mix(start.rotation.radians, end.rotation.radians)),
            anchor: UnitPoint(x: mix(start.anchor.x, end.anchor.x), y: mix(start.anchor.y, end.anchor.y)),
            matrix: AffineTransform(
                linearTransform: start.matrix.linearTransform
                    + (end.matrix.linearTransform - start.matrix.linearTransform) * progress,
                translation: start.matrix.translation
                    + (end.matrix.translation - start.matrix.translation) * progress
            )
        )
    }
}

extension VisualEffect: InterpolatableEffect {
    static func interpolated(
        from start: VisualEffect,
        to end: VisualEffect,
        progress: Double
    ) -> VisualEffect {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * progress }
        var effect = end
        effect.opacity = mix(start.opacity, end.opacity)
        effect.blurRadius = mix(start.blurRadius, end.blurRadius)
        effect.saturation = mix(start.saturation, end.saturation)
        effect.brightness = mix(start.brightness, end.brightness)
        effect.contrast = mix(start.contrast, end.contrast)
        effect.grayscale = mix(start.grayscale, end.grayscale)
        effect.hueRotation = Angle(radians: mix(start.hueRotation.radians, end.hueRotation.radians))
        return effect
    }
}

/// One effect modifier's drawn value and the tween that moves it.
///
/// `commit` is called on every update with the modifier's value; it draws the
/// value at once, or -- under an animation, for a changed value -- starts a tween
/// from what is drawn, which then draws every frame through `draw` until it ends.
/// A commit that brings the same value while the tween runs leaves it running.
///
/// 一個效果 modifier 畫出的值，以及移動它的補間。每次更新都以 modifier 的值呼叫 `commit`:立刻畫出，或——在
/// 動畫下、值改變時——從目前畫出的值啟動補間，之後每一幀經由 `draw` 畫出，直到結束。補間進行中、帶著相同值的
/// commit 不會打斷它。
@MainActor
final class EffectTween<Value: InterpolatableEffect> {
    private(set) var drawn: Value?
    private(set) var target: Value?
    private(set) var isAnimating = false
    private var usedToken: EffectTransaction.Token?
    private let key = UUID()

    /// Sets the value on the widget; replaced on every commit, so it carries the
    /// latest size.
    /// 把值設到 widget 上;每次 commit 都會替換，因此帶著最新的尺寸。
    var draw: ((Value) -> Void)?
    /// Reported to ``EffectAnimationDiagnostics`` when set.
    /// 設定時回報給 ``EffectAnimationDiagnostics``。
    var diagnosticsLabel: String?

    init() {}

    deinit {
        // A repeatForever tween would otherwise keep the frame clock running for a
        // view that is gone. / 否則 repeatForever 的補間會為一個已消失的 view 讓 frame clock 一直跑。
        AnimationDriver.shared.cancel(key: key)
    }

    func commit(_ value: Value, transaction: EffectTransaction?) {
        let previousTarget = target
        target = value
        guard let drawn else {
            // First appearance: drawn as it is (SwiftUI does not animate an
            // inserted view's effects from identity).
            // 首次出現：照原樣畫出(SwiftUI 不會讓新插入 view 的效果從 identity 動起來)。
            show(value)
            return
        }
        if value == previousTarget {
            // Unchanged. A running tween keeps going (its next frame picks up a new
            // size); otherwise redraw, as the size may have changed.
            // 未改變。進行中的補間繼續(下一幀會用新的尺寸);否則重畫，因為尺寸可能變了。
            if !isAnimating {
                show(value)
            }
            return
        }
        if let transaction, let animation = transaction.animation,
            transaction.token != usedToken, drawn != value
        {
            usedToken = transaction.token
            animate(from: drawn, to: value, animation: animation, group: transaction.group)
        } else {
            stop(at: value)
        }
    }

    private func show(_ value: Value) {
        drawn = value
        draw?(value)
        if let diagnosticsLabel {
            EffectAnimationDiagnostics.record(label: diagnosticsLabel, value: value)
        }
    }

    private func stop(at value: Value) {
        if isAnimating {
            isAnimating = false
            AnimationDriver.shared.cancel(key: key)
        }
        show(value)
    }

    private func animate(
        from start: Value,
        to end: Value,
        animation: Animation,
        group: AnimationGroup?
    ) {
        isAnimating = true
        show(start)
        AnimationDriver.shared.start(
            key: key,
            animation: animation,
            group: group,
            apply: { [weak self] progress in
                MainActor.assumeIsolated {
                    self?.show(Value.interpolated(from: start, to: end, progress: progress))
                }
            },
            finish: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isAnimating = false
                }
            }
        )
    }
}

/// What the direct path last drew for each labelled modifier, for test apps
/// (P96) to compare against the expected value in the same frame.
/// 直接路徑為每個加了標籤的 modifier 最後畫出的值，供測試 app(P96)與同一幀的預期值比較。
@_spi(Backends)
@MainActor
public enum EffectAnimationDiagnostics {
    public private(set) static var geometric: [String: GeometricEffect] = [:]
    public private(set) static var visual: [String: VisualEffect] = [:]
    /// Draws per label, so an app can count frames.
    /// 每個標籤的繪製次數，讓 app 能數幀。
    public private(set) static var draws: [String: Int] = [:]

    static func record<Value>(label: String, value: Value) {
        draws[label, default: 0] += 1
        if let value = value as? GeometricEffect {
            geometric[label] = value
        } else if let value = value as? VisualEffect {
            visual[label] = value
        }
    }
}

extension View {
    /// Labels the effect modifiers inside this view for ``EffectAnimationDiagnostics``.
    /// 為此 view 之內的效果 modifier 加上標籤，供 ``EffectAnimationDiagnostics`` 使用。
    @_spi(Backends)
    public func _effectDiagnosticsLabel(_ label: String) -> some View {
        environment(\.effectDiagnosticsLabel, label)
    }

    /// Animates the changes inside this view with `animation` whenever `value`
    /// changes -- SwiftUI's `animation(_:value:)`.
    ///
    /// Effect modifiers inside (`offset`, `scaleEffect`, `rotationEffect`,
    /// `transformEffect`, `opacity`, `blur` ...) tween on the direct path; this
    /// takes precedence over an enclosing `withAnimation` for the views inside it,
    /// and `nil` makes them change at once.
    ///
    /// 每當 `value` 改變，就以 `animation` 為此 view 內部的改變加上動畫——SwiftUI 的 `animation(_:value:)`。
    /// 內部的效果 modifier(`offset`、`scaleEffect`、`rotationEffect`、`transformEffect`、`opacity`、
    /// `blur`……)走直接路徑補間;對它內部的 view 而言，這優先於外層的 `withAnimation`,`nil` 則讓它們立刻改變。
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        AnimationValueModifier(body: TupleView1(self), animation: animation, value: value)
    }
}

/// The children of an effect modifier, with the modifier's tween.
/// 效果 modifier 的 children,帶著該 modifier 的補間。
final class EffectModifierChildren<Content: View, Value: InterpolatableEffect>:
    TupleViewChildren1<Content>
{
    /// Made at the first commit, on the main actor.
    /// 在第一次 commit 時(於 main actor 上)建立。
    var tween: EffectTween<Value>?
}

final class AnimationValueChildren<Content: View, Value: Equatable>: TupleViewChildren1<Content> {
    /// The value at the last commit; `nil` before the first.
    /// 上次 commit 時的值;第一次之前為 `nil`。
    var committedValue: Value?
    /// The token for the change being laid out, shared by every layout pass of
    /// one update.
    /// 正在排版的這次改變的 token,同一次更新的每一趟排版共用。
    var pendingToken: EffectTransaction.Token?
}

struct AnimationValueModifier<Content: View, Value: Equatable>: TypeSafeView {
    var body: TupleView1<Content>
    var animation: Animation?
    var value: Value

    typealias Children = AnimationValueChildren<Content, Value>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(body.view0, backend: backend, snapshots: snapshots, environment: environment)
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        body.asWidget(children, backend: backend)
    }

    /// The content's environment: carrying this modifier's animation when the
    /// value differs from the one last committed.
    /// 內容的環境：當值與上次 commit 的不同時，帶著這個 modifier 的動畫。
    private func contentEnvironment(
        _ environment: EnvironmentValues,
        children: Children
    ) -> EnvironmentValues {
        guard let committed = children.committedValue, committed != value else {
            return environment
        }
        let token = children.pendingToken ?? EffectTransaction.nextValueToken()
        children.pendingToken = token
        var environment = environment
        environment.effectAnimationOverride = EffectTransaction(
            animation: animation,
            group: nil,
            token: token
        )
        return environment
    }

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
            environment: contentEnvironment(environment, children: children),
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
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: contentEnvironment(environment, children: children),
            backend: backend
        )
        children.committedValue = value
        children.pendingToken = nil
    }
}
