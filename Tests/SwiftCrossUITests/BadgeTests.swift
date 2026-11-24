import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// badge(_:) on tabs and list rows: zero hides it, and it draws only in a row.
/// badge(_:) 用於分頁與清單列：零會隱藏它，而且只在列之中繪製。
@MainActor
struct BadgeTests {
    @Test("A count of zero hides the badge; other counts show as written")
    func countLabels() {
        #expect(Badge.label(for: 0) == nil)
        #expect(Badge.label(for: 3)?.string == "3")
        #expect(Badge.label(for: -2)?.string == "-2")
        #expect(Badge.label(for: "New")?.string == "New")
        #expect(Badge.label(for: "") == nil)
        #expect(Badge.label(for: nil as Substring?) == nil)
    }

    @Test("A tab carries its badge, and a later badge(0) removes it")
    func tabBadge() {
        let tab = Tab("Inbox") { Text("Inbox") }
        #expect(tab.badge == nil)
        #expect(tab.badge(3).badge?.string == "3")
        #expect(tab.badge("New").badge?.string == "New")
        #expect(tab.badge(Text("Hi")).badge?.string == "Hi")
        #expect(tab.badge(3).badge(0).badge == nil)
        #expect(tab.badge(nil as Text?).badge == nil)
    }

    @Test("Outside a list row a badge changes no size")
    func outsideRowUnchanged() {
        let proposal = ProposedViewSize(200, nil)
        let plain = ViewGraphHelpers.computeLayout(of: Text("Row"), proposedSize: proposal)
        let badged = ViewGraphHelpers.computeLayout(of: Text("Row").badge(3), proposedSize: proposal)
        #expect(plain.size == badged.size)
    }

    @Test("In a list row a badge fills the row to its trailing edge; zero does not")
    func insideRowDrawn() {
        let proposal = ProposedViewSize(200, nil)
        func inRow<V: View>(_ view: V) -> ViewLayoutResult {
            ViewGraphHelpers.computeLayout(
                of: view.environment(\.isListRowContent, true),
                proposedSize: proposal
            )
        }
        let plain = inRow(Text("Row"))
        let badged = inRow(Text("Row").badge(3))
        let hidden = inRow(Text("Row").badge(0))
        #expect(badged.size.width == 200)
        #expect(plain.size.width < 200)
        #expect(hidden.size == plain.size)
    }
}
