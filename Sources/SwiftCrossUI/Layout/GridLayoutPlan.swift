/// Resolved columns, handed down to whoever actually arranges the cells.
///
/// **It travels in the environment for the same reason ``EnvironmentValues/
/// layoutOverlapsChildren`` does.** ``ForEach`` builds a real container rather
/// than being flattened away, so a `LazyVGrid` whose content is a `ForEach` --
/// which is nearly every one -- sees exactly one child. Arranging that one child
/// in a grid puts every cell in the first column and the `ForEach` then lays its
/// own children out along whatever axis it inherited, which is a vertical list.
/// That is what the first version of this did, and the screenshot showed eight
/// cells stacked one above another with the numbers in the right order, which
/// reads as a grid whose columns are wrong rather than as a grid that never ran.
///
/// The fix is the one the tree already reached for twice: tell `ForEach` how its
/// parent arranges things and let it do the arranging. `layoutOrientation` was
/// the first, `layoutOverlapsChildren` the second when `ZStack` hit the same
/// wall, and this is the third.
///
/// 解析完成的欄位,交給真正負責排列儲存格的那一方。
///
/// **它之所以隨 environment 傳遞,理由與 ``EnvironmentValues/layoutOverlapsChildren`` 完全相同。**
/// ``ForEach`` 會建立一個真正的容器,而不是被攤平消去,因此一個「內容是 `ForEach`」的 `LazyVGrid`
/// ——而那幾乎是全部——只會看到**一個**子節點。把那一個子節點排進格線,會讓每一格都落在第一欄,
/// 接著 `ForEach` 再依它所繼承到的軸向安排自己的子元件,也就是一個垂直清單。本實作的第一版正是如此,
/// 而截圖顯示八格由上而下排成一列、編號順序正確——那讀起來像是「一個欄位算錯的格線」,而不像是
/// 「一個從未執行的格線」。
///
/// 修法就是這棵樹已經採用過兩次的那一個:告訴 `ForEach` 它的父層是怎麼排的,然後讓它自己去排。
/// 第一次是 `layoutOrientation`,第二次是 `ZStack` 撞上同一堵牆時的 `layoutOverlapsChildren`,
/// 而這是第三次。它現在也帶著軸向（見下方 `axis`）。
///
/// **It stayed integral when ``GridItem/Size`` widened to `Double` (task #108),
/// and that is a decision rather than an oversight.** A `GridItem` is what the
/// caller asked for and may be fractional -- `.fixed(100.5)`, or a third of a
/// container. A `GridLayoutPlan` is where the asking stops: every consumer of it
/// hands its numbers to a backend that positions in whole points
/// (`LayoutSystem.commitGridLayout` builds a `SIMD2<Int>` from `laneOffsets`),
/// so widening this type would only move the same rounding downstream, into five
/// backends instead of one resolver. The fractional arithmetic therefore happens
/// entirely inside the resolvers, which round lane EDGES once, at the end -- so
/// the lanes still tile exactly and no remainder is dropped.
///
/// **當 ``GridItem/Size`` 於任務 #108 放寬為 `Double` 時，本型別維持整數，那是一個決定，不是疏漏。**
/// 一個 `GridItem` 是呼叫端所要求的東西，可以帶小數——`.fixed(100.5)`，或容器的三分之一。而
/// `GridLayoutPlan` 是「要求」終止之處：它的每一個消費端都會把其中的數值交給「以整數點定位」的
/// backend（`LayoutSystem.commitGridLayout` 以 `laneOffsets` 建構 `SIMD2<Int>`），因此放寬本型別
/// 只會把同一次取整往下游推——從一個解析器推給五個 backend。所以帶小數的算式完全發生在各個解析器
/// 內部，由它們在最後一次性地對車道**邊界**取整——如此各車道仍然恰好密合，也沒有任何餘數被丟棄。
///
/// **Its vocabulary is "lane" and "line", not "column" and "row", and the rename
/// is what let ``LazyHGrid`` exist (#118).** The two grids are the same
/// algorithm transposed: `LazyVGrid` fixes its COLUMNS and grows downwards,
/// `LazyHGrid` fixes its ROWS and grows rightwards. Written in terms of columns,
/// every one of these fields is a lie in one of the two cases -- a `columnWidth`
/// that holds a row's height reads as a bug at every call site that touches it,
/// and the compiler has nothing to say about it.
///
/// So: a LANE is one of the fixed tracks the caller asked for (a column in a
/// `LazyVGrid`, a row in a `LazyHGrid`), and a LINE is one of the tracks the
/// grid adds as it fills up. ``axis`` says which way the lines run.
///
/// **它的詞彙是「lane(車道)」與「line(行列)」，而不是「column」與「row」，而這次改名正是
/// ``LazyHGrid`` 得以存在的原因(#118)。** 這兩種格線是同一套演算法的轉置:`LazyVGrid` 固定它的
/// **欄**、向下生長;`LazyHGrid` 固定它的**列**、向右生長。若以 column 的詞彙書寫，這裡每一個欄位
/// 在其中一種情況下都是謊話——一個裝著「列高」的 `columnWidth`，在每一個碰到它的呼叫點都讀起來像
/// 是錯誤，而編譯器對此無話可說。
///
/// 因此:一條 **lane** 是呼叫端所要求的固定軌道之一(在 `LazyVGrid` 中是一欄，在 `LazyHGrid` 中是
/// 一列)，而一條 **line** 是格線在填滿時自行增加的軌道之一。``axis`` 說明這些 line 往哪個方向排。
public struct GridLayoutPlan: Equatable, Sendable {
    /// The axis the grid GROWS along: `.vertical` for a ``LazyVGrid``,
    /// `.horizontal` for a ``LazyHGrid``.
    ///
    /// The lanes run across it. Everything else here is expressed in terms of
    /// this, which is why it comes first.
    ///
    /// 格線**生長**的軸向:``LazyVGrid`` 為 `.vertical`，``LazyHGrid`` 為 `.horizontal`。
    ///
    /// 那些 lane 橫越它而排。此處其餘每一項都是依它來表述的，這正是它排在最前面的原因。
    public var axis: Axis

