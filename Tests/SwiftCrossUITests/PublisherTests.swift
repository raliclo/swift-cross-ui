import Testing
import Foundation

@testable import SwiftCrossUI
import DummyBackend

#if canImport(AppKitBackend)
    @testable import AppKitBackend
#endif

@Suite("Publisher-related tests")
struct PublisherTests {
    @Test("Ensures that basic Publisher operations can be observed")
    func testPublisherObservation() {
        class NestedState: SwiftCrossUI.ObservableObject {
            @SwiftCrossUI.Published
            var count = 0
        }

        class MyState: SwiftCrossUI.ObservableObject {
            @SwiftCrossUI.Published
            var count = 0
            @SwiftCrossUI.Published
            var publishedNestedState = NestedState()
            var unpublishedNestedState = NestedState()
        }

        let state = MyState()
        var observedChange = false
        let cancellable = state.didChange.observe {
            observedChange = true
        }

        // Ensures that published value type mutation triggers observation
        observedChange = false
        state.count += 1
        #expect(observedChange, "Expected value type mutation to trigger observation")

        // Ensure that published nested ObservableObject triggers observation
        observedChange = false
        state.publishedNestedState.count += 1
        #expect(
            observedChange,
            "Expected nested published observable object mutation to trigger observation"
        )

        // Ensure that replacing published nested ObservableObject triggers observation
        observedChange = false
        state.publishedNestedState = NestedState()
        #expect(
            observedChange,
            "Expected replacing nested published observable object to trigger observation"
        )

        // Ensure that replaced published nested ObservableObject triggers observation
        observedChange = false
        state.publishedNestedState.count += 1
        #expect(
            observedChange,
            "Expected replaced nested published observable object mutation to trigger observation"
        )

        // Ensure that non-published nested ObservableObject doesn't trigger observation
        observedChange = false
        state.unpublishedNestedState.count += 1
        #expect(
            !observedChange,
            "Expected nested unpublished observable object mutation to not trigger observation"
        )

        // Ensure that cancelling the observation prevents future observations
        cancellable.cancel()
        observedChange = false
        state.count += 1
        #expect(!observedChange, "Expected mutation not to trigger cancelled observation")
    }

    #if canImport(AppKitBackend)
        // TODO: Create mock backend so that this can be tested on all platforms. There's
        //   nothing AppKit-specific about it.
        @Test("Ensure that Publisher.observeAsUIUpdater throttles observations")
        func testThrottledPublisherObservation() async {
            class MyState: SwiftCrossUI.ObservableObject {
                @SwiftCrossUI.Published
                var count = 0
            }

            /// A thread-safe count.
            actor Count {
                var count = 0

                func update(_ action: (Int) -> Int) {
                    count = action(count)
                }
            }

            // Number of mutations to perform
            let mutationCount = 20
            // Length of each fake state update
            let updateDuration = 0.02
            // Delay between observation-causing state mutations
            let mutationGap = 0.01

            let state = MyState()
            let updateCount = Count()

            let backend = await AppKitBackend()
            let cancellable = state.didChange.observeAsUIUpdater(backend: backend) {
                Task {
                    await updateCount.update { $0 + 1 }
                }
                // Simulate an update of duration `updateDuration` seconds
                Thread.sleep(forTimeInterval: updateDuration)
            }
            _ = cancellable // Silence warning about cancellable being unused

            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<mutationCount {
                state.count += 1
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * mutationGap))
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start

            // Compute percentage of main thread's time taken up by updates.
            let ratio = Double(await updateCount.count) * updateDuration / elapsed
            #expect(
                ratio <= 0.85,
                """
                Expected throttled updates to take under 85% of the main \
                thread's time. Took \(Int(ratio * 100))%
                """
            )
        }
    #endif

    /// Two properties of one view node share an update slot, so writes to both in
    /// one turn of the main queue run ONE update. P97 wrote eight `@State` rows per
    /// animation frame and ran eight full updates of its root, about 10 ms each,
    /// until the node passed one slot for all of them (2026-10-20). The control
    /// keeps a slot per observation and must still see two.
    /// 同一個 view 節點的兩個屬性共用一個更新名額，所以在主佇列的同一輪寫入兩者只會跑**一次**更新。P97 每個
    /// 動畫幀寫入八個 `@State`,在節點為全部屬性傳入同一個名額之前，根節點要完整更新八次、每次約 10 毫秒
    /// (2026-10-20)。對照組每個訂閱各有名額，仍必須看到兩次。
    @Test("Observations sharing one slot merge into one update")
    @MainActor
    func testSharedSlotMergesUpdates() async {
        class TwoValues: SwiftCrossUI.ObservableObject {
            @SwiftCrossUI.Published var first = 0
            @SwiftCrossUI.Published var second = 0
        }

        @MainActor final class Counter { var count = 0 }

        func updates(sharingSlot: Bool) async -> Int {
            let backend = DummyBackend()
            let first = TwoValues()
            let second = TwoValues()
            let counter = Counter()
            let slot = DispatchSemaphore(value: 1)
            let cancellables = [
                first.didChange.observeAsUIUpdater(
                    backend: backend, slot: sharingSlot ? slot : DispatchSemaphore(value: 1)
                ) { counter.count += 1 },
                second.didChange.observeAsUIUpdater(
                    backend: backend, slot: sharingSlot ? slot : DispatchSemaphore(value: 1)
                ) { counter.count += 1 },
            ]
            first.first = 1
            second.second = 1
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = cancellables
            return counter.count
        }

        #expect(await updates(sharingSlot: true) == 1)
        #expect(await updates(sharingSlot: false) == 2)
    }
}
