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

    /// How a cell sits in this item's lane when the lane is a COLUMN, which is
    /// the ``LazyVGrid`` case.
    /// 當這個項目的 lane 是一**欄**時（也就是 ``LazyVGrid`` 的情況），儲存格在其中如何擺放。
    public var alignment: HorizontalAlignment?

    /// How a cell sits in this item's lane when the lane is a ROW, which is the
    /// ``LazyHGrid`` case.
    ///
    /// **A second property rather than widening ``alignment``, because the two
    /// grids ask different questions of the same item.** In a `LazyVGrid` an
    /// item is a column and only a horizontal alignment means anything; in a
    /// `LazyHGrid` it is a row and only a vertical one does. SwiftUI collapses
    /// both into one `Alignment?` and reads the component that applies; this
    /// tree already shipped `alignment` as a `HorizontalAlignment?`, and
    /// changing its type would break every existing call site to express
    /// something no caller can use in both grids anyway.
    ///
    /// 這是**第二個**屬性，而不是把 ``alignment`` 放寬——因為這兩種格線對同一個項目問的是不同的
    /// 問題。在 `LazyVGrid` 中一個項目是一欄，只有水平對齊有意義；在 `LazyHGrid` 中它是一列，
    /// 只有垂直對齊有意義。SwiftUI 把兩者併成一個 `Alignment?` 並讀取適用的那個分量；而這棵樹
    /// 早已把 `alignment` 以 `HorizontalAlignment?` 發布出去，改變它的型別會弄壞每一個既有呼叫點，
    /// 換來的還是一個「任何呼叫端都無法在兩種格線中共用」的東西。
    public var verticalAlignment: VerticalAlignment?

    public init(
        _ size: Size = .flexible(),
        spacing: Int? = nil,
        alignment: HorizontalAlignment? = nil,
        verticalAlignment: VerticalAlignment? = nil
    ) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }

    /// Whichever alignment applies to a grid growing along `axis`, or `nil` to
    /// take the grid's own.
    /// 對「沿著 `axis` 生長的格線」而言適用的那個對齊方式；若為 `nil`，則採用格線本身的。
    func laneAlignment(for axis: Axis) -> GridLaneAlignment? {
        switch axis {
            case .vertical: alignment.map(GridLaneAlignment.init)
            case .horizontal: verticalAlignment.map(GridLaneAlignment.init)
        }
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
        plan.crossAxisExtent
    }

    func resolve(proposedWidth: Double?) -> GridLayoutPlan {
        GridLayoutPlan.resolve(
            items: columns,
            // The lanes are the COLUMNS and the lines grow downwards, which is
            // the whole of what makes this a `LazyVGrid` rather than a
            // ``LazyHGrid``. Everything below this line is shared between them.
            // lane 就是那些**欄**，而 line 向下生長——這正是「本型別是 `LazyVGrid` 而不是
            // ``LazyHGrid``」的全部內容。這一行以下的每一件事，兩者都是共用的。
            axis: .vertical,
            alignment: GridLaneAlignment(alignment),
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
            proposedCrossExtent: proposedWidth
        )
    }
}
