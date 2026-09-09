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
///
/// **The sizes are `Double`, and they were `Int` until task #108.** SwiftUI's
/// are `CGFloat`, which cost two things here. The loud one: `.fixed(100.5)` and
/// `GridItem(.flexible(minimum: 100, maximum: .infinity))` -- the commonest grid
/// line in SwiftUI source, because `.infinity` is how SwiftUI spells "no
/// maximum" -- did not compile. The quiet one: an integer division split the
/// proposed width, so on a fractional display scale the columns could not sum to
/// their container and the remainder was dropped rather than distributed.
/// Integer literals still compile unchanged: `GridItem(.fixed(96))` is what P48
/// and P51 write today.
///
/// **這些尺寸的型別是 `Double`，在任務 #108 之前則是 `Int`。** SwiftUI 用的是 `CGFloat`，而此處為此
/// 付出了兩項代價。明顯的那一項：`.fixed(100.5)` 與
/// `GridItem(.flexible(minimum: 100, maximum: .infinity))`——由於 SwiftUI 是用 `.infinity` 表達
/// 「沒有上限」，後者正是 SwiftUI 原始碼中最常見的那一行格線宣告——都編不過。安靜的那一項：整數
/// 除法會切分被建議的寬度，因此在非整數的顯示縮放下，各欄無法加總回其容器，餘數是被丟掉而不是被
/// 分配掉。整數字面量仍照舊編得過：`GridItem(.fixed(96))` 正是 P48 與 P51 今天所寫的形式。
public struct GridItem: Sendable {
    public enum Size: Sendable {
        /// Exactly this many points wide.
        /// 恰好這麼多點寬。
        case fixed(Double)

        /// One column, between `minimum` and `maximum` points wide.
        ///
        /// `maximum` defaults to `.infinity`, not to an optional `nil`, because
        /// that is SwiftUI's spelling and because a caller who writes
        /// `maximum: .infinity` is asking for exactly the same thing as one who
        /// leaves it out. ``LazyVGrid/resolve(columns:alignment:spacing:proposedWidth:)``
        /// treats it as "no upper bound" rather than converting it to anything.
        ///
        /// 一個欄，寬度介於 `minimum` 與 `maximum` 點之間。
        ///
        /// `maximum` 的預設值是 `.infinity` 而非 optional 的 `nil`，因為那是 SwiftUI 的寫法，也因為
        /// 寫下 `maximum: .infinity` 的呼叫端，要的就是與省略它的呼叫端完全相同的東西。
        /// ``LazyVGrid/resolve(columns:alignment:spacing:proposedWidth:)`` 把它當成「沒有上界」處理，
        /// 而不是把它轉換成任何東西。
        case flexible(minimum: Double = 10, maximum: Double = .infinity)

        /// As many columns of at least `minimum` points as fit.
        /// 在寬度允許下，盡可能多的欄，每欄至少 `minimum` 點。
        case adaptive(minimum: Double, maximum: Double = .infinity)
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

