/// A grid that fills its rows top to bottom and then moves right.
///
/// The transpose of ``LazyVGrid``, and deliberately not a copy of it: the two
/// share ``GridLayoutPlan/resolve(items:axis:alignment:spacing:proposedCrossExtent:)``
/// and the whole of `LayoutSystem`'s grid arithmetic, and differ only in which
/// axis they pin. That sharing is what task #118 was actually about -- the plan
/// used to be written in terms of `columnWidths`, and a horizontal grid built on
/// it would have had to store a row's height in a field called a width.
///
/// ```swift
/// LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))]) {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// ```
///
/// **"Lazy" is the SwiftUI spelling, not a claim about this implementation** --
/// see ``LazyVGrid`` for the whole of that argument, which applies unchanged.
///
/// 一個由上而下填滿各列、滿了就往右移的格線。
///
/// 它是 ``LazyVGrid`` 的轉置，而且刻意**不是**它的複製品:兩者共用
/// ``GridLayoutPlan/resolve(items:axis:alignment:spacing:proposedCrossExtent:)``
/// 以及 `LayoutSystem` 中全部的格線算式，差別只在於它們釘住哪一個軸。這份共用正是任務 #118 真正
/// 的內容——該計畫過去是以 `columnWidths` 的詞彙書寫的，而一個建立於其上的水平格線，將不得不把
/// 「一列的高度」存進一個名為「寬度」的欄位裡。
///
/// **「Lazy」是 SwiftUI 的拼法，不是對本實作的宣稱**——完整的理由見 ``LazyVGrid``，該段原封不動
/// 地適用於此。
public struct LazyHGrid<Content: View>: View {
    static var defaultSpacing: Int { 10 }

    public var body: Content
    private let rows: [GridItem]
    private let alignment: VerticalAlignment
    private let spacing: Int

    /// Creates a horizontal grid.
    ///
    /// - Parameters:
    ///   - rows: The lanes. A `GridItem`'s ``GridItem/verticalAlignment`` is the
    ///     one that applies here; its ``GridItem/alignment`` is the `LazyVGrid`
    ///     half and is ignored.
    ///   - alignment: How a cell sits in its row when the row does not say.
    ///   - spacing: Between the rows, and between the columns the grid adds as
    ///     it fills up -- one value for both, exactly as ``LazyVGrid`` uses one.
    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.rows = rows
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
        let plan = resolve(proposedHeight: proposedSize.height)
        let layoutable = layoutableChildren(backend: backend, children: children)

        // One child means the grid arranges nothing itself: that child is a
        // ForEach or a Group, it consumed the plan, and what it reports is the
        // size of the whole grid. ``LazyVGrid`` carries the full account of what
        // goes wrong when this branch is missing; the only difference here is
        // which axis the mistake shows up on.
        // 只有一個子節點，表示這個格線自己並不排列任何東西:那個子節點是 ForEach 或 Group、它已經
        // 消費了該計畫，而它回報的是整個格線的尺寸。少了這個分支會出什麼事，``LazyVGrid`` 有完整
        // 的記載;此處唯一的差別，只是那個錯誤會顯現在哪一個軸上。
        if layoutable.count == 1 {
            let childResult = layoutable[0].computeLayout(
                proposedSize: ProposedViewSize(nil, Double(plan.crossAxisExtent)),
                environment: environment.with(\.layoutGridPlan, plan)
            )
            return ViewLayoutResult(
                size: ViewSize(childResult.size.width, Double(plan.crossAxisExtent)),
                childResults: [childResult]
            )
        }

        return LayoutSystem.computeGridLayout(
            children: layoutable,
            plan: plan,
            environment: environment.with(\.layoutGridPlan, plan),
            // The children here ARE the cells -- a tuple of views rather than a
            // single ForEach -- so the plan must not reach one level further.
            // 此處的子節點**就是**儲存格——是一組 tuple 的 view，而非單一個 ForEach——因此該計畫
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
        let plan = resolve(proposedHeight: layout.size.height)
        let layoutable = layoutableChildren(backend: backend, children: children)

        if layoutable.count == 1 {
            let childResult = layoutable[0].commit()
            backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
            backend.setSize(
                of: widget,
                to: SIMD2(
                    Int(childResult.size.width.rounded(.up)),
                    plan.crossAxisExtent
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

    func resolve(proposedHeight: Double?) -> GridLayoutPlan {
        GridLayoutPlan.resolve(
            items: rows,
            // The lanes are the ROWS and the lines grow rightwards. That one
            // word is the whole difference from ``LazyVGrid``.
            // lane 就是那些**列**，而 line 向右生長。這一個詞就是它與 ``LazyVGrid`` 的全部差異。
            axis: .horizontal,
            alignment: GridLaneAlignment(alignment),
            spacing: spacing,
            proposedCrossExtent: proposedHeight
        )
    }
}