    /// One entry per resolved lane, measured ACROSS ``axis``.
    ///
    /// An adaptive ``GridItem`` contributes several, which is why this is not
    /// the caller's `[GridItem]`.
    ///
    /// 每一條已解析的 lane 各一項，量的是**橫越** ``axis`` 的方向。
    ///
    /// 一個 adaptive 的 ``GridItem`` 會貢獻數項，這正是此處不是呼叫端那份 `[GridItem]` 的原因。
    public var laneSizes: [Int]

    /// The cross-axis offset of each lane, cumulative, including spacing.
    /// 各 lane 在橫軸上的位移，累計值，已含間距。
    public var laneOffsets: [Int]

    /// Per lane, so a `GridItem` can override the grid's own alignment.
    ///
    /// Neutral rather than a ``HorizontalAlignment``: in a `LazyHGrid` a lane is
    /// a row and its cells are aligned vertically. ``resolvedAlignment(forLane:)``
    /// is how a caller gets back to a concrete one.
    ///
    /// 逐 lane 記錄，如此個別 `GridItem` 便能覆寫格線自身的對齊方式。
    ///
    /// 使用中立的表述而非 ``HorizontalAlignment``:在 `LazyHGrid` 中，一條 lane 是一列，而它的
    /// 儲存格是**垂直**對齊的。要取回具體的對齊方式，見 ``resolvedAlignment(forLane:)``。
    public var alignments: [GridLaneAlignment]

    public var spacing: Int

    public init(
        axis: Axis,
        laneSizes: [Int],
        laneOffsets: [Int],
        alignments: [GridLaneAlignment],
        spacing: Int
    ) {
        self.axis = axis
        self.laneSizes = laneSizes
        self.laneOffsets = laneOffsets
        self.alignments = alignments
        self.spacing = spacing
    }

