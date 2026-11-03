import Dispatch
import Foundation
import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

/// The core module's state, navigation, layout and alert behaviour that a
/// read-only review found wrong: one test per behaviour, each failing against
/// the code it replaced.
///
/// 一次唯讀 review 在核心模組中找到的狀態、導覽、排版與警示行為：每個行為一個測試，每個都會在它所取代的
/// 程式碼上失敗。
@Suite("Core state, navigation and layout")
struct CoreStateLayoutTests {
    final class Counter: SwiftCrossUI.ObservableObject {
        @SwiftCrossUI.Published var count = 0
    }

    final class TestStorage: StateStorageProtocol {
        var value: Int
        var didChange = Publisher()
        var downstreamObservation: Cancellable?

        init(_ value: Int) {
            self.value = value
        }
    }

    final class Flag: @unchecked Sendable {
        var fired = 0
    }

    // MARK: ObservableObject / State

    @Test("An object's default didChange is one publisher, however often it is read")
    func didChangeIsCachedPerObject() {
        let counter = Counter()
        let first = counter.didChange
        for _ in 0..<100 {
            _ = counter.didChange
        }
        #expect(counter.didChange === first)
        #expect(Counter().didChange !== first)

        let flag = Flag()
        let cancellable = counter.didChange.observe { flag.fired += 1 }
        counter.count = 1
        #expect(flag.fired == 1)
        cancellable.cancel()
    }

    @Test("Assigning a new object to @State observes the new one and not the old")
    func stateRelinksToNewObject() {
        let old = Counter()
        let new = Counter()
        let state = State(wrappedValue: old)
        let flag = Flag()
        let cancellable = state.didChange.observe { flag.fired += 1 }

        state.wrappedValue = new
        flag.fired = 0
        new.count = 1
        #expect(flag.fired == 1)
        old.count = 1
        #expect(flag.fired == 1)
        cancellable.cancel()
    }

    @Test("Replacing .some(objA) with .some(objB) in an optional @State relinks")
    func optionalStateRelinksToNewObject() {
        let old = Counter()
        let new = Counter()
        let state = State<Counter?>(wrappedValue: old)
        let flag = Flag()
        let cancellable = state.didChange.observe { flag.fired += 1 }

        state.wrappedValue = new
        flag.fired = 0
        new.count = 1
        #expect(flag.fired == 1)
        old.count = 1
        #expect(flag.fired == 1)

        state.wrappedValue = nil
        flag.fired = 0
        new.count = 2
        #expect(flag.fired == 0)
        cancellable.cancel()
    }

    @Test("An integer tween never leaves the span between its start and end")
    func integerTweenIsClamped() {
        typealias Impl = StateImpl<TestStorage>
        #expect(Impl.clampedToSpan(12, from: 0, to: 10) == 10)
        #expect(Impl.clampedToSpan(-1, from: 0, to: 10) == 0)
        #expect(Impl.clampedToSpan(-1, from: 10, to: 0) == 0)
        #expect(Impl.clampedToSpan(Double(10.5), from: 0.0, to: 10.0) == Double(10.5))

        let storage = TestStorage(0)
        let apply = Impl.tweenApply(storage: storage, key: UUID(), from: 0, to: 2)
        // A spring's overshoot: progress past 1.
        // 彈簧的過衝：進度超過 1。
        apply(1.4)
        #expect(storage.value == 2)
        apply(-0.4)
        #expect(storage.value == 0)
    }

    @MainActor
    @Test("Inside withAnimation, a tweening @State reads back the value assigned")
    func readAfterWriteInsideWithAnimation() throws {
        // `StateImpl` animates only on the main thread; on Linux Swift Testing
        // runs main-actor tests elsewhere, and there is nothing to test.
        // `StateImpl` 只在主執行緒上做動畫;在 Linux 上 Swift Testing 在別處執行 main-actor 測試，那裡沒有東西可測。
        guard Thread.isMainThread else { return }
        let driver = AnimationDriver.shared
        let clock = AnimationDriver.ManualClock()
        driver.manualClock = clock
        defer { driver.manualClock = nil }

        let state = State(wrappedValue: 0)
        withAnimation(.linear(duration: 1)) {
            state.wrappedValue += 1
            state.wrappedValue += 1
            #expect(state.wrappedValue == 2)
        }
        clock.advance(to: 0)
        clock.advance(to: 2)
        #expect(state.wrappedValue == 2)
        #expect(driver.activeTweenCount == 0)
    }

    // MARK: Publisher

