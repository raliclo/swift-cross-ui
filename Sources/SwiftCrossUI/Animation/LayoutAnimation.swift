import Foundation

// Layout and drawn state under an animation: a `.frame` size, a `.padding`, a
// `Color` view's colour and a `Shape`'s fill tween when they change inside
// `.animation(_:value:)` or a `withAnimation` assignment that cannot tween (the
// same transactions the effect modifiers read, see EffectAnimation.swift).
//
// **How a frame is drawn.** The parameter keeps the value it last drew and, under
// an animation, a tween from there to the new one. A layout parameter re-lays out
// through the node that holds it on every frame -- `onResize`, the path a child
// that changed size already takes -- so the body is not evaluated again and only
// the ancestors whose size changes are laid out. A colour has nothing to lay out
// and is set on the widget directly.
//
// SwiftUI's semantics: the parameter moves from what is drawn to the new value,
// so a change in mid-flight continues from where it is.
//
// 動畫中的版面與繪製狀態:`.frame` 的尺寸、`.padding`、`Color` view 的顏色與 `Shape` 的填色，在
// `.animation(_:value:)` 或「無法補間的 `withAnimation` 賦值」之內改變時會補間(與效果 modifier 讀的是同一組
// transaction,見 EffectAnimation.swift)。
//
// **每一幀怎麼畫。** 參數保存它上次畫出的值，在動畫中則有一個從那裡到新值的補間。版面參數每一幀經由持有它的
// 節點重新排版——`onResize`,也就是子節點改變尺寸時本來就走的路——所以不會再求值 body,只有尺寸改變的祖先會
// 重新排版。顏色沒有東西要排版，直接設到 widget 上。
//
// SwiftUI 的語意：參數從畫出的值移到新值，所以飛行途中的改變會從它當下所在之處繼續。

/// One animatable parameter of a view: what it last drew and the tween that moves it.
/// 一個 view 的可動畫參數：它上次畫出的值，以及移動它的補間。
@MainActor
final class ParameterTween<Value: AnimatableValue & Equatable> {
    private(set) var drawn: Value?
    private var target: Value?
    private(set) var isAnimating = false
    private var usedToken: EffectTransaction.Token?
    /// True while the tween is being registered: a backend without a frame clock
    /// applies the end at once, inside a layout pass that must not start another.
    /// 註冊補間期間為 true:沒有 frame clock 的 backend 會立刻套用終值，而那發生在一趟不可以再開始另一趟的排版裡。
    private var starting = false
    private let key = UUID()

    /// Runs after each frame has moved ``drawn``: a re-layout through the node
    /// that holds the parameter, or a redraw. Replaced on every resolve, so it
    /// carries the latest widget and environment.
    /// 每一幀移動 ``drawn`` 之後執行：經由持有參數的節點重新排版，或重畫。每次 resolve 都會替換，因此帶著最新的
    /// widget 與環境。
    var onFrame: (() -> Void)?

    init() {}

    deinit {
        AnimationDriver.shared.cancel(key: key)
    }

    /// The value to lay out or draw now, for a view whose parameter is `value`.
    ///
    /// Called by every layout pass and by the commit; a value that did not change
    /// keeps a running tween where it is.
    ///
    /// 對參數為 `value` 的 view,現在要排版或繪製的值。每一趟排版與 commit 都會呼叫;沒有改變的值讓進行中的補間
    /// 停在它當下所在之處。
    func resolve(_ value: Value, transaction: EffectTransaction?) -> Value {
        let previousTarget = target
        target = value
        guard let drawn else {
            // First appearance: drawn as it is. / 首次出現：照原樣畫出。
            drawn = value
            return value
        }
        if value == previousTarget {
            return drawn
        }
        if let transaction, let animation = transaction.animation,
            transaction.token != usedToken, drawn != value
        {
            usedToken = transaction.token
            animate(from: drawn, to: value, animation: animation, group: transaction.group)
            return self.drawn ?? value
        }
        stop(at: value)
        return value
    }

    /// Forgets the drawn value: the parameter went away (a frame width set back to nil).
    /// 忘掉畫出的值：參數不見了(frame 的寬度改回 nil)。
    func reset() {
        stop(at: nil)
        target = nil
    }

    private func stop(at value: Value?) {
        if isAnimating {
            isAnimating = false
            AnimationDriver.shared.cancel(key: key)
        }
        drawn = value
    }

