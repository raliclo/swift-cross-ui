import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Testing for stack layouts")
struct StackLayoutTests {
    @MainActor
    @Test("Empty ScrollView should still be greedy in stack (#328)")
    func emptyScrollViewInStack() {
        let view = VStack {
            Text("Dummy")
            ScrollView {}
        }

        let height = 200.0
        let result = ViewGraphHelpers.computeLayout(
            of: view,
            proposedSize: ProposedViewSize(100, height)
        )

        #expect(result.size.height == height)
    }

    @MainActor
    @Test("Fixed size stack redistributes space (#453)")
    func fixedSizeStackSpaceRedistribution() {
        let view = VStack(spacing: 0) {
            Text("Dummy")
            Color.blue
            Text("Dummy")
        }.fixedSize()

        let node = ViewGraphHelpers.committedNode(
            for: view,
            proposedSize: ProposedViewSize(200, 200)
        )

        let fixedSizeWidget = node.widget.getChildren()[0]
        let children = fixedSizeWidget.getChildren()
        let text1 = children[0]
        let color = children[1]
        let text2 = children[2]

        // Ensure #453 resolved
        #expect(text1.size.x == color.size.x)

        // Sanity checks
        #expect(text1.size == text2.size)
    }

    @MainActor
    @Test("Spacer layout priority")
    func spacerLayoutPriority() {
        let strings = ["AA", "AAAA"]
        let view = HStack(spacing: 0) {
            Text(strings[0])
            Spacer(minLength: 0)
            Text(strings[1])
        }

        let lineHeight = ViewGraphHelpers.environment.resolvedFont.lineHeight

        let textResults = strings.map(Text.init(_:)).map {
            ViewGraphHelpers.computeLayout(of: $0)
        }
        let minimumWidthWithoutWrapping = textResults.map(\.size.vector.x).reduce(0, +)
        let proposedSize = ProposedViewSize(
            Double(minimumWidthWithoutWrapping),
            lineHeight * 2
        )
        let result = ViewGraphHelpers.computeLayout(of: view, proposedSize: proposedSize)

        // No wrapping, and perfect fit
        #expect(result.size.height == ViewGraphHelpers.environment.resolvedFont.lineHeight)
        #expect(result.size.vector.x == minimumWidthWithoutWrapping)
    }

    @MainActor
    @Test("Commit-time redistribution still stretches a flexible child")
    func redistributionStretchesFlexibleChild() {
        // Proposed no height, so the stack lays its children out again at commit.
        // A child already as tall as the row (the 40-high frame) keeps its layout;
        // the blue Color still grows to it and the Text stays one line (2026-11-13).
        // 沒有被提議高度，所以 stack 在 commit 時把子元件再排一次。已經和整列一樣高的子元件(40 高的 frame)沿用原排版;藍色 Color 仍長到整列高，
        // 較矮的 Text 維持一行(2026-11-13)。
        let view = HStack(spacing: 0) {
            Color.red.frame(height: 40)
            Color.blue
            Text("three")
        }.fixedSize(horizontal: false, vertical: true)

        let node = ViewGraphHelpers.committedNode(for: view, proposedSize: ProposedViewSize(200, 200))
        let children = node.widget.getChildren()[0].getChildren()

        #expect(children[1].size.y == children[0].size.y)
        #expect(children[2].size.y < children[0].size.y, "\(children.map(\.size))")
    }

    @MainActor
    @Test("A redistributed child keeps its layout only for its own size")
    func proposesOwnSizeRule() {
        typealias Node = ViewGraphNode<EmptyView, DummyBackend>
        let size = ViewSize(174, 40)
        let last = ProposedViewSize(193, nil)
        // Each axis: the last proposal, or exactly the size it produced.
        // 每一軸：上次的提議，或正好是它算出的尺寸。
        #expect(Node.proposesOwnSize(ProposedViewSize(174, 40), last: last, size: size))
        #expect(Node.proposesOwnSize(ProposedViewSize(193, 40), last: last, size: size))
        #expect(!Node.proposesOwnSize(ProposedViewSize(193, 60), last: last, size: size))
        #expect(!Node.proposesOwnSize(ProposedViewSize(150, 40), last: last, size: size))
        #expect(!Node.proposesOwnSize(ProposedViewSize(174, nil), last: ProposedViewSize(174, nil), size: size))
    }
}
