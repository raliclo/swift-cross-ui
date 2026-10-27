/// Something a shape can be painted with.
///
/// Shaped after ``ListStyle`` rather than ``DatePickerStyle``, and the
/// difference is the point: a date-picker style substitutes a *view*, so its
/// protocol needs an associated `Body` and a `makeView`. A shape style
/// substitutes nothing -- it resolves to a value the backend paints, exactly
/// the relationship `_asBackendListStyle` has. So there is one requirement and
/// no associated type.
///
/// 一個形狀可以被塗上的東西。
///
/// 形狀比照 ``ListStyle`` 而非 ``DatePickerStyle``，而那個差別正是重點：date picker 的 style 會
/// 替換掉一個 *view*，因此它的 protocol 需要 associated `Body` 與 `makeView`。shape style 不替換
/// 任何東西——它解析成一個值，由 backend 來塗，這正是 `_asBackendListStyle` 的關係。因此只有一個
/// requirement，沒有 associated type。
@MainActor
public protocol ShapeStyle: Sendable {
    /// Resolves to what a backend can act on.
    ///
    /// Underscored because it is the seam between this protocol and
    /// ``BackendFeatures/Paths``, not something an application calls. Same
    /// reason as `_asBackendListStyle`.
    ///
    /// 解析成 backend 能據以行動的東西。
    ///
    /// 加底線，是因為它是本 protocol 與 ``BackendFeatures/Paths`` 之間的接縫，而非應用程式會呼叫
    /// 的東西。理由與 `_asBackendListStyle` 相同。
    func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle
}

extension Color: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle {
        .color(resolve(in: environment))
    }
}

extension LinearGradient: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle {
        .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint)
    }
}

extension RadialGradient: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle {
        .radialGradient(
            gradient,
            center: center,
            startRadius: startRadius,
            endRadius: endRadius
        )
    }
}

extension AngularGradient: ShapeStyle {
    /// A conic gradient in the shape's bounds, as in SwiftUI.
    /// 形狀外框中的錐形漸層，同 SwiftUI。
    public func _resolve(in environment: EnvironmentValues) -> ResolvedFillStyle {
        .angularGradient(
            gradient,
            center: center,
            startAngle: startAngle,
            endAngle: endAngle ?? startAngle + Angle(degrees: 360)
        )
    }
}
