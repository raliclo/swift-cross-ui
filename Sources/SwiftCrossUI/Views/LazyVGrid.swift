/// One column of a ``LazyVGrid``.
///
/// The three sizes are SwiftUI's, and they differ in what they let the grid
/// decide. ``fixed(_:)`` and ``flexible(minimum:maximum:)`` each describe one
/// column; ``adaptive(minimum:maximum:)`` describes *as many columns as fit*, so
/// a single adaptive item can become five columns on a wide window and two on a
/// narrow one. That is why column resolution takes the proposed width rather
/// than being a property of the array.
///
/// ``LazyVGrid`` 的一個欄。
///
/// 這三種尺寸取自 SwiftUI，而它們的差別在於各自讓格線決定多少事。``fixed(_:)`` 與
/// ``flexible(minimum:maximum:)`` 各自描述**一個**欄;``adaptive(minimum:maximum:)`` 描述的則是
/// **塞得下幾欄就是幾欄**——因此單一個 adaptive 項目在寬視窗上可能成為五欄、在窄視窗上成為兩欄。
/// 這正是欄位解析必須接收「被建議的寬度」、而不能只是該陣列自身屬性的原因。
public struct GridItem: Sendable {
    public enum Size: Sendable {
        /// Exactly this many points wide.
        /// 恰好這麼多點寬。
        case fixed(Int)

        /// One column, between `minimum` and `maximum` points wide.
        /// 一個欄，寬度介於 `minimum` 與 `maximum` 點之間。
        case flexible(minimum: Int = 10, maximum: Int? = nil)

        /// As many columns of at least `minimum` points as fit.
        /// 在寬度允許下，盡可能多的欄，每欄至少 `minimum` 點。
        case adaptive(minimum: Int, maximum: Int? = nil)
    }

    public var size: Size
    public var spacing: Int?
    public var alignment: HorizontalAlignment?

    public init(
        _ size: Size = .flexible(),
        spacing: Int? = nil,
        alignment: HorizontalAlignment? = nil
    ) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

/// A grid that fills its columns left to right and then wraps.
///
/// Composed from the same layout primitives every stack uses -- it asks each
/// child to lay itself out in its column's width and then positions it -- so it
/// needs nothing from any backend and behaves identically on all five.
///
/// **"Lazy" is the SwiftUI spelling, not a claim about this implementation.**
/// SwiftUI's LazyVGrid builds only the cells near the viewport; this one builds
/// every child, exactly as ``LazyVStack`` does here. The name is kept because
/// the point of it is source compatibility, and a `VGrid` that had to be renamed
/// later would be worse than a name that promises an optimisation it does not
/// yet make. Nothing observable differs except the work done off screen.
///
/// 一個由左至右填滿各欄、滿了就換行的格線。
///
/// 由每個 stack 都在使用的同一批版面原語組合而成——它請每個子節點在其所屬欄的寬度中完成自身佈局，
/// 然後為其定位——因此它不需要任何 backend 支援，在五個 backend 上的行為也完全相同。
///
/// **「Lazy」是 SwiftUI 的拼法，不是對本實作的宣稱。** SwiftUI 的 LazyVGrid 只建構視口附近的儲存格;
/// 此處這個會建構每一個子節點，與本樹的 ``LazyVStack`` 完全相同。保留該名稱是因為它的意義在於原始碼
/// 相容性，而一個日後必須改名的 `VGrid` 會比「一個承諾了尚未做到之最佳化的名稱」更糟。除了螢幕外
/// 所做的工作量之外，沒有任何可觀察的差異。
public struct LazyVGrid<Content: View>: View {
    static var defaultSpacing: Int { 10 }

    public var body: Content
    private let columns: [GridItem]
    private let alignment: HorizontalAlignment
    private let spacing: Int

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing ?? Self.defaultSpacing
        self.body = content()
    }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        for (index, child) in children.widgets(for: backend).enumerated() {
            backend.insert(child, into: container, at: index)
        }
        return container
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let plan = resolve(proposedWidth: proposedSize.width)
        let layoutable = layoutableChildren(backend: backend, children: children)

