import DummyBackend
import Foundation
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// A compact NavigationSplitView shows one column at a time, as SwiftUI's does;
/// a regular one, and a SideBySideSplitView at any width, show them side by side.
///
/// compact 的 NavigationSplitView 與 SwiftUI 相同，一次顯示一欄;regular 的，以及任何寬度的
/// SideBySideSplitView,則並排顯示各欄。
@MainActor
struct NavigationSplitViewTests {
    struct TwoColumns: View {
        @State var selected: Int? = nil

        var body: some View {
            NavigationSplitView {
                List([1, 2, 3], id: \.self, selection: $selected) { item in
                    Text("Row \(item)")
                }
            } detail: {
                Text(selected.map { "Detail \($0)" } ?? "Nothing chosen")
            }
        }
    }

    struct SideBySide: View {
        @State var selected: Int? = nil

        var body: some View {
            SideBySideSplitView {
                List([1, 2, 3], id: \.self, selection: $selected) { item in
                    Text("Row \(item)")
                }
            } detail: {
                Text(selected.map { "Detail \($0)" } ?? "Nothing chosen")
            }
        }
    }

    /// Every widget under `widget`, depth first. / `widget` 底下的每一個 widget,深度優先。
    func widgets(under widget: DummyBackend.Widget) -> [DummyBackend.Widget] {
        [widget] + widget.getChildren().flatMap { widgets(under: $0) }
    }

    func texts(under widget: DummyBackend.Widget) -> [String] {
        widgets(under: widget).compactMap { ($0 as? DummyBackend.TextView)?.content }
    }

    func list(under widget: DummyBackend.Widget) -> DummyBackend.SelectableListView? {
        widgets(under: widget).lazy.compactMap { $0 as? DummyBackend.SelectableListView }.first
    }

    /// The action of the back bar's button, if there is one. / 返回列按鈕的動作(若有)。
    func backButton(under widget: DummyBackend.Widget) -> (() -> Void)? {
        for case let button as DummyBackend.Button in widgets(under: widget) {
            if let label = button.label, texts(under: label).contains(where: { $0.contains("Back") }) {
                return button.action
            }
        }
        return nil
    }

    func node<V: View>(
        _ view: V,
        sizeClass: UserInterfaceSizeClass
    ) -> ViewGraphNode<V, DummyBackend> {
        let environment = ViewGraphHelpers.environment.with(\.horizontalSizeClass, sizeClass)
        let node = ViewGraphNode(
            for: view,
            backend: ViewGraphHelpers.backend,
            environment: environment
        )
        _ = node.computeLayout(proposedSize: ProposedViewSize(390, 800), environment: environment)
        _ = node.commit()
        return node
    }

    /// Lets the update a state change scheduled on the main queue run.
    /// 讓狀態改變排進主佇列的更新執行。
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("Compact: a chosen row moves to the detail column, Back returns and clears it")
    func compactMovesBetweenColumns() async throws {
        let node = node(TwoColumns(), sizeClass: .compact)
        let root = node.widget

        let sidebarList = try #require(list(under: root))
        #expect(!texts(under: root).contains("Nothing chosen"))
        #expect(backButton(under: root) == nil)

        let choose = try #require(sidebarList.selectionHandler)
        choose(1)
        try await settle()

        #expect(list(under: root) == nil)
        #expect(texts(under: root).contains("Detail 2"))
        let back = try #require(backButton(under: root))

        back()
        try await settle()

        let listAgain = try #require(list(under: root))
        #expect(listAgain.selectedIndex == nil)
        #expect(backButton(under: root) == nil)
        #expect(!texts(under: root).contains { $0.hasPrefix("Detail") })
    }

    @Test("Regular: both columns side by side, no back bar")
    func regularShowsBothColumns() throws {
        let node = node(TwoColumns(), sizeClass: .regular)
        let root = node.widget

        #expect(list(under: root) != nil)
        #expect(texts(under: root).contains("Nothing chosen"))
        #expect(backButton(under: root) == nil)
    }

    @Test("SideBySideSplitView keeps both columns in a compact window")
    func sideBySideNeverCollapses() async throws {
        let node = node(SideBySide(), sizeClass: .compact)
        let root = node.widget

        let sidebarList = try #require(list(under: root))
        #expect(texts(under: root).contains("Nothing chosen"))

        let choose = try #require(sidebarList.selectionHandler)
        choose(0)
        try await settle()

        #expect(list(under: root) != nil)
        #expect(texts(under: root).contains("Detail 1"))
        #expect(backButton(under: root) == nil)
    }

    @Test("The window's size class follows its width at 600 points")
    func sizeClassFromWidth() {
        #expect(UserInterfaceSizeClass.forWindowWidth(390) == .compact)
        #expect(UserInterfaceSizeClass.forWindowWidth(599) == .compact)
        #expect(UserInterfaceSizeClass.forWindowWidth(600) == .regular)
        #expect(UserInterfaceSizeClass.forWindowWidth(1200) == .regular)
    }
}
