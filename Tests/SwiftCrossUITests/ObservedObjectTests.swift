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

    /// The P45 shape: the model is created by the wrapper's own initial value.
    struct InlineModelView: View {
        @ObservedObject var model = Counter()
        var body: some View { Text("\(model.count)") }
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
    @Test("An inline model survives the view being re-created by its parent")
    func inlineModelSurvivesRecreation() {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)

        let node = ViewGraphNode(for: InlineModelView(), backend: backend, environment: environment)
        layout(node, environment: environment)
        let original = node.view.model
        original.count = 3

        // What the parent does on every layout pass: build the view again.
        layout(node, with: InlineModelView(), environment: environment)

        #expect(node.view.model === original)
        #expect(node.view.model.count == 3)
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