        // One child means the grid does not arrange anything itself: that child
        // is a ForEach or a Group, it consumed the plan, and what it reports is
        // the size of the whole grid. Putting it in column zero and centring it
        // there subtracts half the difference between the column and the grid --
        // for three 257pt columns and a 787pt child, that is 265 points of
        // leftward shift, which puts the first column off the left edge. The
        // screenshot showed columns and rows in the right shape with the first
        // column simply absent, which reads as cells that failed to render.
        //
        // 只有一個子節點,表示這個格線自己並不排列任何東西:那個子節點是 ForEach 或 Group、它已經
        // 消費了該計畫,而它回報的是整個格線的尺寸。把它放進第 0 欄並置中,等於減去「欄寬與格線寬度
        // 之差」的一半——以三個 257 點的欄與一個 787 點的子節點來說,那是 265 點的左移,足以把第一欄
        // 推出畫面左緣。當時的截圖顯示欄與列的形狀都正確,只是第一欄整個不見了,那讀起來像是那些
        // 儲存格沒有被繪製出來。
        if layoutable.count == 1 {
            let childResult = layoutable[0].computeLayout(
                proposedSize: ProposedViewSize(Double(Self.width(of: plan)), nil),
                environment: environment.with(\.layoutGridPlan, plan)
            )
            return ViewLayoutResult(
                size: ViewSize(Double(Self.width(of: plan)), childResult.size.height),
                childResults: [childResult]
            )
        }

        return LayoutSystem.computeGridLayout(
            children: layoutable,
            plan: plan,
            environment: environment.with(\.layoutGridPlan, plan),
            // The children here ARE the cells -- a tuple of views rather than a
            // single ForEach -- so the plan must not reach one level further.
            // 此處的子節點**就是**儲存格——是一組 tuple 的 view,而非單一個 ForEach——因此該計畫
            // 不可以再往下傳一層。
            clearsPlanForChildren: true
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let plan = resolve(proposedWidth: layout.size.width)
        let layoutable = layoutableChildren(backend: backend, children: children)

        if layoutable.count == 1 {
            let childResult = layoutable[0].commit()
            backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
            backend.setSize(
                of: widget,
                to: SIMD2(
                    Self.width(of: plan),
                    Int(childResult.size.height.rounded(.up))
                )
            )
            return
        }

        LayoutSystem.commitGridLayout(
            container: widget,
            children: layoutable,
            plan: plan,
            layout: layout,
            environment: environment.with(\.layoutGridPlan, plan),
            backend: backend
        )
    }

    /// The width the columns occupy, spacing included.
    ///
    /// A grid is this wide whether or not its cells filled it, which is what
    /// keeps two grids with the same columns the same width.
    ///
    /// 這些欄所佔據的寬度,已含間距。
    ///
    /// 無論儲存格有沒有填滿,格線都是這麼寬——而那正是讓「欄位相同的兩個格線」寬度也相同的原因。
    static func width(of plan: GridLayoutPlan) -> Int {
        plan.columnWidths.reduce(0, +)
            + plan.spacing * max(0, plan.columnWidths.count - 1)
    }

    func resolve(proposedWidth: Double?) -> GridLayoutPlan {
        Self.resolve(
            columns: columns,
            alignment: alignment,
            spacing: spacing,
            // `flatMap` with an `isFinite` test, not `map`. `Int(Double)` TRAPS
            // on an infinite or NaN value -- an `Illegal instruction`, exit 132,
            // with no message at all, because it is a language-level trap rather
            // than a Swift precondition (those print).
            //
            // `.infinity` is a real value here, not a theoretical one. The layout
            // system probes children with it deliberately:
            // `LayoutSystem.swift:605` is `let specialSizes: [Double?] = [nil,
            // .infinity]`, `:284` assigns `.infinity` to a proposal component,
            // and `ProposedViewSize.swift:6` declares `.infinity` as a whole
            // size. So any grid inside an ordinary stack gets asked this.
            //
            // Measured 2026-09-08: P51 died 1881 ms after launch, exit 132, with
            // an empty replay log -- it never reached its first log line. P50,
            // the same launcher and PATH, was still running when a 25 s cap
            // killed it; P50 has no `LazyVGrid`.
            //
            // Infinite maps to `nil` rather than to a large number because
            // `resolve` already gives `nil` the right meaning: `proposedWidth ??
            // 0` makes `.adaptive` resolve to one column, which is what an
            // unconstrained width should produce. A sentinel like `Int.max`
            // would instead overflow `available + spacing` on the next line.
            //
            // 此處用帶 `isFinite` 測試的 `flatMap`，而非 `map`。`Int(Double)` 在值為無限或 NaN 時會
            // **trap**——`Illegal instruction`、退出碼 132，而且完全沒有訊息，因為那是語言層級的
            // trap，不是 Swift 的 precondition（後者會印出訊息）。
            //
            // `.infinity` 在此是真實存在的值，不是理論上的：版面系統會刻意用它來探測子節點——
            // `LayoutSystem.swift:605` 是 `let specialSizes: [Double?] = [nil, .infinity]`、
            // `:284` 會把 `.infinity` 指派給某個提案分量，而 `ProposedViewSize.swift:6` 更把
            // `.infinity` 宣告為一個完整的尺寸。因此任何位於一般 stack 之中的格線都會被這樣詢問。
            //
            // 2026-09-08 實測：P51 於啟動後 1881 毫秒死亡，退出碼 132，replay log 為空——它從未抵達
            // 自己的第一行 log。P50 在同一個啟動器與同一條 PATH 下，直到 25 秒上限才被砍掉；而 P50
            // 沒有 `LazyVGrid`。
            //
            // 無限值對應到 `nil` 而非某個大數，是因為 `resolve` 已經賦予 `nil` 正確的意義：
            // `proposedWidth ?? 0` 會讓 `.adaptive` 解析為一欄，那正是「寬度無約束」該有的結果。
            // 若改用 `Int.max` 之類的哨兵值，反而會讓下一行的 `available + spacing` 溢位。
            proposedWidth: proposedWidth.flatMap {
                $0.isFinite ? Int($0.rounded(.down)) : nil
            }
        )
    }
}