    @Test("A publisher survives observing, cancelling and sending from many threads")
    func publisherIsThreadSafe() {
        let publisher = Publisher()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let cancellable = publisher.observe {}
            publisher.send()
            if i % 2 == 0 {
                cancellable.cancel()
            } else {
                cancellable.defuse()
            }
        }
        let flag = Flag()
        let cancellable = publisher.observe { flag.fired += 1 }
        publisher.send()
        #expect(flag.fired == 1)
        cancellable.cancel()
    }

    // MARK: NavigationPath

    @Test("Decoding a path drops an entry with no destination, and those after it")
    func navigationPathDropsUnknownEntries() throws {
        var path = NavigationPath()
        path.append(1)
        path.append("two")
        path.append(3)
        let data = try JSONEncoder().encode(path)
        let decoded = try JSONDecoder().decode(NavigationPath.self, from: data)

        let entries = decoded.path(destinationTypes: [Int.self])
        #expect(entries.count == 1)
        #expect(entries.first as? Int == 1)
    }

    // MARK: Layout

    @MainActor
    @Test("A flexible frame clamps the child or the proposal into min...max")
    func flexibleFrameLength() {
        typealias Frame = FlexibleFrameView<EmptyView>
        #expect(Frame.boundedLength(50, proposed: 300, minimum: nil, maximum: 200) == 200)
        #expect(Frame.boundedLength(50, proposed: 300, minimum: nil, maximum: .infinity) == 300)
        #expect(Frame.boundedLength(50, proposed: 100, minimum: nil, maximum: 200) == 100)
        #expect(Frame.boundedLength(40, proposed: 300, minimum: 100, maximum: nil) == 100)
        #expect(Frame.boundedLength(40, proposed: nil, minimum: nil, maximum: 200) == 40)
        #expect(Frame.boundedLength(250, proposed: nil, minimum: nil, maximum: 200) == 200)
    }

    @MainActor
    @Test("A higher layoutPriority leaves room for lower-priority minimums")
    func layoutPriorityReservesLowerMinimums() {
        let view = HStack(spacing: 0) {
            Color.red.frame(minWidth: 30, maxWidth: .infinity)
            Color.blue.frame(maxWidth: .infinity).layoutPriority(1)
        }
        let result = ViewGraphHelpers.computeLayout(
            of: view, proposedSize: ProposedViewSize(100, 20)
        )
        #expect(result.size.width == 100)
    }

    // MARK: List

    @MainActor
    @Test("A lazy list row's node follows its id, not its index")
    func lazyListRowsAreKeyedById() {
        let backend = ViewGraphHelpers.backend
        let environment = ViewGraphHelpers.environment
        let children = ListViewChildren<EmptyView>()
        let node = AnyViewGraphNode(for: EmptyView(), backend: backend, environment: environment)

        children.place("a", at: 0)
        children.lazyNodes["a"] = node
        children.touch("a")

        // Row "a" moved to index 1 before index 0 was released.
        // 「a」這一列在索引 0 被釋放之前移到了索引 1。
        children.place("a", at: 1)
        children.releaseLazyRow(at: 0)
        #expect(children.lazyNodes["a"] != nil)

        children.releaseLazyRow(at: 1)
        #expect(children.lazyNodes["a"] == nil)

        children.place("b", at: 0)
        children.lazyNodes["b"] = node
        children.touch("b")
        children.retainLazyRows(present: ["c"])
        #expect(children.lazyNodes.isEmpty)
        #expect(children.lazyOrder.isEmpty)
    }

    // MARK: onChange

    struct ChangeProbe: View {
        nonisolated(unsafe) static var changes: [[Int]] = []
        var value: Int
        var body: some View {
            Text("\(value)").onChange(of: value, initial: true) { old, new in
                Self.changes.append([old, new])
            }
        }
    }

    @MainActor
    @Test("onChange with two arguments receives the old value and the new one")
    func onChangeOldAndNew() {
        ChangeProbe.changes = []
        let environment = ViewGraphHelpers.environment
        let node = ViewGraphNode(
            for: ChangeProbe(value: 1), backend: ViewGraphHelpers.backend,
            environment: environment
        )
        _ = node.computeLayout(proposedSize: ProposedViewSize(100, 100), environment: environment)
        _ = node.commit()
        _ = node.computeLayout(
            with: ChangeProbe(value: 2), proposedSize: ProposedViewSize(100, 100),
            environment: environment
        )
        _ = node.commit()
        #expect(ChangeProbe.changes == [[1, 1], [1, 2]])
    }
}
