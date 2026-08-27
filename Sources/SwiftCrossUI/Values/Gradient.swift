import DebugFeatures

/// A color gradient represented as an array of color stops, each having a normalized location value.
public struct Gradient: Sendable, Hashable {
    /// The array of color stops, ordered by location.
    public var stops: [Gradient.Stop]

    /// Creates a gradient from an array of color stops ordered by location.
    ///
    /// - Parameters:
    ///   - stops: The stops of the Gradient. If no stop is passed, the gradient will be fully transparent.
    init(stops: [Gradient.Stop]) {
        guard let first = stops.first else {
            let invisible = Color.black.opacity(0)
            self.stops = [
                Stop(color: invisible, location: 0),
                Stop(color: invisible, location: 1),
            ]
            return
        }

        // On `SCUI_DEBUG` rather than `#if DEBUG`, because release is the only
        // configuration this project builds by default and the check was absent
        // from it. It is not made unconditional like the unsupported-style
        // warnings, because it is not free: `sorted(by:)` allocates a second
        // array on every gradient constructed, and gradients are constructed
        // during layout. `isEnabled` is a `static let` that a build without the
        // define initialises to `false`, so the comparison and the allocation
        // are both behind a constant the optimiser can fold away -- the same
        // cost as `#if DEBUG` had, now reachable in a release binary built and
        // run with the flag.
        //
        // 改以 `SCUI_DEBUG` 為條件、而非 `#if DEBUG`，因為 release 是本專案唯一預設建置的組態，
        // 而此檢查在其中並不存在。它沒有像「不支援的 style」那類警告一樣改為無條件，是因為它並非
        // 免費：`sorted(by:)` 會在每次建構 gradient 時另外配置一個陣列，而 gradient 是在排版期間
        // 建構的。`isEnabled` 是一個 `static let`，在未定義該旗標的建置中初始化為 `false`，因此
        // 比較與配置都位於一個最佳化器可摺除的常數之後——代價與原本的 `#if DEBUG` 相同，但如今在
        // 以該旗標建置並執行的 release 執行檔中是可觸及的。
        if DebugFeatures.isEnabled,
            stops != stops.sorted(by: { $0.location < $1.location })
        {
            logger.warning("Gradient stop locations must be ordered")
        }

        if stops.count == 1 {
            self.stops = [
                Stop(color: first.color, location: 0),
                Stop(color: first.color, location: 1),
            ]
        } else {
            self.stops = stops
        }
    }

    /// Creates a gradient from an array of colors.
    /// - Parameters:
    ///   - colors: The colors of the gradient. The gradient synthesizes its location values to evenly
    ///     space the colors along the gradient. If no color is passed, the gradient will be fully transparent.
    init(colors: [Color]) {
        guard let first = colors.first else {
            let invisible = Color.black.opacity(0)
            self.stops = [
                Stop(color: invisible, location: 0),
                Stop(color: invisible, location: 1),
            ]
            return
        }

        if colors.count == 1 {
            self.stops = [
                Stop(color: first, location: 0),
                Stop(color: first, location: 1),
            ]
            return
        }

        var stops = [Stop(color: first, location: 0)]
        for (i, color) in colors[1...].enumerated() {
            let location = Double(i + 1) / Double(colors.count - 1)
            stops.append(
                Stop(color: color, location: location)
            )
        }

        self.stops = stops
    }

    /// One color stop in a gradient.
    public struct Stop: Sendable, Equatable, Hashable {
        /// Creates a color stop with a color and location.
        /// - Parameters:
        ///   - color: The color that should be placed at this stop.
        ///   - location: The location of this stop. 0 corresponds to the start and 1 to the end.
        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }

        /// The color for the stop.
        public var color: Color
        /// The parametric location of the stop.
        public var location: Double
    }
}