    private func animate(
        from start: Value,
        to end: Value,
        animation: Animation,
        group: AnimationGroup?
    ) {
        isAnimating = true
        starting = true
        defer { starting = false }
        AnimationDriver.shared.start(
            key: key,
            animation: animation,
            group: group,
            apply: { [weak self] progress in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.drawn = Value.interpolated(from: start, to: end, progress: progress)
                    if !self.starting {
                        self.onFrame?()
                    }
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

/// The children of a layout modifier, with a tween per animatable parameter.
/// 版面 modifier 的 children,每個可動畫參數一個補間。
final class AnimatedLayoutChildren<Content: View>: TupleViewChildren1<Content> {
    /// Made on first use, on the main actor. / 第一次使用時(於 main actor 上)建立。
    var tweens: [Int: ParameterTween<Double>] = [:]

    /// `value` as it is to be laid out now: on its way from the drawn value when
    /// it changed under an animation. `nil` and infinite values pass through, as
    /// there is nothing between them and a number.
    ///
    /// `value` 現在要排版的樣子：若它在動畫中改變，則正從畫出的值走向它。`nil` 與無限大照原樣通過，因為它們與一個
    /// 數字之間沒有中間值。
    @MainActor
    func animated(_ value: Double?, slot: Int, environment: EnvironmentValues) -> Double? {
        guard let value, value.isFinite else {
            tweens[slot]?.reset()
            return value
        }
        let tween: ParameterTween<Double>
        if let existing = tweens[slot] {
            tween = existing
        } else {
            tween = ParameterTween()
            tweens[slot] = tween
        }
        let relayout = environment.onResize
        tween.onFrame = { relayout(.zero) }
        return tween.resolve(value, transaction: EffectTransaction.current(in: environment))
    }
}

/// A `Color` view's drawn colour. / `Color` view 畫出的顏色。
final class ColorViewStorage: ViewGraphNodeChildren {
    let widgets: [AnyWidget] = []
    let erasedNodes: [ErasedViewGraphNode] = []
    /// Made at the first commit, on the main actor. / 在第一次 commit 時(於 main actor 上)建立。
    var fill: ParameterTween<Color>?
}

extension Color {
    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        ColorViewStorage()
    }

    /// Resolved before it tweens, so a system colour has components to move
    /// between (`Color.interpolated` alone would jump for one).
    /// 補間之前先 resolve,讓系統色有分量可以在其間移動(只靠 `Color.interpolated` 時，系統色會直接跳過去)。
    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        guard let storage = children as? ColorViewStorage else {
            commit(widget, layout: layout, environment: environment, backend: backend)
            return
        }
        let fill = storage.fill ?? ParameterTween<Color>()
        storage.fill = fill
        fill.onFrame = { [weak fill] in
            guard let drawn = fill?.drawn else { return }
            drawn.commit(widget, layout: layout, environment: environment, backend: backend)
            LayoutAnimationDiagnostics.record(environment, "color", color: drawn)
        }
        let shown = fill.resolve(
            Color(resolve(in: environment)),
            transaction: EffectTransaction.current(in: environment)
        )
        shown.commit(widget, layout: layout, environment: environment, backend: backend)
        LayoutAnimationDiagnostics.record(environment, "color", color: shown)
    }
}

/// What the layout modifiers and colours under a ``View/_effectDiagnosticsLabel(_:)``
/// set on their widgets, with the time, for test apps (P104) to compare a frame
/// in flight against the curve. Keyed by `"label/kind"`, kind being `frame`,
/// `padding`, `color` or `fill`, as one label covers everything inside it.
/// 在 ``View/_effectDiagnosticsLabel(_:)`` 之下的版面 modifier 與顏色設到 widget 上的值及時間，供測試 app(P104)
/// 把飛行中的一幀與曲線比較。以 `"label/kind"` 為鍵,kind 為 `frame`、`padding`、`color` 或 `fill`,因為一個標籤
/// 涵蓋它之內的一切。
@_spi(Backends)
@MainActor
public enum LayoutAnimationDiagnostics {
    public struct Sample: Sendable {
        public var time: Double
        /// Width and height for a size; red, green, blue and opacity for a colour.
        /// 尺寸為寬與高;顏色為紅、綠、藍與不透明度。
        public var values: [Double]
    }

    public private(set) static var samples: [String: [Sample]] = [:]

    static func record(_ environment: EnvironmentValues, _ kind: String, size: ViewSize) {
        guard let label = environment.effectDiagnosticsLabel else { return }
        append("\(label)/\(kind)", [size.width, size.height])
    }

    static func record(_ environment: EnvironmentValues, _ kind: String, color: Color) {
        guard let label = environment.effectDiagnosticsLabel else { return }
        let resolved = color.resolve(in: environment)
        append(
            "\(label)/\(kind)",
            [Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity)]
        )
    }

    /// Any list of values, for kinds that are neither a size nor one colour
    /// (a gradient's locations and colour components).
    /// 任意的數值清單，供既不是尺寸也不是單一顏色的種類使用(漸層的位置與顏色分量)。
    static func record(_ environment: EnvironmentValues, _ kind: String, values: [Double]) {
        guard let label = environment.effectDiagnosticsLabel else { return }
        append("\(label)/\(kind)", values)
    }

    private static func append(_ key: String, _ values: [Double]) {
        let time = ProcessInfo.processInfo.systemUptime
        if let last = samples[key]?.last, last.values == values {
            return
        }
        samples[key, default: []].append(Sample(time: time, values: values))
    }

    public static func clear() {
        samples = [:]
    }
}
