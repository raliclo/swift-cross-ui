import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Testing for ForEach")
struct ForEachTests {
    @MainActor
    @Test("Duplicate ids", .bug("https://github.com/moreSwift/swift-cross-ui/issues/456"))
    func duplicateIds() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        let view = ForEach([1, 1], id: \.self) { x in
            Text("\(x)")
        }

        let node = ViewGraphNode(for: view, backend: backend, environment: environment)
        _ = node.computeLayout(
            proposedSize: .unspecified,
            environment: environment
        )
        // This will crash if the duplicate identifiers bug happens
        _ = node.commit()

        // Re-layout the view, because the nature of the duplicate handling bug changed
        // depending on the existing set of nodes before the update
        _ = node.computeLayout(
            with: view,
            proposedSize: .unspecified,
            environment: environment
        )
        _ = node.commit()
    }

    @MainActor
    @Test("An empty ForEach with a sibling after it")
    func emptyForEachFollowedBySibling() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        // Reported by a downstream consumer on 2026-09-08: an empty ForEach
        // crashes on the first frame whenever it is NOT the last child of its
        // container. Same data, move it to last and the crash goes; put a
        // sibling after it and it dies in `ViewGraphNode.widget`, on the
        // `_widget!`.
        //
        // **NONE of the shapes below reproduces it**, on DummyBackend here or on
        // AppKitBackend in a running app. So this test does not pin the reported
        // bug; it pins six shapes that are known NOT to have it, which is what
        // makes the next report able to say "not one of these". Kept, and
        // labelled, rather than deleted -- a test that was written to catch
        // something and does not is worth more as a recorded negative than as a
        // silently removed file.
        //
        // Both orders are here, because "it crashes" and "it crashes only in
        // this position" are different claims and only the second one points at
        // the cause.
        //
        // 由下游使用者於 2026-09-08 回報:一個空的 ForEach 只要**不是**其容器的最後一個子項,就會在
        // 第一幀崩潰。相同的資料,把它移到最後就不會崩;在它後面放一個兄弟節點,它就會死在
        // `ViewGraphNode.widget` 的 `_widget!` 上。
        //
        // **以下沒有任何一種形狀能重現它**——在此處的 DummyBackend 上不行,在一支執行中的 app 以
        // AppKitBackend 執行也不行。因此這個測試並未釘住那個被回報的缺陷;它釘住的是六種**已知不具有**
        // 該缺陷的形狀,而那正是讓下一份回報能夠說出「不是這其中任何一個」的東西。予以保留並加註,
        // 而非刪除——一個「為了抓某件事而寫、卻沒抓到」的測試,作為一筆被記錄下來的否定結果,
        // 價值高於一個被靜默移除的檔案。
        //
        // 兩種順序都放在這裡,因為「它會崩潰」與「它只在這個位置崩潰」是兩個不同的主張,而只有後者
        // 指向成因。
        let empty: [Int] = []

        let sibling​Last = VStack {
            Text("before")
            ForEach(empty, id: \.self) { x in
                Text("\(x)")
            }
        }
        let node1 = ViewGraphNode(for: sibling​Last, backend: backend, environment: environment)
        _ = node1.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node1.commit()

        let siblingAfter = VStack {
            ForEach(empty, id: \.self) { x in
                Text("\(x)")
            }
            Text("after")
        }
        let node2 = ViewGraphNode(for: siblingAfter, backend: backend, environment: environment)
        _ = node2.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node2.commit()

        // The same shape in the other containers a consumer is likely to have
        // reached for. The report named none of them, so all of them are tried
        // rather than the one that happened to come to mind.
        // 同樣的形狀,放進使用者可能會伸手去拿的其他容器裡。該回報沒有指名任何一個容器,因此全部試過,
        // 而不是只試那個剛好先想到的。
        let inHStack = HStack {
            ForEach(empty, id: \.self) { x in Text("\(x)") }
            Text("after")
        }
        let node3 = ViewGraphNode(for: inHStack, backend: backend, environment: environment)
        _ = node3.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node3.commit()

        let inScrollView = ScrollView {
            VStack {
                ForEach(empty, id: \.self) { x in Text("\(x)") }
                Text("after")
            }
        }
        let node4 = ViewGraphNode(for: inScrollView, backend: backend, environment: environment)
        _ = node4.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node4.commit()

        let twoEmpties = VStack {
            ForEach(empty, id: \.self) { x in Text("\(x)") }
            ForEach(empty, id: \.self) { x in Text("\(x)") }
            Text("after")
        }
        let node5 = ViewGraphNode(for: twoEmpties, backend: backend, environment: environment)
        _ = node5.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node5.commit()

        // Emptied by an UPDATE rather than empty from the start. The report says
        // "first frame", but a list that becomes empty is the commoner shape and
        // costs one more node to rule out.
        // 由一次**更新**變空,而不是一開始就空。該回報說的是「第一幀」,但「一個變空的清單」是更常見的
        // 形狀,而排除它只多花一個節點。
        func rows(_ ids: [Int]) -> some View {
            VStack {
                ForEach(ids, id: \.self) { x in Text("\(x)") }
                Text("after")
            }
        }
        let node6 = ViewGraphNode(for: rows([1, 2]), backend: backend, environment: environment)
        _ = node6.computeLayout(proposedSize: .unspecified, environment: environment)
        _ = node6.commit()
        _ = node6.computeLayout(
            with: rows([]),
            proposedSize: .unspecified,
            environment: environment
        )
        _ = node6.commit()
    }

    @MainActor
    @Test("Reordered children")
    func reorderedChildren() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        func makeView(_ ids: [Int]) -> ForEach<[Int], Int, TupleView1<Text>> {
            ForEach(ids, id: \.self) { x in
                Text("\(x)")
            }
        }

        let values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        var forEach = makeView(values)

        // Perform the initial update
        let node = ViewGraphNode(for: forEach, backend: backend, environment: environment)
        _ = node.computeLayout(
            proposedSize: .unspecified,
            environment: environment
        )
        _ = node.commit()

        // Initialize the state of each view to match its index
        let originalErasedNodes = node.children.erasedNodes
        let originalNodes = originalErasedNodes.map(\.node)
        let originalWidgets = node.widget.getChildren()

        #expect(originalNodes.count == values.count)
        #expect(originalWidgets.count == values.count)

        // let values =    [11, 1, 5, 3, 4, 2, 6, 7, 8, 9, 10]
        let newValues = [11, 1, 5, 6, 2, 4, 3]

        forEach = makeView(newValues)
        _ = node.computeLayout(
            with: forEach,
            proposedSize: .unspecified,
            environment: environment
        )
        _ = node.commit()

        let newErasedNodes = node.children.erasedNodes
        let newNodes = newErasedNodes.map(\.node)
        let newWidgets = node.widget.getChildren()

        // Sanity check
        #expect(newNodes.count == newValues.count)
        #expect(newWidgets.count == newValues.count)

        // Have we successfully re-used all nodes whose identifiers are present
        // in both values and newValues?
        for (originalNode, originalId) in zip(originalNodes, values) {
            for (newNode, newId) in zip(newNodes, newValues) {
                #expect(
                    (originalNode === newNode)
                        <=>
                        (originalId == newId)
                )
            }
        }

        // Have we successfully re-arranged the widgets to match the nodes?
        #expect(
            zip(originalWidgets, originalErasedNodes)
                .allSatisfy { $0.0 === $0.1.getWidget().into() }
        )
        #expect(zip(newWidgets, newErasedNodes).allSatisfy { $0.0 === $0.1.getWidget().into() })
    }
}

infix operator <=>

func <=> (_ lhs: Bool, _ rhs: Bool) -> Bool {
    lhs == rhs
}
