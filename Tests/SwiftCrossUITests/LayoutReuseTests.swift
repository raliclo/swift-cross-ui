import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

/// Reusing a probe's result in the final call must commit exactly what a fresh
/// computation commits. See `LayoutReuse`.
/// 在最後一次呼叫中重用試探結果時，commit 出來的必須與重新計算完全相同。見 `LayoutReuse`。
@Suite("Layout reuse within one pass", .serialized)
@MainActor
struct LayoutReuseTests {
    /// Stacks, a ForEach, flexible frames and fixed ones, so that probes and
    /// final calls propose different sizes.
    /// stack、ForEach、可伸縮與固定的 frame,讓試探與最後一次呼叫提議不同的尺寸。
    struct Page: View {
        var body: some View {
            VStack(spacing: 3) {
                ForEach(0..<4) { index in
                    HStack(spacing: 2) {
                        Text("row \(index)").frame(minWidth: 10, maxWidth: .infinity)
                        Text("x")
                        Color.red.frame(width: Double(20 + index), height: 8)
                        Spacer()
                    }
                }
                Text("footer").padding(4)
            }
        }
    }

    /// Every widget's size and every child's position, depth first.
    /// 深度優先列出每個 widget 的尺寸與每個子 widget 的位置。
    private func geometry(of widget: DummyBackend.Widget) -> [String] {
        var lines = ["\(type(of: widget)) \(widget.size)"]
        if let container = widget as? DummyBackend.Container {
            for child in container.children {
                lines.append("at \(child.position)")
                lines.append(contentsOf: geometry(of: child.widget).map { "  " + $0 })
            }
        } else {
            for child in widget.getChildren() {
                lines.append(contentsOf: geometry(of: child).map { "  " + $0 })
            }
        }
        return lines
    }

    /// Lays out and commits `Page` with reuse as given, returning the geometry.
    /// 依指定的重用設定排版並 commit `Page`,傳回幾何資訊。
    private func committedGeometry(enabled: Bool, checking: Bool) -> [String] {
        LayoutReuse.isEnabled = enabled
        LayoutReuse.isChecking = checking
        defer {
            LayoutReuse.isEnabled = false
            LayoutReuse.isChecking = false
        }
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)
        let node = ViewGraphNode(for: Page(), backend: backend, environment: environment)
        _ = node.computeLayout(proposedSize: ProposedViewSize(300, 200), environment: environment)
        _ = node.commit()
        return geometry(of: node.widget)
    }

    @Test("Reuse commits the same geometry as a fresh computation")
    func reuseCommitsSameGeometry() {
        let fresh = committedGeometry(enabled: false, checking: false)
        LayoutReuse.candidateCount = 0
        let reused = committedGeometry(enabled: true, checking: false)
        // Reuse actually happened -- otherwise equality proves nothing.
        // 確實發生了重用——否則相等什麼也證明不了。
        #expect(LayoutReuse.candidateCount > 0)
        #expect(reused == fresh)
    }

    /// Text that wraps differently at the two widths, so the subtree's state differs.
    /// 在兩種寬度下換行不同的文字，讓子樹狀態不同。
    struct Wrapping: View {
        var body: some View {
            VStack(spacing: 1) {
                Text("short")
                Text("a much longer line that wraps when narrow")
                HStack { Text("left"); Spacer(); Text("right") }
            }
        }
    }

    /// Probe at `first`, probe at `second`, then the final call at `first`: the
    /// sequence where the subtree holds the state of `second` and only a restore
    /// puts back that of `first`.
    /// 先以 `first` 試探、再以 `second` 試探，最後一次呼叫回到 `first`:
    /// 此時子樹留著 `second` 的狀態，只有還原能放回 `first` 的。
    private func probedThenFinal(
        first: ProposedViewSize, second: ProposedViewSize, enabled: Bool
    ) -> [String] {
        LayoutReuse.isEnabled = enabled
        defer { LayoutReuse.isEnabled = false }
        let backend = DummyBackend()
        let window = backend.createWindow(withDefaultSize: nil, id: "window")
        let environment = EnvironmentValues(backend: backend).with(\.window, window)
        let probe = environment.with(\.allowLayoutCaching, true)
        let node = ViewGraphNode(for: Wrapping(), backend: backend, environment: environment)
        _ = node.computeLayout(proposedSize: first, environment: probe)
        _ = node.computeLayout(proposedSize: second, environment: probe)
        _ = node.computeLayout(proposedSize: first, environment: environment)
        _ = node.commit()
        return geometry(of: node.widget)
    }

    @Test("A reused container restores the state of its whole subtree")
    func reuseRestoresSubtree() {
        let first = ProposedViewSize(60, 200)
        let second = ProposedViewSize(400, 200)
        let fresh = probedThenFinal(first: first, second: second, enabled: false)
        LayoutReuse.candidateCount = 0
        let reused = probedThenFinal(first: first, second: second, enabled: true)
        #expect(LayoutReuse.candidateCount > 0)
        #expect(reused == fresh)
        // The two widths really lay out differently. / 兩種寬度確實排出不同結果。
        #expect(fresh != probedThenFinal(first: second, second: first, enabled: false))
    }

    @Test("The check finds no reusable record whose result differs")
    func checkFindsNoMismatch() {
        LayoutReuse.mismatchCount = 0
        LayoutReuse.candidateCount = 0
        _ = committedGeometry(enabled: false, checking: true)
        #expect(LayoutReuse.candidateCount > 0)
        #expect(LayoutReuse.mismatchCount == 0)
    }

    @Test("The check counts final calls that computed afresh")
    func checkCountsFreshFinalCalls() {
        LayoutReuse.noRecordCount = 0
        // The root's final call had no probe before it. / 根節點的最後一次呼叫之前沒有試探。
        _ = committedGeometry(enabled: false, checking: true)
        #expect(LayoutReuse.noRecordCount > 0)
    }

    @Test("Off by default: nothing is recorded")
    func offByDefault() {
        LayoutReuse.candidateCount = 0
        _ = committedGeometry(enabled: false, checking: false)
        #expect(LayoutReuse.candidateCount == 0)
    }
}
