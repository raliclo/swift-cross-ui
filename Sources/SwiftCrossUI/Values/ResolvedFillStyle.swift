/// What a shape is painted with, resolved down to what a backend can act on.
///
/// Gradients otherwise reach a backend as whole rectangular widgets on a
/// separate protocol, with no way to clip one to a shape. Carrying this value
/// through `renderPath` is what makes `Circle().fill(LinearGradient(...))`
/// possible.
///
/// Deliberately an enum and not a `ShapeStyle` protocol. SwiftUI's `ShapeStyle`
/// has a wide conformance surface, and building the wide part before the narrow
/// part works is the wrong order -- `DatePickerStyle` and `ListStyle` were both
/// turned into protocols only after they did something (#63, #64), and that
/// order worked. The protocol is #31.
///
/// Angular is included (`angularGradient`) although XAML has no conic brush:
/// WinUIBackend rasterises it with `ConicGradientBrush` (the gradient view has
/// its own workaround in `WinUIBackend+AngularGradient.swift`).
///
/// 一個形狀被塗上什麼，解析到 backend 能據以行動的程度。
///
/// 漸層若以整塊矩形 widget、經由另一個 protocol 抵達 backend,就沒有辦法把它裁進一個形狀裡；
/// 讓本型別經由 `renderPath` 傳遞，`Circle().fill(LinearGradient(...))` 才得以存在。
///
/// 刻意採用 enum 而非 `ShapeStyle` protocol。SwiftUI 的 `ShapeStyle` 有很寬的 conformance 面，
/// 而在窄的部分能動之前先蓋寬的部分，順序是反的——`DatePickerStyle` 與 `ListStyle` 都是在它們
/// 真的做了事之後才轉為 protocol（#63、#64），那個順序是可行的。protocol 本身是 #31。
///
/// angular 也包含在內(`angularGradient`),儘管 XAML 沒有 conic brush:WinUIBackend 以
/// `ConicGradientBrush` 把它點陣化(漸層 view 另有 `WinUIBackend+AngularGradient.swift` 的變通做法)。
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
    /// A conic gradient, as SwiftUI's `AngularGradient`: angles from three
    /// o'clock, clockwise on screen, the centre a unit point of the shape's
    /// bounds. A gradient made with one angle has `endAngle` a full turn on.
    /// Backends draw it as a full turn from `startAngle` with
    /// ``angularTurnStops(_:startAngle:endAngle:)``.
    /// 錐形漸層，同 SwiftUI 的 `AngularGradient`:角度自三點鐘方向起、在螢幕上順時針，中心是形狀外框的單位座標。
    /// 只給一個角度的漸層，`endAngle` 是其後一整圈。backend 以 ``angularTurnStops(_:startAngle:endAngle:)``
    /// 從 `startAngle` 畫一整圈。
    case angularGradient(
        Gradient,
        center: UnitPoint,
        startAngle: Angle,
        endAngle: Angle
    )
    /// The stops over one turn that starts at `startAngle` (0 there, 1 a turn
    /// on): squeezed into the sweep to `endAngle`, reversed for a sweep that
    /// runs backwards, the last colour after it -- the rule
    /// `AngularGradient.adjustedStops` applies to the view, so a shape and the
    /// view draw the same gradient.
    /// 從 `startAngle` 起一整圈的色標(該處為 0、一圈後為 1):壓進到 `endAngle` 的掃掠範圍、反向掃掠時反轉、其後是最後
    /// 一個顏色——與 view 用的 `AngularGradient.adjustedStops` 規則相同，因此形狀與 view 畫出同一個漸層。
    public static func angularTurnStops(
        _ gradient: Gradient,
        startAngle: Angle,
        endAngle: Angle
    ) -> [Gradient.Stop] {
        let range = (endAngle - startAngle).degrees
        let sweep = min(abs(range), 360) / 360
        return gradient.stops
            .map { Gradient.Stop(color: $0.color, location: (range < 0 ? 1 - $0.location : $0.location) * sweep) }
            .sorted { $0.location < $1.location }
    }

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
                .radialGradient(let gradient, _, _, _),
                .angularGradient(let gradient, _, _, _):
                return Self.midpoint(of: gradient, in: environment)
        }
    }

    /// The colour the gradient actually has at location 0.5.
    ///
    /// **Not the stop nearest 0.5, which returns the first colour for the
    /// commonest gradient there is.** `Gradient(colors: [.red, .blue])` has stops
    /// at 0.0 and 1.0; both are exactly 0.5 away, `min(by:)` keeps the first of
    /// an equal pair, and the "midpoint" would be red. That is the outcome the
    /// note above this function says must not happen -- flattening a two-stop
    /// gradient to its first colour reads as the gradient having been ignored.
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
    /// **不是「最接近 0.5 的 stop」,因為那對最常見的漸層會回傳第一個顏色。**
    /// `Gradient(colors: [.red, .blue])` 的 stop 位於 0.0 與 1.0;兩者距 0.5 都恰好是 0.5,而
    /// `min(by:)` 在相等時保留前者，於是「中點」會是紅色。那正是本函式上方那段說明所指「不可以發生」
    /// 的結果——把雙 stop 的漸層壓成它的第一個顏色，讀起來像漸層被忽略了。
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
        // nearest end is the honest answer.
        // 一個整段都落在 0.5 同一側的漸層，沒有中點可找；離它最近的那一端就是誠實的答案。
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
