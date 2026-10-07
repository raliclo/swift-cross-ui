import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

/// What `@ObservedObject` does when its view is re-created by the parent.
///
/// This framework re-creates view structs far more often than SwiftUI -- a
/// view's own @State change lays its parent out again, and the parent's body
/// builds the child anew. `computeLayout(with:)` is exactly that path, so these
/// tests hand the node a freshly built view the way a parent does.
///
/// 當父層重建 view 時 `@ObservedObject` 怎麼做。本框架重建 view struct 的頻率遠高於 SwiftUI——view 自己的
/// @State 改變會讓父層重新排版,而父層的 body 會重新建出子 view。`computeLayout(with:)` 正是那條路徑,所以
/// 這些測試像父層一樣,把新建的 view 交給節點。
@Suite("ObservedObject across view re-creation")
struct ObservedObjectTests {
    final class Counter: SwiftCrossUI.ObservableObject {
        @SwiftCrossUI.Published var count = 0
    }


    /// The parent-owned shape: the object is passed in.
    struct PassedModelView: View {
        @ObservedObject var model: Counter
        var body: some View { Text("\(model.count)") }
    }

    @MainActor
    private func layout<V: View>(
        _ node: ViewGraphNode<V, DummyBackend>,
        with view: V? = nil,
        environment: EnvironmentValues
    ) {
        _ = node.computeLayout(
            with: view,
            proposedSize: ProposedViewSize(200, 200),
            environment: environment
        )
        // Committed as the real update is. `commit` clears the layout cache, and
        // without it the next `computeLayout` with the same proposal returns the
        // cached result without looking at the new view at all -- the first
        // version of these tests did that, and passed and failed identically with
        // and without the fix.
        // 與真正的更新一樣要 commit。`commit` 會清掉排版快取;少了它,下一次同樣提議的 `computeLayout`
        // 會直接回傳快取、根本不看新的 view——這些測試的第一版就是那樣,修正前後通過與失敗都一模一樣。
        _ = node.commit()
    }

    @MainActor
    @Test("A fresh object from the parent, held by nobody else, is adopted")
    func freshPassedModelIsAdopted() {
        // The review case (Codex, 2026-10-07): `Child(model: Model(...))`, where
        // the parent keeps no reference. Until then such an object was refused
        // and the child kept showing the first one.
        // review 的情境(Codex,2026-10-07):`Child(model: Model(...))`,父層不保留參考。在那之前這種物件會被拒絕，
        // 子 view 一直顯示第一個。
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        let node = ViewGraphNode(
            for: PassedModelView(model: Counter()), backend: backend, environment: environment
        )
        layout(node, environment: environment)

        let fresh = { () -> Counter in
            let counter = Counter()
            counter.count = 9
            return counter
        }
        layout(node, with: PassedModelView(model: fresh()), environment: environment)

        #expect(node.view.model.count == 9)
    }

    /// A view that owns its model, the way P45 now does.
    struct OwnedModelView: View {
        @StateObject var model = Counter()
        var body: some View { Text("\(model.count)") }
    }

    @MainActor
    @Test("A @StateObject survives the view being re-created by its parent")
    func stateObjectSurvivesRecreation() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        let node = ViewGraphNode(for: OwnedModelView(), backend: backend, environment: environment)
        layout(node, environment: environment)
        let original = node.view.model
        original.count = 3

        layout(node, with: OwnedModelView(), environment: environment)

        #expect(node.view.model === original)
        #expect(node.view.model.count == 3)
    }

    /// A child whose @State change makes it wider, counting its constructions.
    struct GrowingChild: View {
        nonisolated(unsafe) static var constructions = 0
        nonisolated(unsafe) static var text: Binding<String>?
        @State var label = "a"
        init() { Self.constructions += 1 }
        var body: some View {
            let _ = { Self.text = $label }()
            Text(label)
        }
    }

    struct ParentOfGrowingChild: View {
        var body: some View {
            VStack { GrowingChild() }
        }
    }

    @MainActor
    @Test("A child's own state change does not make its parent re-create it")
    func childStateChangeDoesNotRecreateIt() async throws {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        GrowingChild.constructions = 0
        let node = ViewGraphNode(for: ParentOfGrowingChild(), backend: backend, environment: environment)
        layout(node, environment: environment)
        let afterLaunch = GrowingChild.constructions
        #expect(afterLaunch > 0)

        // Longer text: the child resizes, which lays its parent out again.
        GrowingChild.text?.wrappedValue = "a much longer label than before"
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(GrowingChild.text?.wrappedValue == "a much longer label than before")
        // The re-layout this resize starts lays out the parent's KEPT body
        // (`EnvironmentValues.reusesBodies`). Evaluating it again builds the
        // child -- a first attempt that only withheld the new view from the node
        // failed this line identically with and without it (2026-09-29).
        // 這次尺寸改變所發起的重新排版,排的是父層**保存的** body。再求值一次就會建出子 view——第一次只把新 view
        // 擋在節點外的嘗試,在有無它時這一行失敗得一模一樣(2026-09-29)。
        #expect(GrowingChild.constructions == afterLaunch)
    }

    @MainActor
    @Test("A model the parent holds and passes is still adopted")
    func passedModelIsAdopted() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        let first = Counter()
        let second = Counter()
        second.count = 7

        let node = ViewGraphNode(
            for: PassedModelView(model: first), backend: backend, environment: environment
        )
        layout(node, environment: environment)

        layout(node, with: PassedModelView(model: second), environment: environment)

        #expect(node.view.model === second)
        #expect(node.view.model.count == 7)
        // `second` stays alive to here, as a parent's own property would.
        #expect(second.count == 7)
    }
}
