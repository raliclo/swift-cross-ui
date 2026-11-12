import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

/// How many times creating a node evaluates its view's `body`.
///
/// `ViewGraphNode.init` calls `view.children(...)` and then `view.asWidget(...)`,
/// and the default implementations of both used to evaluate `body`, so every
/// new node built its body twice before anything was laid out (Swift-Cross-UI-M4,
/// AppKit P2, 2026-11-12). `BodyHandoff` passes the first one to the second.
///
/// 建立節點時會求值它 view 的 `body` 幾次。`ViewGraphNode.init` 先呼叫 `view.children(...)` 再呼叫
/// `view.asWidget(...)`,兩者的預設實作以前都會求值 `body`,所以每個新節點在排版之前就建了兩次 body(Swift-Cross-UI-M4,
/// AppKit P2,2026-11-12)。`BodyHandoff` 把第一次的結果交給第二次。
@Suite("Body evaluations on node creation")
struct BodyEvaluationTests {
    /// A builder-produced body, which the default implementation wraps in a `VStack`.
    struct BuilderBody: View {
        nonisolated(unsafe) static var evaluations = 0
        var body: some View {
            // a result builder takes `let _ =`, not `_ =`
            // swiftlint:disable:next redundant_discardable_let
            let _ = { Self.evaluations += 1 }()
            Text("builder")
        }
    }

    /// An explicit `return`, which the default implementation hands to the body itself.
    struct ExplicitReturnBody: View {
        nonisolated(unsafe) static var evaluations = 0
        var body: some View {
            Self.evaluations += 1
            return Text("explicit return")
        }
    }

    /// The same type nested inside itself, so an offered body must not be taken by
    /// the inner node. / 同一型別包在自己裡面，提供的 body 不可被內層節點取走。
    struct Nested: View {
        nonisolated(unsafe) static var evaluations = 0
        var depth: Int
        var body: some View {
            // a result builder takes `let _ =`, not `_ =`
            // swiftlint:disable:next redundant_discardable_let
            let _ = { Self.evaluations += 1 }()
            if depth > 0 {
                Nested(depth: depth - 1)
            } else {
                Text("leaf")
            }
        }
    }

    @MainActor
    private func makeEnvironment() -> (DummyBackend, EnvironmentValues) {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        return (backend, EnvironmentValues(backend: backend).with(\.window, window))
    }

    @MainActor
    @Test("A builder body is evaluated once when its node is created")
    func builderBodyOnce() {
        let (backend, environment) = makeEnvironment()
        BuilderBody.evaluations = 0
        let node = ViewGraphNode(for: BuilderBody(), backend: backend, environment: environment)
        #expect(BuilderBody.evaluations == 1)

        let result = node.computeLayout(proposedSize: ProposedViewSize(200, 200), environment: environment)
        #expect(result.size.width > 0)
    }

    @MainActor
    @Test("An explicit-return body is evaluated once and still draws")
    func explicitReturnBodyOnce() {
        let (backend, environment) = makeEnvironment()
        ExplicitReturnBody.evaluations = 0
        let node = ViewGraphNode(for: ExplicitReturnBody(), backend: backend, environment: environment)
        #expect(ExplicitReturnBody.evaluations == 1)

        let result = node.computeLayout(proposedSize: ProposedViewSize(200, 200), environment: environment)
        #expect(result.size.width > 0)
    }

    @MainActor
    @Test("Nested nodes of one type each evaluate their own body once")
    func nestedSameTypeOncePerNode() {
        let (backend, environment) = makeEnvironment()
        Nested.evaluations = 0
        let node = ViewGraphNode(for: Nested(depth: 2), backend: backend, environment: environment)
        // Three nodes -- depth 2, 1 and 0 -- one evaluation each.
        // 三個節點(深度 2、1、0),各求值一次。
        #expect(Nested.evaluations == 3)

        let result = node.computeLayout(proposedSize: ProposedViewSize(200, 200), environment: environment)
        #expect(result.size.width > 0)
    }
}
