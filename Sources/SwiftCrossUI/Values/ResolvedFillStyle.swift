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
                return Self.midpoint(of: gradient, in: environment)
        }
    }

    /// The colour the gradient actually has at location 0.5.
    ///
    /// **Not the stop nearest 0.5, which is what this did until 2026-09-04 and
    /// which returned the first colour for the commonest gradient there is.**
    /// `Gradient(colors: [.red, .blue])` has stops at 0.0 and 1.0; both are
    /// exactly 0.5 away, `min(by:)` keeps the first of an equal pair, and the
    /// "midpoint" was red. That is the outcome the note above this function
    /// says must not happen -- flattening a two-stop gradient to its first
    /// colour reads as the gradient having been ignored -- so the intent was
    /// right and only the arithmetic was wrong.
    ///
    /// Interpolating removes the tie rather than breaking it, and it is also
    /// the more truthful answer: 0.5 of a red-to-blue ramp is the purple a
    /// backend that could draw the gradient would put there.
    ///
    /// In sRGB, because that is the space every backend's gradient interpolates
    /// in -- `CGGradient` with `CGColorSpace.sRGB`, Cairo's default, Android's
    /// `LinearGradient` -- so this lands on the colour the real gradient would
    /// have shown at its middle rather than on a different blend of the same
    /// two ends.
    ///
    /// 此漸層在位置 0.5 處實際所具有的顏色。
    ///
    /// **不是「最接近 0.5 的 stop」——那是本函式在 2026-09-04 之前的做法，而它對最常見的漸層
    /// 回傳的是第一個顏色。** `Gradient(colors: [.red, .blue])` 的 stop 位於 0.0 與 1.0；兩者距
    /// 0.5 都恰好是 0.5，而 `min(by:)` 在相等時保留前者，於是「中點」是紅色。那正是本函式上方那段
    /// 說明所指「不可以發生」的結果——把雙 stop 的漸層壓成它的第一個顏色，讀起來像漸層被忽略了
    /// ——因此當初的意圖是對的，錯的只有算術。
    ///
    /// 內插是「消除」這個平手，而不是「打破」它；而且它也是更誠實的答案：一段紅到藍的漸變在 0.5
    /// 處，正是一個畫得出該漸層的 backend 會放在那裡的紫色。
    ///
    /// 在 sRGB 空間中進行，因為那是每一個 backend 的漸層所使用的內插空間——`CGGradient` 搭配
    /// `CGColorSpace.sRGB`、Cairo 的預設、Android 的 `LinearGradient`——因此此處會落在「真實漸層
    /// 在其中間所顯示的顏色」上，而不是同樣兩端的另一種混色。
    @MainActor
    private static func midpoint(
        of gradient: Gradient,
        in environment: EnvironmentValues
    ) -> Color.Resolved {
        // Sorted, because `Gradient(stops:)` takes whatever order the caller
        // wrote and the bracket below walks pairs. An unsorted array would make
        // the pair search miss and fall through to the last stop.
        // 先排序，因為 `Gradient(stops:)` 會照呼叫端所寫的順序收下，而下方的區間搜尋是逐對走訪的。
        // 未排序的陣列會使該搜尋落空，並一路掉到最後一個 stop。
        let stops = gradient.stops.sorted { $0.location < $1.location }

        guard let first = stops.first else {
            return Color.black.opacity(0).resolve(in: environment)
        }
        guard let last = stops.last, stops.count > 1 else {
            return first.color.resolve(in: environment)
        }

        // A gradient entirely on one side of 0.5 has no midpoint to find; its
        // nearest end is the honest answer, and it is the case the old
        // "clustered at one end" note was really about.
        // 一個整段都落在 0.5 同一側的漸層，沒有中點可找；離它最近的那一端就是誠實的答案，而那正是
        // 舊註解所說「聚集在某一端」真正指的情況。
        guard first.location < 0.5 else { return first.color.resolve(in: environment) }
        guard last.location > 0.5 else { return last.color.resolve(in: environment) }

        var lower = first
        var upper = last
        for (start, end) in zip(stops, stops.dropFirst())
        where start.location <= 0.5 && 0.5 <= end.location {
            lower = start
            upper = end
            break
        }

        let span = upper.location - lower.location
        let fraction = span > 0 ? Float((0.5 - lower.location) / span) : 0
        let start = lower.color.resolve(in: environment)
        let end = upper.color.resolve(in: environment)

        return Color.Resolved(
            red: start.red + (end.red - start.red) * fraction,
            green: start.green + (end.green - start.green) * fraction,
            blue: start.blue + (end.blue - start.blue) * fraction,
            opacity: start.opacity + (end.opacity - start.opacity) * fraction
        )
    }
}