extension LazyVGrid {
    /// Turns the caller's items into concrete columns.
    ///
    /// Takes the proposed width because ``GridItem/Size/adaptive`` turns one
    /// item into a variable number of columns, so the column COUNT is not
    /// knowable from the array alone.
    ///
    /// 把呼叫端的項目轉成具體的欄位。
    ///
    /// 必須接收「被建議的寬度」,因為 ``GridItem/Size/adaptive`` 會把一個項目變成數量不定的欄,
    /// 因此欄的**數量**無法單憑該陣列得知。
    static func resolve(
        columns: [GridItem],
        alignment: HorizontalAlignment,
        spacing: Int,
        proposedWidth: Int?
    ) -> GridLayoutPlan {
        // A grid with no columns still has to put its children somewhere. One
        // full-width column is what SwiftUI does, and it keeps the modulo
        // arithmetic in LayoutSystem from dividing by zero.
        // 一個沒有任何欄的格線,仍然必須把子節點擺在某處。SwiftUI 的做法是「一個滿寬的欄」,
        // 而那也讓 LayoutSystem 中的取餘數運算不會除以零。
        guard !columns.isEmpty else {
            return GridLayoutPlan(
                columnWidths: [proposedWidth ?? 0],
                columnOffsets: [0],
                alignments: [alignment],
                spacing: spacing
            )
        }

        let available = proposedWidth ?? 0

        // Pass one: how many columns each item becomes, and which of them want a
        // share of what is left after the fixed ones.
        // 第一輪:每個項目會變成幾個欄,以及其中哪些想分配「扣掉固定欄之後」剩下的部分。
        var counts: [Int] = []
        for column in columns {
            switch column.size {
                case .fixed, .flexible:
                    counts.append(1)
                case .adaptive(let minimum, _):
                    // As many as fit, at least one. The numerator adds one
                    // spacing back because n columns carry n-1 gaps.
                    // 塞得下幾個就是幾個,至少一個。分子先加回一份間距,因為 n 個欄之間有 n-1 道空隙。
                    counts.append(max(1, (available + spacing) / (max(minimum, 1) + spacing)))
            }
        }

        let totalColumns = counts.reduce(0, +)
        var fixedTotal = 0
        var shareCount = 0
        for (index, column) in columns.enumerated() {
            if case .fixed(let width) = column.size {
                fixedTotal += width * counts[index]
            } else {
                shareCount += counts[index]
            }
        }
        let remaining = max(
            0,
            available - spacing * max(0, totalColumns - 1) - fixedTotal
        )
        let share = shareCount > 0 ? remaining / shareCount : 0

        // Pass two: expand each item into its columns, clamped to its bounds.
        // 第二輪:把每個項目展開為它的各個欄,並夾在其自身的界限內。
        var widths: [Int] = []
        var alignments: [HorizontalAlignment] = []
        for (index, column) in columns.enumerated() {
            let width: Int =
                switch column.size {
                    case .fixed(let fixed):
                        fixed
                    case .flexible(let minimum, let maximum):
                        min(max(share, minimum), maximum ?? Int.max)
                    case .adaptive(let minimum, let maximum):
                        min(max(share, minimum), maximum ?? Int.max)
                }
            widths.append(contentsOf: Array(repeating: width, count: counts[index]))
            alignments.append(
                contentsOf: Array(
                    repeating: column.alignment ?? alignment,
                    count: counts[index]
                )
            )
        }

        var offsets: [Int] = []
        var x = 0
        for width in widths {
            offsets.append(x)
            x += width + spacing
        }
        return GridLayoutPlan(
            columnWidths: widths,
            columnOffsets: offsets,
            alignments: alignments,
            spacing: spacing
        )
    }
}
