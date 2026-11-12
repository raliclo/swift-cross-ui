import Foundation

/// Reuse of a probe's layout result in the final call of the same pass.
///
/// **Why there is anything to reuse.** Stacks probe each child with
/// `allowLayoutCaching` (a minimum and a maximum proposal) and then lay it out
/// for real without the flag, and the real call misses `resultCache` by design.
/// Measured 2026-11-12 in P998 (one pass, 1753 commits, GTK): 3263 final-call
/// misses, 3064 of them for a proposal a probe had already computed.
///
/// **Why it is not just a cache lookup.** Commit reads state the LAST
/// `computeLayout` left -- each descendant node's `currentLayout`,
/// `lastProposedSize`, `lastBody`, `parentEnvironment`, and the children
/// object's own state (`StackLayoutCache`). A cache hit writes none of it, so a
/// descendant can hold the state of another proposal. A reused result therefore
/// carries a ``LayoutReuseRecord``: the state its node had right after computing
/// it, and the last proposal each node computed under it was given. Restoring
/// walks those, each node restoring from its OWN record.
///
/// **Only what is known to be safe is reused.** A record is reusable when the
/// node's children type can snapshot its layout state (``LayoutSnapshotChildren``
/// or a ``TupleViewChildren``), nothing marked the computation unsafe
/// (``LayoutReuse/markUnsafe()``, called by representables whose native views
/// may keep per-proposal state), and every record below it is reusable. Children
/// types that behave differently on a probe -- `GeometryReader`, `List`,
/// `ScrollView`, `Table`, `SplitView` -- do not conform, so they and everything
/// above them recompute as before.
///
/// **Off unless `SCUI_LAYOUT_REUSE=1`.** `SCUI_LAYOUT_REUSE_CHECK=1` computes the
/// result anyway and reports every reusable record whose result differs (the
/// acceptance check in todo.md); it changes nothing else.
///
/// 在同一輪的最後一次呼叫中重用試探時算出的排版結果。
///
/// **為何有東西可以重用。** stack 會以 `allowLayoutCaching` 試探每個子節點(最小與最大提議尺寸),再不帶這個旗標
/// 真正排版一次，而真正的那次依設計不會查 `resultCache`。2026-11-12 於 P998 實測(一輪、1753 次 commit、GTK):最後一次
/// 呼叫共 3263 次未命中，其中 3064 次的提議尺寸已經有試探算過。
///
/// **為何不只是查快取。** commit 讀的是「最後一次」`computeLayout` 留下的狀態——每個子孫節點的 `currentLayout`、
/// `lastProposedSize`、`lastBody`、`parentEnvironment`,以及 children 物件自己的狀態(`StackLayoutCache`)。命中快取時
/// 這些都不會寫入，所以子孫可能留著別的提議尺寸的狀態。因此被重用的結果附帶一份 ``LayoutReuseRecord``:節點算出它之後的
/// 狀態，以及其下每個節點最後一次收到的提議尺寸。還原時沿著這些走，每個節點都從**自己的**紀錄還原。
///
/// **只重用已知安全的。** 紀錄可重用的條件：節點的 children 型別能為排版狀態做快照(``LayoutSnapshotChildren`` 或
/// ``TupleViewChildren``)、沒有任何東西把這次計算標為不安全(``LayoutReuse/markUnsafe()``,由原生 view 可能保留各提議
/// 尺寸狀態的 representable 呼叫),而且其下每份紀錄都可重用。在試探時行為不同的 children 型別——`GeometryReader`、
/// `List`、`ScrollView`、`Table`、`SplitView`——都沒有 conform,所以它們與其上的一切照舊重算。
///
/// **除非 `SCUI_LAYOUT_REUSE=1`,否則關閉。** `SCUI_LAYOUT_REUSE_CHECK=1` 仍然照常計算，並回報每一份可重用、但結果
/// 不同的紀錄(todo.md 裡的驗收檢查);它不改變其他任何東西。
@_spi(Backends)
@MainActor
public enum LayoutReuse {
    static let environment = ProcessInfo.processInfo.environment
    /// Reuse probe results in the final call. A `var` so tests can switch it.
    /// 在最後一次呼叫中重用試探結果。是 `var`,讓測試可以切換。
    static var isEnabled = environment["SCUI_LAYOUT_REUSE"] == "1"
    /// Compute anyway and report mismatches. / 仍然計算並回報不一致。
    static var isChecking = environment["SCUI_LAYOUT_REUSE_CHECK"] == "1"
    /// Mismatches seen by the check, for tests. / 檢查看到的不一致次數，供測試使用。
    static var mismatchCount = 0
    /// Final calls that found a reusable record (reused, or checked). / 找到可重用紀錄的最後一次呼叫(重用或檢查)。
    static var candidateCount = 0
    /// Whether records are kept at all. / 是否保留紀錄。
    static var isRecording: Bool { isEnabled || isChecking }

    /// One node's computation in progress: the calls made under it.
    /// 一次進行中的節點計算：在它之下發生的呼叫。
    final class Frame {
        var calls: [ObjectIdentifier: LayoutReuseRecord.Call] = [:]
        var isUnsafe = false
    }

    private static var frames: [Frame] = []

    /// Says the layout being computed must not be reused: its view keeps state
    /// per proposal that no record restores (a native view behind a
    /// representable, say). A no-op unless reuse is recorded.
    /// 表示正在計算的排版不可被重用：它的 view 保留了紀錄無法還原的各提議尺寸狀態(例如 representable 背後的原生 view)。
    /// 沒有記錄重用時不做任何事。
    public static func markUnsafe() {
        frames.last?.isUnsafe = true
    }

