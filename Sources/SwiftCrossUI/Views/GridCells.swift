/// Opt-in for view types that stand for SEVERAL grid cells rather than one.
///
/// ``LazyVGrid`` has to know how many cells its content holds before it can flow
/// them into columns, and a `@ViewBuilder` block does not hand that over: it
/// hands over one value, a `TupleViewN` or a ``ForEach``, whose children are
/// reachable only if the type says how. This protocol is that "how", and only
/// the container types implement it -- everything else is one cell, which is the
/// default in ``gridCells(of:)`` rather than a conformance anybody has to write.
///
/// Modelled on ``View/_asMenuItems``, which solves the identical problem for
/// ``Menu`` and is the only other value-level flattener in the project. The
/// difference is that `_asMenuItems` is a requirement on ``View`` itself with a
/// default that recurses into `body`; this is a separate protocol reached by a
/// conditional cast, so a view that does not adopt it stays one cell instead of
/// recursing into an `EmptyView` body and vanishing.
///
/// **This is not a grid layout.** It flattens values before layout runs, so the
/// cells it produces are laid out by ordinary stacks and share none of a real
/// grid's column measurement. See ``Grid`` for what that costs.
///
/// 讓「代表**多個**網格儲存格、而非單一儲存格」的 view 型別選擇性加入的協定。
///
/// ``LazyVGrid`` 必須先知道其內容共有多少個儲存格，才能把它們流排成欄，而 `@ViewBuilder` 區塊並不
/// 交出這項資訊：它交出的是**一個**值——一個 `TupleViewN` 或一個 ``ForEach``——其子項唯有在型別
/// 主動說明時才取得到。本協定就是那個「說明」，且只有容器型別會實作它；其餘一切都是一個儲存格，
/// 而那是 ``gridCells(of:)`` 中的預設行為，不需要任何人去寫一份 conformance。
///
/// 其設計仿照 ``View/_asMenuItems``——後者為 ``Menu`` 解決了完全相同的問題，也是本專案中唯一另一個
/// 值層級的攤平機制。差別在於：`_asMenuItems` 是 ``View`` 自身的一項需求，其預設實作會遞迴進入
/// `body`；而此處是一個以條件轉型抵達的獨立協定，因此未採用它的 view 會維持為一個儲存格，而不會
/// 遞迴進入 `EmptyView` 的 body 後憑空消失。
///
/// **這不是網格版面演算法。** 它在版面計算開始前就把值攤平，因此它產出的儲存格是由一般的 stack
/// 來排版的，完全不具備真正網格所做的欄寬量測。那樣的代價，見 ``Grid``。
@MainActor
protocol GridCellsProviding {
    /// This view's contribution to the enclosing grid, in order.
    /// 本 view 對外層網格的貢獻，依序排列。
    var _gridCells: [AnyView] { get }
}

/// The flat list of cells a view contributes to a grid.
///
/// The default -- one cell -- is deliberately here rather than in a `View`
/// extension. A view that has not opted in is a leaf as far as a grid is
/// concerned, and that has to stay true for user-defined views, whose `body` a
/// grid must not look inside: flowing somebody's custom view's internals into
/// separate columns would take a single control apart.
///
/// 一個 view 對網格所貢獻的儲存格平坦列表。
///
/// 預設值——單一儲存格——刻意寫在此處，而非寫成 `View` 的 extension。就網格而言，未選擇加入的 view
/// 就是一個葉節點，而這一點對使用者自訂的 view 必須同樣成立：網格不可以窺看它們的 `body`，因為把
/// 別人自訂 view 的內部結構流排到不同的欄裡，等於把單一控制項拆散。
@MainActor
func gridCells(of view: any View) -> [AnyView] {
    if let provider = view as? any GridCellsProviding {
        return provider._gridCells
    }
    return [AnyView(view)]
}

// MARK: - Containers that the view builder itself produces

extension EmptyView: GridCellsProviding {
    /// No cells, not one empty cell. An `if` with no `else` must not leave a
    /// hole that shifts every later cell into the wrong column.
    /// 零個儲存格，而不是一個空白儲存格。沒有 `else` 的 `if` 不可以留下一個空洞，把其後每一個儲存格
    /// 都擠到錯誤的欄位去。
    var _gridCells: [AnyView] { [] }
}

