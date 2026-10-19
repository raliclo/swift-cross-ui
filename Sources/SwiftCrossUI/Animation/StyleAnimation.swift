import Foundation

// Text colours and gradients under an animation: `.foregroundColor` /
// `.foregroundStyle` on `Text`, and `LinearGradient`, `RadialGradient` and
// `AngularGradient` (stop colours and locations, points, radii, angles) tween
// when they change inside `.animation(_:value:)` or a `withAnimation`
// assignment that cannot tween -- the transactions EffectAnimation.swift and
// LayoutAnimation.swift read.
//
// **How a frame is drawn.** Each view keeps a ``ParameterTween`` of what it
// draws and, every frame, hands the backend the value in between through the
// call it already makes: `updateTextView` with the colour in the environment
// for `Text` (a colour does not change a text's size, so nothing is laid out),
// `update…GradientWidget` with a gradient in between. Colours are resolved
// before they tween, so a system colour has components to move between.
//
// **Gradients with different stops.** With the same number of stops each stop
// moves to its partner (colour and location). Otherwise both gradients are
// sampled at the union of their locations and each sample moves from one
// colour to the other, so the drawn gradient at each end is exactly the
// gradient given.
//
// 動畫中的文字顏色與漸層:`Text` 上的 `.foregroundColor` / `.foregroundStyle`,以及 `LinearGradient`、
// `RadialGradient` 與 `AngularGradient`(色標的顏色與位置、點、半徑、角度),在 `.animation(_:value:)` 或無法補間的
// `withAnimation` 賦值之內改變時會補間——即 EffectAnimation.swift 與 LayoutAnimation.swift 所讀的 transaction。
//
// **每一幀怎麼畫。** 每個 view 保存它所畫內容的 ``ParameterTween``,每一幀經由它本來就會做的呼叫把中間值交給
// backend:`Text` 以環境中的顏色呼叫 `updateTextView`(顏色不改變文字尺寸，所以不排版),漸層以中間的漸層呼叫
// `update…GradientWidget`。顏色在補間前先 resolve,讓系統色有分量可以在其間移動。
//
// **色標數不同的漸層。** 色標數相同時，每個色標移向它的配對(顏色與位置)。否則兩個漸層都在雙方位置的聯集上取樣，
// 每個樣本從一個顏色移到另一個，所以兩端畫出的漸層恰好就是給定的漸層。

extension Gradient: AnimatableValue {
    public static func interpolated(from start: Gradient, to end: Gradient, progress: Double) -> Gradient {
        var gradient = end
        if start.stops.count == end.stops.count {
            gradient.stops = zip(start.stops, end.stops).map { a, b in
                Stop(
                    color: Color.interpolated(from: a.color, to: b.color, progress: progress),
                    location: a.location + (b.location - a.location) * progress
                )
            }
            return gradient
        }
        let locations = Array(Set(start.stops.map(\.location) + end.stops.map(\.location))).sorted()
        gradient.stops = locations.map { location in
            Stop(
                color: Color.interpolated(
                    from: start.color(at: location), to: end.color(at: location), progress: progress
                ),
                location: location
            )
        }
        return gradient
    }

    /// The colour drawn at `location`: between the stops around it, or the
    /// nearest end stop's outside them.
    /// 在 `location` 畫出的顏色：介於它兩側的色標之間，或在色標範圍外取最近端點色標的顏色。
    func color(at location: Double) -> Color {
        guard let first = stops.first, let last = stops.last else { return .black }
        if location <= first.location { return first.color }
        if location >= last.location { return last.color }
        for (a, b) in zip(stops, stops.dropFirst()) where location <= b.location {
            let span = b.location - a.location
            let t = span > 0 ? (location - a.location) / span : 1
            return Color.interpolated(from: a.color, to: b.color, progress: t)
        }
        return last.color
    }

    /// The stops with their colours resolved in `environment`.
    /// 色標的顏色在 `environment` 中 resolve 之後的漸層。
    @MainActor func resolved(in environment: EnvironmentValues) -> Gradient {
        var gradient = self
        gradient.stops = stops.map { Stop(color: Color($0.color.resolve(in: environment)), location: $0.location) }
        return gradient
    }

    /// Locations and colour components, for ``LayoutAnimationDiagnostics``.
    /// 位置與顏色分量，供 ``LayoutAnimationDiagnostics`` 使用。
    @MainActor func diagnosticValues(in environment: EnvironmentValues) -> [Double] {
        stops.flatMap { stop -> [Double] in
            let c = stop.color.resolve(in: environment)
            return [stop.location, Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity)]
        }
    }
}