    static func recordCall(_ call: LayoutReuseRecord.Call) {
        frames.last?.calls[call.node] = call
    }

    static func push() -> Frame {
        let frame = Frame()
        frames.append(frame)
        return frame
    }

    static func pop() {
        _ = frames.popLast()
    }

    /// The layout state of a children object, if its type can snapshot it.
    /// children 物件的排版狀態(若其型別能做快照)。
    static func snapshot(of children: any ViewGraphNodeChildren) -> (supported: Bool, value: Any?) {
        if let tuple = children as? any TupleViewChildren {
            return (true, tuple.stackLayoutCache)
        }
        if let snapshotting = children as? any LayoutSnapshotChildren {
            return (true, snapshotting.layoutSnapshot())
        }
        return (false, nil)
    }

    static func restore(_ value: Any?, into children: any ViewGraphNodeChildren) {
        if let tuple = children as? any TupleViewChildren, let cache = value as? StackLayoutCache {
            tuple.stackLayoutCache = cache
        } else if let snapshotting = children as? any LayoutSnapshotChildren {
            snapshotting.restoreLayoutSnapshot(value)
        }
    }

    private static var reportedMismatches: Set<String> = []

    /// Reports, once per view type, a reusable record whose result was not the
    /// one a real computation gave. / 對每個 view 型別回報一次：可重用的紀錄，其結果與實際計算不同。
    static func reportMismatch(view: String, proposal: ProposedViewSize, reused: ViewSize, computed: ViewSize) {
        mismatchCount += 1
        guard reportedMismatches.insert(view).inserted else { return }
        FileHandle.standardError.write(
            Data(
                "layout-reuse mismatch: \(view) proposed \(proposal) reused \(reused) computed \(computed)\n".utf8
            )
        )
    }
}

/// What a node needs to put back to make a cached result the committed one.
/// 節點要讓某個快取結果成為被 commit 的那一個時，必須還原的東西。
@MainActor
final class LayoutReuseRecord {
    /// A call made under the recorded computation, and how to restore it.
    /// 在被記錄的計算之下發生的一次呼叫，以及如何還原它。
    struct Call {
        let node: ObjectIdentifier
        let proposal: ProposedViewSize
        let isReusable: () -> Bool
        let restore: () -> Void
    }

    let lastBody: Any?
    let environment: EnvironmentValues
    let childrenSnapshot: Any?
    let calls: [Call]
    /// Precomputed when the record is made: everything it restores was safe then,
    /// and records are dropped at commit, so it stays true for the pass.
    /// 在建立紀錄時算好：它要還原的一切當時都是安全的，而紀錄在 commit 時就丟棄，所以整輪都成立。
    let isReusable: Bool

    init(
        lastBody: Any?, environment: EnvironmentValues, childrenSnapshot: Any?,
        calls: [Call], isReusable: Bool
    ) {
        self.lastBody = lastBody
        self.environment = environment
        self.childrenSnapshot = childrenSnapshot
        self.calls = calls
        self.isReusable = isReusable
    }
}

/// A children type whose layout state can be saved and put back.
/// 排版狀態可以存下並放回的 children 型別。
@MainActor
protocol LayoutSnapshotChildren: ViewGraphNodeChildren {
    func layoutSnapshot() -> Any?
    func restoreLayoutSnapshot(_ snapshot: Any?)
}

/// A children type with no layout state that depends on the proposal (audit of
/// 2026-11-12: structural, sticky, or keyed by input).
/// 沒有隨提議尺寸而變之排版狀態的 children 型別(2026-11-12 的盤點：結構性的、只增不減的，或以輸入為鍵的)。
@MainActor
protocol LayoutStatelessChildren: LayoutSnapshotChildren {}

extension LayoutStatelessChildren {
    func layoutSnapshot() -> Any? { nil }
    func restoreLayoutSnapshot(_: Any?) {}
}

extension EmptyViewChildren: LayoutStatelessChildren {}
extension AnyViewChildren: LayoutStatelessChildren {}
extension EitherViewChildren: LayoutStatelessChildren {}
extension OptionalViewChildren: LayoutStatelessChildren {}
extension HotReloadableViewChildren: LayoutStatelessChildren {}
extension ImageChildren: LayoutStatelessChildren {}
extension MenuStorage: LayoutStatelessChildren {}
extension BuiltinPickerChildren: LayoutStatelessChildren {}
extension ScrollTrackingChildren: LayoutStatelessChildren {}
extension MatchedGeometryChildren: LayoutStatelessChildren {}
extension ShapeStorage: LayoutStatelessChildren {}
extension ColorViewStorage: LayoutStatelessChildren {}
extension GradientViewStorage: LayoutStatelessChildren {}
extension TextColorStorage: LayoutStatelessChildren {}

/// `stackLayoutCache` and the layoutable children commit reads.
/// `stackLayoutCache` 以及 commit 會讀取的可排版子節點。
extension ForEachViewChildren: LayoutSnapshotChildren {
    func layoutSnapshot() -> Any? {
        (stackLayoutCache, layoutableChildren)
    }

    func restoreLayoutSnapshot(_ snapshot: Any?) {
        guard let (cache, layoutable) = snapshot as? (StackLayoutCache, [LayoutSystem.LayoutableChild]) else {
            return
        }
        stackLayoutCache = cache
        layoutableChildren = layoutable
    }
}