    /// The alignment for a lane, or `.center` when the lane has none.
    ///
    /// Out-of-range indices answer `.center` rather than trapping: the count of
    /// alignments and the count of lanes are resolved separately, and a grid
    /// that vanished because one list was shorter would be a worse failure than
    /// a cell that centred itself.
    ///
    /// 某條 lane 的對齊方式；若該 lane 沒有，則為 `.center`。
    ///
    /// 索引越界時回答 `.center` 而不是 trap:對齊方式的數量與 lane 的數量是分開解析的，而一個
    /// 「因為其中一份清單較短就整個消失」的格線，會是比「一格自行置中」更糟的失效方式。
    public func resolvedAlignment(forLane lane: Int) -> GridLaneAlignment {
        lane >= 0 && lane < alignments.count ? alignments[lane] : .center
    }

    /// The extent the lanes occupy across ``axis``, spacing included.
    ///
    /// A grid is this wide (or tall) whether or not its cells filled it, which
    /// is what keeps two grids with the same lanes the same size.
    ///
    /// 這些 lane 橫越 ``axis`` 所佔的長度，已含間距。
    ///
    /// 無論儲存格有沒有填滿，格線都是這麼寬(或這麼高)——而那正是讓「lane 相同的兩個格線」尺寸也
    /// 相同的原因。
    public var crossAxisExtent: Int {
        laneSizes.reduce(0, +) + spacing * max(0, laneSizes.count - 1)
    }
}

/// Where a cell sits inside its lane, without saying which axis that is.
///
/// Three cases rather than a ``HorizontalAlignment`` and a
/// ``VerticalAlignment``, because the grid arithmetic is identical in both and
/// duplicating it is how the two would drift apart.
///
/// 一格在它的 lane 中的位置，而不說那是哪一個軸。
///
/// 使用三個 case，而不是 ``HorizontalAlignment`` 與 ``VerticalAlignment`` 各一套，因為格線的算式
/// 在兩者中完全相同，而把它複製一份正是讓兩者日後分歧的做法。
public enum GridLaneAlignment: Equatable, Sendable {
    case start
    case center
    case end

    public init(_ alignment: HorizontalAlignment) {
        self =
            switch alignment {
                case .leading: .start
                case .center: .center
                case .trailing: .end
            }
    }

    public init(_ alignment: VerticalAlignment) {
        self =
            switch alignment {
                case .top: .start
                case .center: .center
                case .bottom: .end
            }
    }
}

extension GridLayoutPlan {
    /// Upper bounds that exist to keep `Int(_:)` from trapping, not to express
    /// any layout policy.
    ///
    /// Both are reached only by a value no display can produce -- ten thousand
    /// lanes, or a lane a million points wide. They matter because the sizes
    /// are `Double` since task #108, and `Int(_:)` traps above `Int.max` for the
    /// same language-level reason it traps on `.infinity`: silently, with exit
    /// 132 and no message. Clamping to an absurd-but-finite number turns a value
    /// that could only have come from a bug into a picture that is visibly
    /// wrong, which is strictly better than a process that vanishes.
    ///
    /// 這兩個上界的存在，是為了讓 `Int(_:)` 不要 trap，而不是為了表達任何版面政策。
    ///
    /// 兩者都只會被「任何顯示器都產不出來的值」觸及——一萬條 lane，或一條一百萬點寬的 lane。它們之
    /// 所以重要，是因為自任務 #108 起尺寸型別為 `Double`，而 `Int(_:)` 在超過 `Int.max` 時會 trap，
    /// 其語言層級的成因與它對 `.infinity` 的 trap 相同：靜默、退出碼 132、沒有訊息。把它夾到一個
    /// 荒謬但有限的數字，會把「只可能來自 bug 的值」變成一張明顯錯誤的畫面，那嚴格優於一個直接
    /// 消失的行程。
    static var laneCountLimit: Double { 10_000 }
    static var laneSizeLimit: Double { 1_000_000 }