extension AnyView: GridCellsProviding {
    var _gridCells: [AnyView] { gridCells(of: child) }
}

extension Group: GridCellsProviding {
    /// Transparent, exactly as it is to the layout system. A ``Group`` exists to
    /// let modifiers apply to several views at once, not to make them one cell.
    /// 與它對版面系統的作用完全一致：透明。``Group`` 的存在是為了讓 modifier 一次套用到多個 view，
    /// 而不是為了把它們合併成一個儲存格。
    var _gridCells: [AnyView] { gridCells(of: body) }
}

extension OptionalView: GridCellsProviding {
    var _gridCells: [AnyView] {
        guard let view else { return [] }
        return gridCells(of: view)
    }
}

extension EitherView: GridCellsProviding {
    var _gridCells: [AnyView] {
        switch storage {
            case .a(let a): gridCells(of: a)
            case .b(let b): gridCells(of: b)
        }
    }
}

extension ForEach: GridCellsProviding where Child: View {
    /// The case that matters most: a grid's content is almost always a single
    /// ``ForEach``, so without this one conformance a `LazyVGrid` would flow
    /// every data-driven grid into a single column.
    ///
    /// 最要緊的情形：網格的內容幾乎總是單一個 ``ForEach``，因此少了這一份 conformance，`LazyVGrid`
    /// 會把所有由資料驅動的網格全部流排成單獨一欄。
    var _gridCells: [AnyView] {
        elements.flatMap { gridCells(of: child($0)) }
    }
}

// MARK: - TupleView arities
//
// One conformance per arity, because `TupleViewN` is what `@ViewBuilder` builds
// from a literal block of views and there is no variadic way to reach `view0`
// through `viewN`.
//
// **These must cover every arity the view builder can produce.** The ceiling is
// `maximum_view_count` in `TupleView.swift.gyb`, which is 20; if that number
// ever rises, an unlisted `TupleView21` does not fail to compile -- it silently
// becomes a single cell, and a twenty-one-view grid collapses into one column
// with nothing pointing at why. Written out by hand rather than generated
// because this file is not gyb-managed; the sync hazard is the price, and
// naming it here is the mitigation.
//
// 每個元數各一份 conformance，因為 `TupleViewN` 正是 `@ViewBuilder` 由一段字面的 view 區塊所建構出
// 來的型別，而沒有任何 variadic 的方式可以取到 `view0` 到 `viewN`。
//
// **這些必須涵蓋 view builder 能產生的每一個元數。** 上限是 `TupleView.swift.gyb` 中的
// `maximum_view_count`，其值為 20；若該數字日後調高，未列出的 `TupleView21` 並不會編譯失敗——它會
// 靜默地變成單一儲存格，使一個二十一個 view 的網格塌縮成一欄，且沒有任何線索指向原因。此處以手寫
// 而非產生的方式撰寫，因為本檔案不由 gyb 管理；同步風險是其代價，而在此明白指出它就是其緩解措施。

extension TupleView1: GridCellsProviding {
    var _gridCells: [AnyView] {
        gridCells(of: view0)
    }
}

extension TupleView2: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView3: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView4: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2, view3]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView5: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2, view3, view4]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView6: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2, view3, view4, view5]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView7: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2, view3, view4, view5, view6]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView8: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [view0, view1, view2, view3, view4, view5, view6, view7]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView9: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView10: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView11: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView12: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView13: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView14: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView15: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView16: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14, view15,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView17: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14, view15, view16,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView18: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14, view15, view16, view17,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView19: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14, view15, view16, view17, view18,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}

extension TupleView20: GridCellsProviding {
    var _gridCells: [AnyView] {
        let views: [any View] = [
            view0, view1, view2, view3, view4, view5, view6, view7, view8, view9,
            view10, view11, view12, view13, view14, view15, view16, view17, view18,
            view19,
        ]
        return views.flatMap { gridCells(of: $0) }
    }
}
