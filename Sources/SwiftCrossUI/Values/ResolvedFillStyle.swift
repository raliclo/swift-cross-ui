/// What a shape is painted with, resolved down to what a backend can act on.
///
/// `renderPath` took two `Color.Resolved` and nothing else, which is why
/// `Circle().fill(LinearGradient(...))` did not exist: gradients reach a backend
/// as whole rectangular widgets on a separate protocol, so there was no way to
/// clip one to a shape. This is the value that closes that gap.
///
/// Deliberately an enum and not a `ShapeStyle` protocol. SwiftUI's `ShapeStyle`
/// has a wide conformance surface, and building the wide part before the narrow
/// part works is the wrong order -- `DatePickerStyle` and `ListStyle` were both
/// turned into protocols only after they did something (#63, #64), and that
/// order worked. The protocol is #31.
///
/// Angular is absent on purpose: XAML has no conic brush, which is why
/// `WinUIBackend+AngularGradient.swift` exists as a workaround, and starting
/// with the hardest case would stall the easy ones.
///
/// 一個形狀被塗上什麼，解析到 backend 能據以行動的程度。
///
/// `renderPath` 只收兩個 `Color.Resolved`，別無其他，這正是
/// `Circle().fill(LinearGradient(...))` 不存在的原因：漸層是以整塊矩形 widget、經由另一個
/// protocol 抵達 backend 的，因此沒有辦法把它裁進一個形狀裡。本型別就是用來補上這個缺口的值。
///
/// 刻意採用 enum 而非 `ShapeStyle` protocol。SwiftUI 的 `ShapeStyle` 有很寬的 conformance 面，
/// 而在窄的部分能動之前先蓋寬的部分，順序是反的——`DatePickerStyle` 與 `ListStyle` 都是在它們
/// 真的做了事之後才轉為 protocol（#63、#64），那個順序是可行的。protocol 本身是 #31。
///
/// 刻意不含 angular：XAML 沒有 conic brush，這正是 `WinUIBackend+AngularGradient.swift` 作為
/// 變通存在的原因，而從最難的情況起手會讓容易的那些一起卡住。
public enum ResolvedFillStyle: Sendable {
    case color(Color.Resolved)

    /// `startPoint` and `endPoint` are in the shape's own unit space, so a
    /// backend multiplies them by the path's bounds rather than the widget's.
    /// That is the whole difference from the gradient *views*, which fill a
    /// rectangle they own.
    /// `startPoint` 與 `endPoint` 位於形狀自身的單位空間，因此 backend 應以路徑的 bounds、而非
    /// widget 的尺寸相乘。這正是它與漸層**視圖**的根本差異——後者填滿的是它自己擁有的矩形。
    case linearGradient(Gradient, startPoint: UnitPoint, endPoint: UnitPoint)

    case radialGradient(
        Gradient,
        center: UnitPoint,
        startRadius: Double,
        endRadius: Double
    )

    /// The single colour to use when a backend cannot paint this style.
    ///
    /// The **midpoint** stop, not the first. A two-stop gradient flattened to
    /// its first colour looks like the gradient was ignored; the midpoint reads
    /// as an approximation of it. Callers must still say out loud that they
    /// degraded -- see `BackendFeatures.Paths` -- because drawing *something*
    /// plausible is worse than drawing nothing: it reads as a rendering bug
    /// rather than a missing feature.
    ///
    /// 當 backend 無法繪製此樣式時所使用的單一顏色。
    ///
    /// 取**中點**的 stop，而非第一個。把雙 stop 的漸層壓成它的第一個顏色，看起來像漸層被忽略了；
    /// 取中點則讀起來像是它的近似。呼叫端仍必須明確說出自己降級了——見 `BackendFeatures.Paths`
    /// ——因為畫出一個「看似合理的東西」比什麼都不畫更糟：它讀起來像算繪 bug，而不是缺少功能。
    @MainActor
    public func flattened(in environment: EnvironmentValues) -> Color.Resolved {
        switch self {
            case .color(let resolved):
                return resolved
            case .linearGradient(let gradient, _, _),
                .radialGradient(let gradient, _, _, _):
                return Self.midpoint(of: gradient).resolve(in: environment)
        }
    }

    private static func midpoint(of gradient: Gradient) -> Color {
        let stops = gradient.stops
        guard !stops.isEmpty else { return Color.black.opacity(0) }
        // The stop nearest location 0.5, rather than the middle of the array:
        // stops are not evenly spaced, and a gradient whose stops cluster at one
        // end would otherwise flatten to a colour from that end.
        // 取位置最接近 0.5 的 stop，而非陣列中間的那一個：stop 之間並非等距，若不如此，一個 stop
        // 聚集在某一端的漸層就會被壓成該端的顏色。
        return stops.min(by: {
            abs($0.location - 0.5) < abs($1.location - 0.5)
        })!.color
    }
}
