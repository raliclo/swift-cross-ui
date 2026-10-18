import Testing

@testable @_spi(Backends) import SwiftCrossUI
import DummyBackend

@MainActor
enum BodyReturnProbe {
    static var appeared: [String] = []
    static var bodies = 0
}

struct ImplicitBodyView: View {
    var body: some View {
        let _ = BodyReturnProbe.bodies += 1
        VStack {
            Text("a")
        }
        .padding(4)
        .onAppear { BodyReturnProbe.appeared.append("implicit") }
    }
}

struct ExplicitReturnBodyView: View {
    var body: some View {
        BodyReturnProbe.bodies += 1
        return VStack {
            Text("a")
        }
        .padding(4)
        .onAppear { BodyReturnProbe.appeared.append("return") }
    }
}

/// The 2026-09-08 shape (testapp/plan/explicit-return-body.md): a returned `Text`.
/// 2026-09-08 的形狀(testapp/plan/explicit-return-body.md):回傳一個 `Text`。
struct ReturnedTextView: View {
    var body: some View {
        let n = 7
        return Text("MINIMAL n=\(n)")
    }
}

/// `View`'s default implementations route a builder body through a `VStack`
/// and anything else through the body itself; an explicit `return` must not
/// lose a modifier's `asWidget` (`.onAppear`) or draw nothing (`Text`).
/// `View` 的預設實作讓 builder 產生的 body 經過 `VStack`,其餘直接經過 body 本身;顯式 `return` 不可以讓
/// modifier 的 `asWidget`(`.onAppear`)消失，也不可以什麼都不畫(`Text`)。
@Suite("A body with a statement and an explicit return")
struct BodyReturnTests {
    @MainActor
    @discardableResult
    func show(_ view: some View) -> ViewSize {
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)
        let graph = ViewGraph(for: view, backend: backend, environment: environment)
        let result = graph.computeLayout(
            proposedSize: ProposedViewSize(ViewSize(200, 200)),
            environment: environment
        )
        graph.commit()
        return result.size
    }

    @Test("A returned Text is laid out with a size")
    @MainActor
    func returnedText() {
        let size = show(ReturnedTextView())
        #expect(size.width > 0 && size.height > 0)
    }

    @Test("onAppear runs whichever way the body is written")
    @MainActor
    func onAppearRuns() {
        BodyReturnProbe.appeared = []
        show(ImplicitBodyView())
        show(ExplicitReturnBodyView())
        #expect(BodyReturnProbe.appeared == ["implicit", "return"])
    }
}
