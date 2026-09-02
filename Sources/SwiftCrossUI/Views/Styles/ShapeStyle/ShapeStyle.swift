/// Something a shape can be painted with.
///
/// Shaped after ``ListStyle`` rather than ``DatePickerStyle``, and the
/// difference is the point: a date-picker style substitutes a *view*, so its
/// protocol needs an associated `Body` and a `makeView`. A shape style
/// substitutes nothing -- it resolves to a value the backend paints, exactly
/// the relationship `_asBackendListStyle` has. So there is one requirement and
/// no associated type.
///
/// Introduced only after `renderPath` could paint more than two flat colours
/// (#66). `DatePickerStyle` and `ListStyle` both became protocols after they
/// did something (#63, #64); doing it the other way round would have been a
/// protocol over a capability that did not exist.
///
/// 一個形狀可以被塗上的東西。
///
/// 形狀比照 ``ListStyle`` 而非 ``DatePickerStyle``，而那個差別正是重點：date picker 的 style 會
/// 替換掉一個 *view*，因此它的 protocol 需要 associated `Body` 與 `makeView`。shape style 不替換
/// 任何東西——它解析成一個值，由 backend 來塗，這正是 `_asBackendListStyle` 的關係。因此只有一個
/// requirement，沒有 associated type。
///
/// 直到 `renderPath` 能畫出兩種純色以外的東西之後才引入（#66）。`DatePickerStyle` 與 `ListStyle`
/// 都是在真的做了事之後才成為 protocol（#63、#64）；反過來做，等於為一個尚不存在的能力立協定。
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

// `AngularGradient` deliberately does not conform. `ResolvedFillStyle` has no
// conic case, because XAML has no conic brush -- which is why
// `WinUIBackend+AngularGradient.swift` exists as a separate workaround. A
// conformance would have to invent a case that one of the two verified
// backends cannot paint, so the absence is the honest state rather than an
// oversight. It stays usable as a view, which is what it already was.
//
// `AngularGradient` 刻意不宣告 conformance。`ResolvedFillStyle` 沒有 conic case，因為 XAML 沒有
// conic brush——那正是 `WinUIBackend+AngularGradient.swift` 作為獨立變通存在的原因。若要宣告
// conformance，就得發明一個「已驗證的兩個 backend 之一畫不出來」的 case，因此這個缺席是誠實的
// 現狀，而不是疏漏。它作為 view 仍可使用，那本來就是它原本的身分。