extension UnitPoint {
    static func interpolated(from a: UnitPoint, to b: UnitPoint, progress: Double) -> UnitPoint {
        UnitPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
    }
}

/// A gradient view's drawn gradient. / 漸層 view 畫出的漸層。
final class GradientViewStorage<Drawn: AnimatableValue & Equatable>: ViewGraphNodeChildren {
    let widgets: [AnyWidget] = []
    let erasedNodes: [ErasedViewGraphNode] = []
    /// Made at the first commit, on the main actor. / 在第一次 commit 時(於 main actor 上)建立。
    var tween: ParameterTween<Drawn>?
}

/// Shared by the three gradient views: draws `view` through its tween.
/// 三種漸層 view 共用：經由補間畫出 `view`。
@MainActor
enum GradientAnimation {
    static func commit(
        _ drawing: GradientDrawing,
        children: any ViewGraphNodeChildren,
        environment: EnvironmentValues,
        draw: @escaping (GradientDrawing) -> Void
    ) -> Bool {
        guard let storage = children as? GradientViewStorage<GradientDrawing> else { return false }
        let tween = storage.tween ?? ParameterTween<GradientDrawing>()
        storage.tween = tween
        tween.onFrame = { [weak tween] in
            guard let drawn = tween?.drawn else { return }
            draw(drawn)
            LayoutAnimationDiagnostics.record(environment, "gradient", values: drawn.diagnosticValues(in: environment))
        }
        let shown = tween.resolve(drawing, transaction: EffectTransaction.current(in: environment))
        draw(shown)
        LayoutAnimationDiagnostics.record(environment, "gradient", values: shown.diagnosticValues(in: environment))
        return true
    }
}

/// What a gradient view draws, as a value the tween can move: the resolved
/// gradient and the view's geometry (points, radii, angles in radians).
/// 漸層 view 畫的東西，作為補間可以移動的值:resolve 後的漸層與 view 的幾何(點、半徑、以弧度表示的角度)。
struct GradientDrawing: Equatable, Sendable, AnimatableValue {
    var gradient: Gradient
    var points: [UnitPoint]
    var scalars: [Double]
    /// AngularGradient without an end angle. / 沒有終止角的 AngularGradient。
    var isOpen = false

    static func interpolated(from a: GradientDrawing, to b: GradientDrawing, progress: Double) -> GradientDrawing {
        guard a.points.count == b.points.count, a.scalars.count == b.scalars.count, a.isOpen == b.isOpen else {
            // A different form (an angular gradient gaining an end angle):
            // the colours move, the geometry takes the target's.
            // 形式不同(角度漸層多了終止角):顏色移動，幾何採用目標的。
            var drawing = b
            drawing.gradient = Gradient.interpolated(from: a.gradient, to: b.gradient, progress: progress)
            return drawing
        }
        return GradientDrawing(
            gradient: Gradient.interpolated(from: a.gradient, to: b.gradient, progress: progress),
            points: zip(a.points, b.points).map { UnitPoint.interpolated(from: $0, to: $1, progress: progress) },
            scalars: zip(a.scalars, b.scalars).map { $0 + ($1 - $0) * progress },
            isOpen: b.isOpen
        )
    }

    @MainActor func diagnosticValues(in environment: EnvironmentValues) -> [Double] {
        gradient.diagnosticValues(in: environment) + points.flatMap { [$0.x, $0.y] } + scalars
    }
}

extension LinearGradient {
    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        GradientViewStorage<GradientDrawing>()
    }

    /// Drawn through the gradient's tween (StyleAnimation.swift).
    /// 經由漸層的補間畫出(StyleAnimation.swift)。
    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let drawing = GradientDrawing(
            gradient: gradient.resolved(in: environment), points: [startPoint, endPoint], scalars: []
        )
        let drew = GradientAnimation.commit(drawing, children: children, environment: environment) { drawn in
            LinearGradient(gradient: drawn.gradient, startPoint: drawn.points[0], endPoint: drawn.points[1])
                .commit(widget, layout: layout, environment: environment, backend: backend)
        }
        if !drew {
            commit(widget, layout: layout, environment: environment, backend: backend)
        }
    }
}