    /// Turns the caller's items into concrete lanes.
    ///
    /// Takes the proposed cross-axis extent because ``GridItem/Size/adaptive`` turns one
    /// item into a variable number of lanes, so the lane COUNT is not
    /// knowable from the array alone.
    ///
    /// 把呼叫端的項目轉成具體的 lane。
    ///
    /// 必須接收「橫越生長軸的那個被建議長度」,因為 ``GridItem/Size/adaptive`` 會把一個項目變成數量不定的 lane,
    /// 因此 lane 的**數量**無法單憑該陣列得知。
    static func resolve(
        items: [GridItem],
        axis: Axis,
        alignment: GridLaneAlignment,
        spacing: Int,
        proposedCrossExtent: Double?
    ) -> GridLayoutPlan {
        // The one line that makes every `Int(_:)` conversion below safe, and the
        // reason `resolve(proposedCrossExtent:)` no longer needs to do anything.
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
        // `.adaptive` resolve to one lane, which is what an unconstrained width
        // should produce. A sentinel like `.greatestFiniteMagnitude` would
        // instead survive into `available + gap` and back into an `Int(_:)`.
        //
        // Widening the sizes to `Double` moved this problem, it did not remove
        // it. An infinite PROPOSAL is handled here; an infinite `maximum` on a
        // lane is handled further down, at `clamped`, and by `min(_:_:)`
        // returning its finite operand.
        //
        // 這一行讓底下每一個 `Int(_:)` 轉換都變得安全，也正是 `resolve(proposedCrossExtent:)` 不再需要
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
        // 意義：它會讓 `.adaptive` 解析為一 lane ，那正是「寬度無約束」該有的結果。若改用
        // `.greatestFiniteMagnitude` 之類的哨兵值，它反而會存活到 `available + gap`，並再次流入某個
        // `Int(_:)`。
        //
        // 把尺寸放寬為 `Double` 只是**移動**了這個問題，並沒有消除它。無限的**提案**在此處理； lane 上
        // 無限的 `maximum` 則在下方的 `clamped` 處處理，以及靠 `min(_:_:)` 會回傳其有限的那一邊。
        let available = proposedCrossExtent.flatMap { $0.isFinite ? $0 : nil } ?? 0

        // Spacing stays `Int` on the way in and on the way out -- it is the
        // caller's `LazyVGrid(spacing:)`, not a `GridItem` size, and task #108
        // widened the sizes. It becomes a `Double` only for the arithmetic in
        // between, so that a fractional share is not rounded on every addition.
        // 間距在進來與出去時都維持 `Int`——它是呼叫端的 `LazyVGrid(spacing:)`，而不是 `GridItem`
        // 的尺寸，而任務 #108 放寬的是尺寸。它只在中間的算式裡成為 `Double`，好讓一個帶小數的
        // 分配額不會在每一次加法時都被四捨五入一次。
        let gap = Double(spacing)

        // A grid with no lanes still has to put its children somewhere. One
        // full-width lane is what SwiftUI does, and it keeps the modulo
        // arithmetic in LayoutSystem from dividing by zero.
        // 一個沒有任何 lane 的格線,仍然必須把子節點擺在某處。SwiftUI 的做法是「一條佔滿橫軸的 lane 」,
        // 而那也讓 LayoutSystem 中的取餘數運算不會除以零。
        guard !items.isEmpty else {
            return GridLayoutPlan(
                axis: axis,
               laneSizes: [Int(available.rounded())],
               laneOffsets: [0],
                alignments: [alignment],
                spacing: spacing
            )
        }

        // Pass one: how many lanes each item becomes, and which of them want a
        // share of what is left after the fixed ones.
        // 第一輪:每個項目會變成幾條 lane,以及其中哪些想分配「扣掉固定 lane 之後」剩下的部分。
        // What an adaptive lane may divide is what is LEFT, not the whole
        // container.
        //
        // This used to divide `available`, so a fixed lane's width was
        // counted twice -- once by the fixed lane and once by the adaptive
        // one filling the same space. Measured by a reviewer against the
        // resolver: 420 pt available, one `.fixed(200)` and one
        // `.adaptive(minimum: 100)` produced 530 pt of lanes in a 420 pt
        // container. Nothing overflowed loudly; the last lane simply ran off
        // the edge.
        //
        // The gap reserve is one per item rather than one per resulting lane,
        // because the adaptive counts are not known yet -- that is the
        // circularity this pass exists inside. It under-reserves when an
        // adaptive item becomes several lanes, which costs at most a few
        // points of the share and never overflows, since the second pass clamps
        // each lane to its own bounds anyway.
        //
        // adaptive lane 能夠瓜分的,是**剩下**的部分,不是整個容器。
        //
        // 它原本瓜分的是 `available`,因此一個固定 lane 的寬度被計算了兩次——一次由該固定 lane、一次由填滿
        // 同一片空間的 adaptive lane。某位審查者對照解析器實測:420 點可用寬度、一個 `.fixed(200)` 與
        // 一個 `.adaptive(minimum: 100)`,在一個 420 點的容器中產出了 530 點的 lane。沒有任何東西大聲
        // 溢位;只是最後一 lane 跑出了邊緣。
        //
        // 間距的預留是「每個項目一份」而非「每個最終 lane 一份」,因為此時 adaptive 的 lane 數尚未得知——
        // 那正是這一輪所身處的那個循環依賴。當某個 adaptive 項目展開為數 lane 時它會預留不足,而代價至多
        // 是分配額中的幾個點、且永遠不會溢位,因為第二輪無論如何都會把每一 lane 夾在它自身的界限內。
        var fixedWidth = 0.0
        var adaptiveItems = 0
        for item in items {
            switch item.size {
                case .fixed(let width): fixedWidth += width
                case .adaptive: adaptiveItems += 1
                case .flexible: break
            }
        }
        let reservedGaps = gap * Double(max(0, items.count - 1))
        let adaptiveSpace = max(0, available - fixedWidth - reservedGaps)
        let spacePerAdaptiveItem =
            adaptiveItems > 0 ? adaptiveSpace / Double(adaptiveItems) : 0

        var counts: [Int] = []
        for item in items {
            switch item.size {
                case .fixed, .flexible:
                    counts.append(1)
                case .adaptive(let minimum, _):
                    // As many as fit, at least one. The numerator adds one
                    // spacing back because n lanes carry n-1 gaps.
                    //
                    // The quotient is clamped BEFORE the `Int` conversion, not
                    // after: `available` is finite by the line above, but a
                    // finite absurd width divided by a minimum of 1 still
                    // produces a quotient past `Int.max`, and `Int(_:)` traps on
                    // that exactly as it does on `.infinity`.
                    //
                    // 塞得下幾個就是幾個,至少一個。分子先加回一份間距,因為 n 條 lane 之間有 n-1 道空隙。
                    //
                    // 商是在 `Int` 轉換**之前**被夾住的，不是之後：上面那一行已保證 `available` 有限，
                    // 但一個「有限但荒謬」的寬度除以最小值 1，其商仍可能超過 `Int.max`，而 `Int(_:)`
                    // 對此的 trap 方式，與它對 `.infinity` 的完全相同。
                    let fit = (spacePerAdaptiveItem + gap) / (max(minimum, 1) + gap)
                    counts.append(
                        max(1, Int(min(fit, Self.laneCountLimit).rounded(.down)))
                    )
            }
        }

        let totalLanes = counts.reduce(0, +)
        var fixedTotal = 0.0
        var shareCount = 0
        for (index, item) in items.enumerated() {
            if case .fixed(let width) = item.size {
                fixedTotal += width * Double(counts[index])
            } else {
                shareCount += counts[index]
            }
        }
        let remaining = max(
            0,
            available - gap * Double(max(0, totalLanes - 1)) - fixedTotal
        )
        let share = shareCount > 0 ? remaining / Double(shareCount) : 0

        // Pass two: expand each item into its lanes, clamped to its bounds.
        // 第二輪:把每個項目展開為它的各條 lane,並夾在其自身的界限內。
        var exactSizes: [Double] = []
        var alignments: [GridLaneAlignment] = []
        for (index, item) in items.enumerated() {
            let width: Double =
                switch item.size {
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
            // A lane's own numbers are the caller's, and nothing has validated
            // them: `.fixed(.infinity)` and `.adaptive(minimum: .infinity)` both
            // reach here intact, and both would trap at the `Int(_:)` below.
            // Non-finite falls back to the proposal (the same meaning `available`
            // gives an infinite proposal), and the upper clamp keeps a finite but
            // absurd width out of the offset accumulator.
            // 一條 lane 自身的數值來自呼叫端，而且不曾被驗證過：`.fixed(.infinity)` 與
            // `.adaptive(minimum: .infinity)` 都會原封不動抵達此處，而兩者都會在下方的 `Int(_:)`
            // 處 trap。非有限值退回為那份提案（與 `available` 賦予無限提案的意義相同），而上界的
            // 夾制則讓「有限但荒謬」的寬度進不了位移累加器。
            let clamped = min(
                max(0, width.isFinite ? width : available),
                Self.laneSizeLimit
            )
            exactSizes.append(
                contentsOf: Array(repeating: clamped, count: counts[index])
            )
            alignments.append(
                contentsOf: Array(
                    repeating: item.laneAlignment(for: axis) ?? alignment,
                    count: counts[index]
                )
            )
        }

        // Whole-point lanes come from rounding the EDGES, not from rounding
        // each width on its own. `GridLayoutPlan` is integral (see the note on
        // it), so a fractional share has to become integers somewhere, and the
        // two ways of doing it are not equally good:
        //
        //   - round each width: three lanes of 33.67 in 101 points become
        //     34 + 34 + 34 = 102 and the last cell hangs over the right edge,
        //     while flooring them gives 33 + 33 + 33 = 99 and drops the
        //     remainder into a gutter -- which is what the `Int` version did.
        //   - round each edge, and take the width as the distance between two
        //     rounded edges: 0..34, 34..67, 67..101. The lanes tile exactly,
        //     the remainder is distributed rather than discarded, and no error
        //     accumulates along the row because every offset is computed from
        //     the exact running position `x`, never from the rounded widths.
        //
        // Integer inputs are unaffected: 96 + 8 lands on integers at every step,
        // so P51's `.fixed(96)` and P48's `.adaptive(minimum: 120)` resolve to
        // exactly what they did before. P48's second grid is `.fixed(90.5)`
        // precisely so that one grid in the suite does NOT.
        //
        // 整數點的 lane 來自對**邊界**取整，而不是各自對每一個寬度取整。`GridLayoutPlan` 是整數的
        //（見其上的說明），因此帶小數的分配額總得在某處變成整數，而兩種做法的好壞並不相等：
        //
        //   - 對每個寬度取整：101 點中三個 33.67 的 lane 會變成 34 + 34 + 34 = 102，最後一格因而突出
        //     右緣；而向下取整則得到 33 + 33 + 33 = 99，把餘數丟進一條空隙——那正是 `Int` 版本的
        //     行為。
        //   - 對每個邊界取整，並以「兩個取整後邊界之間的距離」作為寬度：0..34、34..67、67..101。
        //     各 lane 恰好密合、餘數是被分配而非被丟棄，而且誤差不會沿著一列累積，因為每個位移都是由
        //     精確的累進位置 `x` 算出，從不由取整後的寬度算出。
        //
        // 整數輸入不受影響：96 + 8 在每一步都落在整數上，因此 P51 的 `.fixed(96)` 與 P48 的
        // `.adaptive(minimum: 120)` 解析出來的結果，與先前完全相同。P48 的第二個格線之所以是
        // `.fixed(90.5)`，正是為了讓這套測試中有一個格線**不是**如此。
        var sizes: [Int] = []
        var offsets: [Int] = []
        var x = 0.0
        for size in exactSizes {
            let start = Int(x.rounded())
            let end = Int((x + size).rounded())
            offsets.append(start)
            sizes.append(max(0, end - start))
            x += size + gap
        }
        return GridLayoutPlan(
            axis: axis,
           laneSizes: sizes,
           laneOffsets: offsets,
            alignments: alignments,
            spacing: spacing
        )
    }
}
