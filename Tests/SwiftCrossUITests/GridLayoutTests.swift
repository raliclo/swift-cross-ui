import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Grid column resolution")
struct GridLayoutTests {
    /// The case a reviewer measured against the resolver on 2026-09-09: an
    /// adaptive column divided the WHOLE container instead of what a fixed
    /// column had left, so 420 points of container produced 530 points of
    /// columns.
    ///
    /// Nothing overflowed loudly. The last column simply ran off the edge, which
    /// on a backend that clips looks like a missing item and on one that does
    /// not looks like a layout that is merely wide.
    ///
    /// 某位審查者於 2026-09-09 對照解析器實測的案例:一個 adaptive 欄瓜分的是**整個**容器,而不是
    /// 固定欄留下的部分,於是 420 點的容器產出了 530 點的欄。
    ///
    /// 沒有任何東西大聲溢位。只是最後一欄跑出了邊緣——在會裁切的 backend 上那看起來像是少了一個項目,
    /// 在不裁切的 backend 上則看起來只是版面偏寬。
    @MainActor
    @Test("An adaptive column divides what a fixed column leaves")
    func adaptiveDoesNotDoubleCountFixedWidth() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [
                GridItem(.fixed(200)),
                GridItem(.adaptive(minimum: 100)),
            ],
            alignment: .leading,
            spacing: 0,
            proposedWidth: 420
        )

        let total = plan.columnWidths.reduce(0, +)
        #expect(
            total <= 420,
            "columns total \(total) in a 420 point container: \(plan.columnWidths)"
        )
        #expect(plan.columnWidths.first == 200, "the fixed column keeps its width")
    }

    // The four tests below were written on the Windows side, the same morning,
    // as a separate `LazyVGridTests` suite, before a fetch showed this file
    // already existed. The duplicate case -- fixed beside adaptive, which is the
    // one above -- was dropped, and these four were folded in rather than left
    // in a second file about the same subject. Two suites over one function
    // drift, and the flow.md rule about exactly that was written the same day
    // after the same collision in flow.md itself.
    //
    // 下面四項測試是在 Windows 側於同一個早晨、作為另一個獨立的 `LazyVGridTests` suite 寫成的，
    // 當時尚未 fetch，因而不知道本檔已經存在。重複的那一項——「固定欄旁的 adaptive 欄」，也就是上方
    // 那一項——已被捨棄，其餘四項則併入此處，而不是留在另一個談論同一主題的檔案裡。
    // **兩個 suite 覆蓋同一個函式必然會漂移**，而 flow.md 中關於這件事的規則，正是在同一天、因為
    // flow.md 自己發生了同樣的撞車而寫下的。

    /// The control for the case above. With no fixed column there is nothing to
    /// subtract, so this arithmetic was already right before the fix -- and if
    /// it ever fails, the fix broke the simple case rather than the mixed one.
    /// 上一項的**對照組**。沒有固定欄就沒有東西需要扣除，因此這段算術在修正之前就已經是對的；
    /// 若它哪天失敗了，代表被修壞的是簡單情形，而不是混合情形。
    @MainActor
    @Test("An adaptive column alone fills the container and does not exceed it")
    func adaptiveAloneFits() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [GridItem(.adaptive(minimum: 100))],
            alignment: .leading,
            spacing: 10,
            proposedWidth: 420
        )
        let total = plan.columnWidths.reduce(0, +)
            + 10 * max(0, plan.columnWidths.count - 1)
        #expect(total <= 420, "columns total \(total): \(plan.columnWidths)")
        #expect(plan.columnWidths.allSatisfy { $0 >= 100 })
    }

    /// The obvious WRONG fix for the overflow is to let the share fall below the
    /// minimum: the total then fits, and `.adaptive(minimum:)` quietly stops
    /// meaning anything. This test is what rules that out, and it has to be read
    /// together with the overflow test -- either one alone is satisfied by a fix
    /// that is wrong in the other direction.
    /// 針對該溢出，顯而易見的**錯誤**修法是讓分配額低於最小值：總寬因此「符合」，而
    /// `.adaptive(minimum:)` 也就悄悄地不再具有任何意義。這一項測試正是用來排除那種修法的，而它
    /// **必須與溢出那一項一起讀**——任一項單獨存在時，都會被一個「錯在另一個方向」的修正所滿足。
    @MainActor
    @Test("Every adaptive column still honours its minimum")
    func adaptiveColumnsKeepTheirMinimum() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [GridItem(.fixed(200)), GridItem(.adaptive(minimum: 100))],
            alignment: .leading,
            spacing: 10,
            proposedWidth: 420
        )
        for width in plan.columnWidths.dropFirst() {
            #expect(width >= 100, "adaptive column resolved to \(width), below its minimum")
        }
    }

    /// Guards task #112. `Int(Double)` TRAPS on `.infinity` -- an Illegal
    /// instruction, exit 132, with no message, because it is a language-level
    /// trap rather than a precondition. The layout system probes children with
    /// an infinite proposal deliberately, so this is a real input, and P51 died
    /// 1881 ms after launch to prove it. Kept next to the overflow tests because
    /// they touch the same arithmetic.
    /// 守住任務 #112。`Int(Double)` 遇到 `.infinity` 會**trap**——Illegal instruction、退出碼 132、
    /// 沒有任何訊息，因為那是語言層級的 trap 而非 precondition。版面系統會**刻意**用無限提案去探測
    /// 子節點，因此那是真實的輸入；P51 曾於啟動後 1881 毫秒死亡以資證明。放在溢出測試旁邊，是因為
    /// 兩者動到的是同一段算術。
    @MainActor
    @Test("An infinite proposal does not trap")
    func infiniteProposalIsSafe() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [GridItem(.fixed(200)), GridItem(.adaptive(minimum: 100))],
            alignment: .leading,
            spacing: 10,
            proposedWidth: .infinity
        )
        #expect(!plan.columnWidths.isEmpty)
    }

    /// A grid with no columns still has to put its children somewhere, and one
    /// full-width column is both what SwiftUI does and what keeps the modulo
    /// arithmetic in `LayoutSystem` from dividing by zero.
    /// 一個沒有任何欄的格線仍然必須把子節點擺在某處；「一個滿寬的欄」既是 SwiftUI 的做法，也是讓
    /// `LayoutSystem` 中的取餘數運算不會除以零的原因。
    @MainActor
    @Test("No columns still yields one full-width column")
    func emptyColumnsYieldOne() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [],
            alignment: .leading,
            spacing: 10,
            proposedWidth: 420
        )
        #expect(plan.columnWidths == [420])
    }

    /// Spacing counts too, and it is the half that is easy to drop when the
    /// first half is fixed.
    /// 間距同樣要算,而當前半段是固定寬度時,那是最容易被漏掉的一半。
    @MainActor
    @Test("Spacing between columns stays inside the container")
    func adaptiveRespectsSpacing() {
        let plan = LazyVGrid<EmptyView>.resolve(
            columns: [
                GridItem(.fixed(200)),
                GridItem(.adaptive(minimum: 100)),
            ],
            alignment: .leading,
            spacing: 20,
            proposedWidth: 420
        )

        let widths = plan.columnWidths.reduce(0, +)
        let gaps = 20 * max(0, plan.columnWidths.count - 1)
        #expect(
            widths + gaps <= 420,
            "columns \(plan.columnWidths) plus \(gaps) of spacing exceed 420"
        )
    }

    /// A static cell beside a `ForEach` collapses the whole `ForEach` into one
    /// cell.
    ///
    /// `LazyVGrid` decides what to do by counting its DIRECT children: one means
    /// "that child owns the cells, hand it the plan", more than one means "these
    /// children ARE the cells". `TupleView.layoutableChildren` returns exactly
    /// one entry per view and does not flatten, so `Text(…)` beside
    /// `ForEach(…)` is two children -- and the entire ForEach becomes a single
    /// cell whose contents fall back to stack layout, because the plan is
    /// cleared for children in that branch.
    ///
    /// SwiftUI flattens: the ForEach's elements each become cells.
    ///
    /// **Attempted on 2026-09-09 and reverted, and the reason is measured.**
    ///
    /// The obvious fix is to let the grid ask each direct child "are you a group
    /// of cells?" and splice in the answer. That was built --
    /// `ErasedViewGraphNode.getChildren()`, a `cellChildren` requirement on
    /// `ViewGraphNodeChildren` defaulting to nil, and `ForEachViewChildren`
    /// answering with its `layoutableChildren`. It compiled, the suite stayed
    /// green, and this test still recorded its known issue.
    ///
    /// A probe said why:
    ///
    ///     PROBE node 0 type Text      cellChildren: nil
    ///     PROBE node 1 type ForEach<> cellChildren: Optional(0)
    ///
    /// **Empty, not absent.** `ForEachViewChildren.layoutableChildren` is filled
    /// during the ForEach's OWN layout, and the parent asks before that has
    /// happened. So the splice contributed nothing and the ForEach was dropped
    /// entirely -- strictly worse than treating it as one cell, and invisible
    /// without a test, because a grid with fewer cells still lays out.
    ///
    /// Fixing it means populating those children when the children object is
    /// CONSTRUCTED rather than when it is laid out, and the elements needed for
    /// that live on the view rather than on the children. That is a change to
    /// ForEach's lifecycle.
    ///
    /// Kept as a known issue: it records the defect, and it fails the day
    /// someone fixes it -- which is the failure that should happen. It also now
    /// records one route that does NOT work, which is the part that would
    /// otherwise be rediscovered.
    ///
    /// **2026-09-09 嘗試過並已還原,而理由是量出來的。**
    ///
    /// 顯而易見的修法,是讓格線逐一詢問每個直接子節點「你是一組儲存格嗎?」並把答案接進去。那個做法
    /// 被實作出來了——`ErasedViewGraphNode.getChildren()`、`ViewGraphNodeChildren` 上一個預設為 nil 的
    /// `cellChildren` requirement,以及 `ForEachViewChildren` 以它的 `layoutableChildren` 作答。
    /// 它編譯通過、測試全綠,而這個測試依然記錄了它的 known issue。
    ///
    /// 一個探針說出了原因:
    ///
    ///     PROBE node 0 type Text      cellChildren: nil
    ///     PROBE node 1 type ForEach<> cellChildren: Optional(0)
    ///
    /// **是空的,不是不存在。** `ForEachViewChildren.layoutableChildren` 是在該 ForEach **自己的**
    /// layout 期間才被填入的,而父層是在那之前詢問的。因此那次拼接什麼也沒貢獻,ForEach 被整個丟掉——
    /// 嚴格來說比「當成一格」更糟,而且沒有測試就看不見,因為一個少了幾格的格線照樣排得出版面。
    ///
    /// 要修好它,意味著在該 children 物件**被建構時**就填入那些子項,而不是在它被排版時;而做那件事
    /// 所需要的 elements 存在於 view 上、不在 children 上。那是對 ForEach 生命週期的改動。
    ///
    /// 保留為 known issue:它記錄了這個缺陷,並且會在有人修好它的那天失敗——那正是應該發生的失敗。
    /// 它現在同時記錄了一條**行不通**的路線,而那正是否則會被重新發現一次的部分。
    ///
    /// 一個靜態儲存格擺在 `ForEach` 旁邊時,整個 `ForEach` 會塌縮成一格。
    ///
    /// `LazyVGrid` 是以「數**直接**子節點」來決定行為的:一個代表「那個子節點擁有這些儲存格,把計畫交
    /// 給它」,多於一個代表「這些子節點**就是**儲存格」。而 `TupleView.layoutableChildren` 對每個 view
    /// 恰好回傳一個項目、不做攤平,因此 `Text(…)` 擺在 `ForEach(…)` 旁邊就是兩個子節點——於是整個
    /// ForEach 成為單一格,其內容退回 stack 排版,因為那個分支會為子節點清掉計畫。
    ///
    /// SwiftUI 會攤平:ForEach 的每個元素各自成為一格。
    ///
    /// **標記為已知問題,而非在此修正。** 修法需要讓格線能問子節點「你是一組儲存格嗎?」,而
    /// `LayoutSystem.LayoutableChild` 是一對不透明的閉包,回答不了。那是「子節點如何被攤平」的改動,
    /// 不是這個檔案的改動,而它作為一項被釘住的事實,價值高於一次未經驗證的嘗試。當有人真的修好它時,
    /// 這個測試會失敗——而那正是應該發生的失敗。
    @MainActor
    @Test("A static cell beside a ForEach collapses it into one cell")
    func staticCellBesideForEachCollapsesIt() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        func height(of view: some View) -> Double {
            let node = ViewGraphNode(for: view, backend: backend, environment: environment)
            let result = node.computeLayout(
                proposedSize: ProposedViewSize(400, nil),
                environment: environment
            )
            _ = node.commit()
            return result.size.height
        }

        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        // Four cells in two columns is two rows.
        // 兩欄裝四格,就是兩列。
        let fourViaForEach = LazyVGrid(columns: columns) {
            ForEach([0, 1, 2, 3], id: \.self) { Text("\($0)") }
        }

        // One static cell plus three from a ForEach is also four cells, so it
        // should also be two rows.
        // 一個靜態儲存格加上 ForEach 的三個,同樣是四格,因此也應該是兩列。
        let oneStaticPlusThree = LazyVGrid(columns: columns) {
            Text("static")
            ForEach([1, 2, 3], id: \.self) { Text("\($0)") }
        }

        withKnownIssue("a ForEach beside a static cell is treated as one cell") {
            #expect(
                height(of: oneStaticPlusThree) == height(of: fourViaForEach),
                "mixed \(height(of: oneStaticPlusThree)) vs all-ForEach \(height(of: fourViaForEach))"
            )
        }
    }
}