    /// Upper bounds that exist to keep `Int(_:)` from trapping, not to express
    /// any layout policy.
    ///
    /// Both are reached only by a value no display can produce -- ten thousand
    /// columns, or a column a million points wide. They matter because the sizes
    /// are `Double` since task #108, and `Int(_:)` traps above `Int.max` for the
    /// same language-level reason it traps on `.infinity`: silently, with exit
    /// 132 and no message. Clamping to an absurd-but-finite number turns a value
    /// that could only have come from a bug into a picture that is visibly
    /// wrong, which is strictly better than a process that vanishes.
    ///
    /// 這兩個上界的存在，是為了讓 `Int(_:)` 不要 trap，而不是為了表達任何版面政策。
    ///
    /// 兩者都只會被「任何顯示器都產不出來的值」觸及——一萬個欄，或一個一百萬點寬的欄。它們之所以
    /// 重要，是因為自任務 #108 起尺寸型別為 `Double`，而 `Int(_:)` 在超過 `Int.max` 時會 trap，
    /// 其語言層級的成因與它對 `.infinity` 的 trap 相同：靜默、退出碼 132、沒有訊息。把它夾到一個
    /// 荒謬但有限的數字，會把「只可能來自 bug 的值」變成一張明顯錯誤的畫面，那嚴格優於一個直接
    /// 消失的行程。
    static var columnCountLimit: Double { 10_000 }
    static var columnWidthLimit: Double { 1_000_000 }

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
            // Handed over untouched. Until task #108 this line was
            // `proposedWidth.flatMap { $0.isFinite ? Int($0.rounded(.down)) : nil }`
            // -- both halves of that are gone, but only one of them for a good
            // reason. The truncation is gone because the sizes are `Double` now.
            // The `isFinite` test is NOT gone: it moved one level down to
            // `available`, which is where the `Int` conversions that would trap
            // on it now live. Read the comment there before assuming an infinite
            // proposal is harmless just because nothing converts it here.
            //
            // 原樣傳遞。在任務 #108 之前，這一行是
            // `proposedWidth.flatMap { $0.isFinite ? Int($0.rounded(.down)) : nil }`
            // ——它的兩個部分都不見了，但只有其中一個是有好理由的。截斷之所以消失，是因為尺寸現在
            // 已是 `Double`。而 `isFinite` 測試**並沒有**消失：它下沉了一層，移到 `available`，
            // 也就是那些「會因它而 trap 的 `Int` 轉換」現在所在之處。在因為「此處已無任何轉換」
            // 而認定無限的提案無害之前，請先讀該處的註解。
            proposedWidth: proposedWidth
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
        proposedWidth: Double?
    ) -> GridLayoutPlan {
        // The one line that makes every `Int(_:)` conversion below safe, and the
        // reason `resolve(proposedWidth:)` no longer needs to do anything.
        //
        // `flatMap` with an `isFinite` test, not `map`. `Int(Double)` TRAPS on an
        // infinite or NaN value -- an `Illegal instruction`, exit 132, with no
        // message at all, because it is a language-level trap rather than a Swift
        // precondition (those print).
        //
        // `.infinity` is a real value here, not a theoretical one. The layout
        // system probes children with it deliberately: `LayoutSystem.swift:605`
        // is `let specialSizes: [Double?] = [nil, .infinity]`, `:284` assigns
        // `.infinity` to a proposal component, and `ProposedViewSize.swift:6`
        // declares `.infinity` as a whole size. So any grid inside an ordinary
        // stack gets asked this.
        //
        // Measured 2026-09-08: P51 died 1881 ms after launch, exit 132, with an
        // empty replay log -- it never reached its first log line. P50, the same
        // launcher and PATH, was still running when a 25 s cap killed it; P50 has
        // no `LazyVGrid`.
        //
        // Infinite maps to `nil`, and therefore to `0`, rather than to a large
        // number, because `0` already means the right thing here: it makes
        // `.adaptive` resolve to one column, which is what an unconstrained width
        // should produce. A sentinel like `.greatestFiniteMagnitude` would
        // instead survive into `available + gap` and back into an `Int(_:)`.
        //
        // Widening the sizes to `Double` moved this problem, it did not remove
        // it. An infinite PROPOSAL is handled here; an infinite `maximum` on a
        // column is handled further down, at `clamped`, and by `min(_:_:)`
        // returning its finite operand.
        //
        // 這一行讓底下每一個 `Int(_:)` 轉換都變得安全，也正是 `resolve(proposedWidth:)` 不再需要
        // 做任何事的原因。
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
        // 無限值對應到 `nil`、因而對應到 `0`，而不是對應到某個大數，是因為 `0` 在此已經表達了正確的
        // 意義：它會讓 `.adaptive` 解析為一欄，那正是「寬度無約束」該有的結果。若改用
        // `.greatestFiniteMagnitude` 之類的哨兵值，它反而會存活到 `available + gap`，並再次流入某個
        // `Int(_:)`。
        //
        // 把尺寸放寬為 `Double` 只是**移動**了這個問題，並沒有消除它。無限的**提案**在此處理；欄位上
        // 無限的 `maximum` 則在下方的 `clamped` 處處理，以及靠 `min(_:_:)` 會回傳其有限的那一邊。
        let available = proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? 0

        // Spacing stays `Int` on the way in and on the way out -- it is the
        // caller's `LazyVGrid(spacing:)`, not a `GridItem` size, and task #108
        // widened the sizes. It becomes a `Double` only for the arithmetic in
        // between, so that a fractional share is not rounded on every addition.
        // 間距在進來與出去時都維持 `Int`——它是呼叫端的 `LazyVGrid(spacing:)`，而不是 `GridItem`
        // 的尺寸，而任務 #108 放寬的是尺寸。它只在中間的算式裡成為 `Double`，好讓一個帶小數的
        // 分配額不會在每一次加法時都被四捨五入一次。
        let gap = Double(spacing)

        // A grid with no columns still has to put its children somewhere. One
        // full-width column is what SwiftUI does, and it keeps the modulo
        // arithmetic in LayoutSystem from dividing by zero.
        // 一個沒有任何欄的格線,仍然必須把子節點擺在某處。SwiftUI 的做法是「一個滿寬的欄」,
        // 而那也讓 LayoutSystem 中的取餘數運算不會除以零。
        guard !columns.isEmpty else {
            return GridLayoutPlan(
                columnWidths: [Int(available.rounded())],
                columnOffsets: [0],
                alignments: [alignment],
                spacing: spacing
            )
        }

        // Pass one: how many columns each item becomes, and which of them want a
        // share of what is left after the fixed ones.
        // 第一輪:每個項目會變成幾個欄,以及其中哪些想分配「扣掉固定欄之後」剩下的部分。
        // What an adaptive column may divide is what is LEFT, not the whole
        // container.
        //
        // This used to divide `available`, so a fixed column's width was
        // counted twice -- once by the fixed column and once by the adaptive
        // one filling the same space. Measured by a reviewer against the
        // resolver: 420 pt available, one `.fixed(200)` and one
        // `.adaptive(minimum: 100)` produced 530 pt of columns in a 420 pt
        // container. Nothing overflowed loudly; the last column simply ran off
        // the edge.
        //
        // The gap reserve is one per item rather than one per resulting column,
        // because the adaptive counts are not known yet -- that is the
        // circularity this pass exists inside. It under-reserves when an
        // adaptive item becomes several columns, which costs at most a few
        // points of the share and never overflows, since the second pass clamps
        // each column to its own bounds anyway.
        //
        // adaptive 欄能夠瓜分的,是**剩下**的部分,不是整個容器。
        //
        // 它原本瓜分的是 `available`,因此一個固定欄的寬度被計算了兩次——一次由該固定欄、一次由填滿
        // 同一片空間的 adaptive 欄。某位審查者對照解析器實測:420 點可用寬度、一個 `.fixed(200)` 與
        // 一個 `.adaptive(minimum: 100)`,在一個 420 點的容器中產出了 530 點的欄。沒有任何東西大聲
        // 溢位;只是最後一欄跑出了邊緣。
        //
        // 間距的預留是「每個項目一份」而非「每個最終欄位一份」,因為此時 adaptive 的欄數尚未得知——
        // 那正是這一輪所身處的那個循環依賴。當某個 adaptive 項目展開為數欄時它會預留不足,而代價至多
        // 是分配額中的幾個點、且永遠不會溢位,因為第二輪無論如何都會把每一欄夾在它自身的界限內。
        var fixedWidth = 0.0
        var adaptiveItems = 0
        for column in columns {
            switch column.size {
                case .fixed(let width): fixedWidth += width
                case .adaptive: adaptiveItems += 1
                case .flexible: break
            }
        }
        let reservedGaps = gap * Double(max(0, columns.count - 1))
        let adaptiveSpace = max(0, available - fixedWidth - reservedGaps)
        let spacePerAdaptiveItem =
            adaptiveItems > 0 ? adaptiveSpace / Double(adaptiveItems) : 0

        var counts: [Int] = []
        for column in columns {
            switch column.size {
                case .fixed, .flexible:
                    counts.append(1)
                case .adaptive(let minimum, _):
                    // As many as fit, at least one. The numerator adds one
                    // spacing back because n columns carry n-1 gaps.
                    //
                    // The quotient is clamped BEFORE the `Int` conversion, not
                    // after: `available` is finite by the line above, but a
                    // finite absurd width divided by a minimum of 1 still
                    // produces a quotient past `Int.max`, and `Int(_:)` traps on
                    // that exactly as it does on `.infinity`.
                    //
                    // 塞得下幾個就是幾個,至少一個。分子先加回一份間距,因為 n 個欄之間有 n-1 道空隙。
                    //
                    // 商是在 `Int` 轉換**之前**被夾住的，不是之後：上面那一行已保證 `available` 有限，
                    // 但一個「有限但荒謬」的寬度除以最小值 1，其商仍可能超過 `Int.max`，而 `Int(_:)`
                    // 對此的 trap 方式，與它對 `.infinity` 的完全相同。
                    let fit = (spacePerAdaptiveItem + gap) / (max(minimum, 1) + gap)
                    counts.append(
                        max(1, Int(min(fit, Self.columnCountLimit).rounded(.down)))
                    )
            }
        }

        let totalColumns = counts.reduce(0, +)
        var fixedTotal = 0.0
        var shareCount = 0
        for (index, column) in columns.enumerated() {
            if case .fixed(let width) = column.size {
                fixedTotal += width * Double(counts[index])
            } else {
                shareCount += counts[index]
            }
        }
        let remaining = max(
            0,
            available - gap * Double(max(0, totalColumns - 1)) - fixedTotal
        )
        let share = shareCount > 0 ? remaining / Double(shareCount) : 0

        // Pass two: expand each item into its columns, clamped to its bounds.
        // 第二輪:把每個項目展開為它的各個欄,並夾在其自身的界限內。
        var exactWidths: [Double] = []
        var alignments: [HorizontalAlignment] = []
        for (index, column) in columns.enumerated() {
            let width: Double =
                switch column.size {
                    case .fixed(let fixed):
                        fixed
                    // `min(share, .infinity)` is `share`, so an infinite
                    // `maximum` needs no case of its own -- it simply stops
                    // being an upper bound, which is what it means. No `??` and
                    // no sentinel: that is the whole benefit of spelling "no
                    // maximum" the way SwiftUI does.
                    // `min(share, .infinity)` 就是 `share`，因此無限的 `maximum` 不需要自己的分支
                    // ——它單純地不再構成上界，而那正是它的語意。不需要 `??`、也不需要哨兵值：
                    // 這正是「照 SwiftUI 的方式表達『沒有上限』」所帶來的全部好處。
                    case .flexible(let minimum, let maximum):
                        min(max(share, minimum), maximum)
                    case .adaptive(let minimum, let maximum):
                        min(max(share, minimum), maximum)
                }
            // A column's own numbers are the caller's, and nothing has validated
            // them: `.fixed(.infinity)` and `.adaptive(minimum: .infinity)` both
            // reach here intact, and both would trap at the `Int(_:)` below.
            // Non-finite falls back to the proposal (the same meaning `available`
            // gives an infinite proposal), and the upper clamp keeps a finite but
            // absurd width out of the offset accumulator.
            // 一個欄自身的數值來自呼叫端，而且不曾被驗證過：`.fixed(.infinity)` 與
            // `.adaptive(minimum: .infinity)` 都會原封不動抵達此處，而兩者都會在下方的 `Int(_:)`
            // 處 trap。非有限值退回為那份提案（與 `available` 賦予無限提案的意義相同），而上界的
            // 夾制則讓「有限但荒謬」的寬度進不了位移累加器。
            let clamped = min(
                max(0, width.isFinite ? width : available),
                Self.columnWidthLimit
            )
            exactWidths.append(
                contentsOf: Array(repeating: clamped, count: counts[index])
            )
            alignments.append(
                contentsOf: Array(
                    repeating: column.alignment ?? alignment,
                    count: counts[index]
                )
            )
        }

        // Whole-point columns come from rounding the EDGES, not from rounding
        // each width on its own. `GridLayoutPlan` is integral (see the note on
        // it), so a fractional share has to become integers somewhere, and the
        // two ways of doing it are not equally good:
        //
        //   - round each width: three columns of 33.67 in 101 points become
        //     34 + 34 + 34 = 102 and the last cell hangs over the right edge,
        //     while flooring them gives 33 + 33 + 33 = 99 and drops the
        //     remainder into a gutter -- which is what the `Int` version did.
        //   - round each edge, and take the width as the distance between two
        //     rounded edges: 0..34, 34..67, 67..101. The columns tile exactly,
        //     the remainder is distributed rather than discarded, and no error
        //     accumulates along the row because every offset is computed from
        //     the exact running position `x`, never from the rounded widths.
        //
        // Integer inputs are unaffected: 96 + 8 lands on integers at every step,
        // so P51's `.fixed(96)` and P48's `.adaptive(minimum: 120)` resolve to
        // exactly what they did before. P48's second grid is `.fixed(90.5)`
        // precisely so that one grid in the suite does NOT.
        //
        // 整數點的欄位來自對**邊界**取整，而不是各自對每一個寬度取整。`GridLayoutPlan` 是整數的
        //（見其上的說明），因此帶小數的分配額總得在某處變成整數，而兩種做法的好壞並不相等：
        //
        //   - 對每個寬度取整：101 點中三個 33.67 的欄會變成 34 + 34 + 34 = 102，最後一格因而突出
        //     右緣；而向下取整則得到 33 + 33 + 33 = 99，把餘數丟進一條空隙——那正是 `Int` 版本的
        //     行為。
        //   - 對每個邊界取整，並以「兩個取整後邊界之間的距離」作為寬度：0..34、34..67、67..101。
        //     各欄恰好密合、餘數是被分配而非被丟棄，而且誤差不會沿著一列累積，因為每個位移都是由
        //     精確的累進位置 `x` 算出，從不由取整後的寬度算出。
        //
        // 整數輸入不受影響：96 + 8 在每一步都落在整數上，因此 P51 的 `.fixed(96)` 與 P48 的
        // `.adaptive(minimum: 120)` 解析出來的結果，與先前完全相同。P48 的第二個格線之所以是
        // `.fixed(90.5)`，正是為了讓這套測試中有一個格線**不是**如此。
        var widths: [Int] = []
        var offsets: [Int] = []
        var x = 0.0
        for width in exactWidths {
            let start = Int(x.rounded())
            let end = Int((x + width).rounded())
            offsets.append(start)
            widths.append(max(0, end - start))
            x += width + gap
        }
        return GridLayoutPlan(
            columnWidths: widths,
            columnOffsets: offsets,
            alignments: alignments,
            spacing: spacing
        )
    }
}