extension RadialGradient {
    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        GradientViewStorage<GradientDrawing>()
    }

    /// Drawn through the gradient's tween (StyleAnimation.swift).
    /// 經由漸層的補間畫出(StyleAnimation.swift)。
    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let drawing = GradientDrawing(
            gradient: gradient.resolved(in: environment), points: [center],
            scalars: [startRadius, endRadius]
        )
        let drew = GradientAnimation.commit(drawing, children: children, environment: environment) { drawn in
            RadialGradient(
                gradient: drawn.gradient, center: drawn.points[0],
                startRadius: drawn.scalars[0], endRadius: drawn.scalars[1]
            )
            .commit(widget, layout: layout, environment: environment, backend: backend)
        }
        if !drew {
            commit(widget, layout: layout, environment: environment, backend: backend)
        }
    }
}

extension AngularGradient {
    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        GradientViewStorage<GradientDrawing>()
    }

    /// Drawn through the gradient's tween (StyleAnimation.swift).
    /// 經由漸層的補間畫出(StyleAnimation.swift)。
    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let drawing = GradientDrawing(
            gradient: gradient.resolved(in: environment), points: [center],
            scalars: [startAngle.radians] + (endAngle.map { [$0.radians] } ?? []),
            isOpen: endAngle == nil
        )
        let drew = GradientAnimation.commit(drawing, children: children, environment: environment) { drawn in
            let start = Angle(radians: drawn.scalars[0])
            let view =
                drawn.isOpen
                ? AngularGradient(gradient: drawn.gradient, center: drawn.points[0], angle: start)
                : AngularGradient(
                    gradient: drawn.gradient, center: drawn.points[0], startAngle: start,
                    endAngle: Angle(radians: drawn.scalars[1])
                )
            view.commit(widget, layout: layout, environment: environment, backend: backend)
        }
        if !drew {
            commit(widget, layout: layout, environment: environment, backend: backend)
        }
    }
}
/// A `Text`'s drawn colour. / `Text` 畫出的顏色。
final class TextColorStorage: ViewGraphNodeChildren {
    let widgets: [AnyWidget] = []
    let erasedNodes: [ErasedViewGraphNode] = []
    /// Made on first use, on the main actor. / 第一次使用時(於 main actor 上)建立。
    var color: ParameterTween<Color>?

    /// `environment` with the foreground colour to draw now: on its way from
    /// the drawn colour when it changed under an animation. An unset colour
    /// stays unset unless a tween is moving it, so the backend keeps its own
    /// default (a dynamic system colour) at rest.
    /// 帶著現在要畫的前景色的 `environment`:若它在動畫中改變，則正從畫出的顏色走向它。未設定的顏色維持未設定，除非
    /// 補間正在移動它，讓 backend 在靜止時保有它自己的預設色(動態系統色)。
    @MainActor
    func environment(for environment: EnvironmentValues) -> EnvironmentValues {
        let tween = color ?? ParameterTween<Color>()
        color = tween
        let target = Color(environment.suggestedForegroundColor.resolve(in: environment))
        let shown = tween.resolve(target, transaction: EffectTransaction.current(in: environment))
        guard environment.foregroundColor != nil || tween.isAnimating else { return environment }
        return environment.with(\.foregroundColor, shown)
    }
}

extension Text {
    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        TextColorStorage()
    }

    /// Laid out with the colour on its way (StyleAnimation.swift).
    /// 以正在補間中的顏色排版(StyleAnimation.swift)。
    @MainActor
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let environment = (children as? TextColorStorage)?.environment(for: environment) ?? environment
        return computeLayout(widget, proposedSize: proposedSize, environment: environment, backend: backend)
    }

    /// Each frame of a colour tween sets the colour on the text view; the
    /// size does not change, so nothing is laid out.
    /// 顏色補間的每一幀把顏色設到文字 view 上;尺寸不變，所以不排版。
    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        if let storage = children as? TextColorStorage, let tween = storage.color {
            let content = environment.applyingTextTransforms(to: string)
            tween.onFrame = { [weak tween] in
                guard let drawn = tween?.drawn else { return }
                let frameEnvironment = environment.with(\.foregroundColor, drawn)
                backend.updateTextView(widget, content: content, environment: frameEnvironment)
                LayoutAnimationDiagnostics.record(environment, "text", color: drawn)
            }
            if let drawn = tween.drawn {
                LayoutAnimationDiagnostics.record(environment, "text", color: drawn)
            }
        }
        commit(widget, layout: layout, environment: environment, backend: backend)
    }
}

extension View {
    /// Sets the colour of the text in this view -- SwiftUI's
    /// `foregroundStyle(_:)` with a colour, the same as ``foregroundColor(_:)``.
    /// 設定此 view 中文字的顏色——SwiftUI 以顏色呼叫的 `foregroundStyle(_:)`,與 ``foregroundColor(_:)`` 相同。
    public func foregroundStyle(_ color: Color) -> some View {
        foregroundColor(color)
    }
}
