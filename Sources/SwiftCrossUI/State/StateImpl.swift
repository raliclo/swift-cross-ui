import Foundation
struct StateImpl<Storage: StateStorageProtocol> {
    /// The inner storage of `StateImpl`.
    ///
    /// The inner `Storage` is what stays constant between view updates.
    /// The wrapping box is used so that we can assign the storage to future
    /// state instances from the non-mutating ``update(with:previousValue:)``
    /// method. It's vital that the inner storage remains the same so that
    /// bindings can be stored across view updates.
    var box: Box<Storage>

    var storage: Storage {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    init(initialStorage: Storage) {
        self.box = Box(initialStorage)

        // Before casting the value we check the type, because casting an optional
        // to protocol Optional doesn't conform to can still succeed when the value
        // is `.some` and the wrapped type conforms to the protocol.
        if Storage.Value.self is ObservableObject.Type,
           let value = initialStorage.value as? ObservableObject
        {
            storage.downstreamObservation = storage.didChange.link(toUpstream: value.didChange)
        } else if
            let value = initialStorage.value as? OptionalObservableObject,
            let innerDidChange = value.didChange
        {
            // If we have an `Optional<some ObservableObject>.some`, then observe its
            // inner value's publisher.
            storage.downstreamObservation = storage.didChange.link(toUpstream: innerDidChange)
        }
    }

    /// Identifies this storage to ``AnimationDriver`` for as long as it lives.
    ///
    /// Per BOX, not per `StateImpl`: the `StateImpl` struct is copied every time
    /// the view it belongs to is reconstructed, and a per-copy id would start a
    /// second tween on every update instead of continuing the one in flight.
    ///
    /// 在這份儲存存在期間，用來向 ``AnimationDriver`` 標識它。
    ///
    /// 是逐 **box**、而非逐 `StateImpl`:那個 `StateImpl` struct 在它所屬的 view 每次被重建時都會被
    /// 複製一份，而一個「逐複本」的 id 會在每一次更新時啟動第二個補間，而不是延續飛行中的那一個。
    var animationKey: UUID { box.animationKey }

    var wrappedValue: Storage.Value {
        // Two values exist while a tween runs: the one on screen, in
        // `storage.value`, which the tween writes every frame, and the one last
        // assigned, in `box.animationTarget`.
        //
        // Inside a `withAnimation` body a read returns the assigned value, so
        // `withAnimation { count += 1 }` run twice before the first tween ends
        // adds two, and a value read back after it is assigned is the value
        // assigned. Everywhere else -- a view's `body` above all -- a read
        // returns the value on screen, which is what makes the view animate.
        // A body is never evaluated inside a `withAnimation` body: the update
        // it causes is queued and runs afterwards.
        //
        // 補間進行時存在兩個值：畫面上的那個，在 `storage.value` 中，由補間每一幀寫入;以及最後被賦予的那個，
        // 在 `box.animationTarget` 中。
        //
        // 在 `withAnimation` 的 body 內，讀取回傳被賦予的值，因此在第一個補間結束前執行兩次
        // `withAnimation { count += 1 }` 會加二，而賦值後讀回的就是所賦的值。其他地方——尤其是 view 的
        // `body`——讀取回傳畫面上的值，view 正是因此而有動畫。`body` 永遠不會在 `withAnimation` 的 body
        // 內被求值：它所引發的更新被排入佇列，之後才執行。
        get {
            if let target = box.animationTarget, currentAnimation != nil,
                let target = target as? Storage.Value
            {
                return target
            }
            return storage.value
        }
        nonmutating set {
            // An animatable assignment made inside `withAnimation` becomes a
            // tween; everything else is the assignment it always was.
            //
            // The old value is read BEFORE the write, obviously, and the tween
            // closure writes through `storage` rather than capturing `self`: a
            // `StateImpl` is a struct and the closure outlives this call. The
            // tween starts from the value on screen, so a value re-animated in
            // flight continues from where it is.
            //
            // 一個在 `withAnimation` 內、且型別可動畫的賦值，會變成一次補間;其餘一切仍然是它一向
            // 所是的那個賦值。
            //
            // 舊值當然是在寫入**之前**讀的，而那個補間 closure 是透過 `storage` 寫入、而非捕捉
            // `self`:`StateImpl` 是一個 struct，而該 closure 的生命比這次呼叫更長。補間從畫面上的值出發，
            // 因此飛行途中被重新動畫的值會從它當下所在之處繼續。
            if let animation = currentAnimation,
                let start = storage.value as? any AnimatableValue,
                let end = newValue as? any AnimatableValue
            {
                animate(from: start, to: end, animation: animation)
                return
            }

            // Inside withAnimation but with no value in between: what animates
            // instead is the layout it changes (matchedGeometryEffect), in the
            // update that applies it -- see LayoutTransaction.
            // 在 withAnimation 內、但沒有中間值：改為由它所改變的版面來動畫(matchedGeometryEffect),
            // 於套用它的那次更新中——見 LayoutTransaction。
            if let animation = currentAnimation {
                LayoutTransaction.arm(animation)
            }
            cancelAnyAnimation()
            box.animationTarget = nil
            storage.value = newValue
            storage.postSet()
        }
    }

    /// The animation in force, or `nil` when there is none OR when this
    /// assignment is not on the main thread.
    ///
    /// **Off the main thread is not an error and does not animate.** State can
    /// be written from anywhere; an animation has to be driven by a frame clock,
    /// which is main-actor, so a background assignment lands on its final value.
    /// The alternative -- hopping to the main actor to start a tween -- would
    /// make the value arrive later than the line that set it, which is a far
    /// stranger thing for a caller to debug than "it did not animate".
    ///
    /// 目前適用的動畫;若沒有、**或**這次賦值不在主執行緒上，則為 `nil`。
    ///
    /// **不在主執行緒上並不是錯誤，它只是不會有動畫。** 狀態可以從任何地方被寫入;而一個動畫必須由
    /// frame clock 驅動，那是 main-actor 的——因此一次背景賦值會直接落在它的終值上。另一種做法是
    /// 「跳到 main actor 去啟動一個補間」，那會讓那個值比「設定它的那一行」更晚抵達——對呼叫端而言，
    /// 那比「它沒有動畫」要難除錯得多。
    private var currentAnimation: Animation? {
        guard Thread.isMainThread else { return nil }
        return AnimationTransaction.current
    }

    private func cancelAnyAnimation() {
        guard Thread.isMainThread else { return }
        AnimationDriver.shared.cancel(key: animationKey)
    }

    /// Registers the tween. Opened as a generic so the two values can be
    /// compared and interpolated as their own type rather than as existentials.
    /// 註冊那個補間。以泛型開箱，好讓那兩個值以它們**自己的型別**被比較與插值，而不是以 existential。
    private func animate(
        from start: any AnimatableValue,
        to end: any AnimatableValue,
        animation: Animation
    ) {
        func run<V: AnimatableValue>(_ start: V) {
            guard let end = end as? V else {
                // Two animatable values of different types: not a thing a typed
                // `@State` can produce, and if it ever is, land on the target
                // rather than on nothing.
                // 兩個型別不同的可動畫值:這不是一個有型別的 `@State` 產得出來的情況;而萬一它成真，
                // 就落在目標值上，而不是落在什麼都沒有。
                box.animationTarget = nil
                storage.value = self.wrappedValueCast(end as Any)
                storage.postSet()
                return
            }
            // The target is recorded for reads made inside `withAnimation`
            // (see `wrappedValue`) and forgotten when the tween reaches it.
            // A replaced tween never finishes, and its replacement has
            // already recorded its own target.
            // 記下目標值，供 `withAnimation` 內的讀取使用(見 `wrappedValue`),補間抵達它時忘掉。被取代的補間
            // 永遠不會 finish,而取代它的那一個已經記下了自己的目標。
            let box = box
            box.animationTarget = end
            AnimationDriver.shared.start(
                key: animationKey,
                animation: animation,
                group: AnimationTransaction.group,
                apply: Self.tweenApply(storage: storage, key: animationKey, from: start, to: end),
                finish: { [weak box] in box?.animationTarget = nil }
            )
        }
        run(start)
    }

    /// The tween's per-frame write.
    ///
    /// The storage is held weakly, and a tween whose storage is gone cancels
    /// itself on its next frame. Held strongly, a tween that never ends --
    /// `repeatForever()` -- would keep the state of a removed view alive and
    /// keep the frame clock running for it, since nothing cancels a tween
    /// when its view goes away.
    ///
    /// A function of its own so a test can hold the very closure the driver
    /// gets: on Linux, Swift Testing runs main-actor tests off the main thread,
    /// where assigning `wrappedValue` does not animate at all (measured
    /// 2026-10-22, `Thread.isMainThread` false inside a `@MainActor` test).
    ///
    /// 補間每一幀的寫入。storage 以弱參照持有，storage 已不在的補間會在下一幀自行取消。若以強參照持有，一個永不結束的
    /// 補間——`repeatForever()`——會讓已被移除之 view 的狀態一直存活，並為它持續驅動 frame clock,因為 view 消失時
    /// 沒有任何東西會取消它的補間。獨立成函式，好讓測試能拿到 driver 拿到的同一個閉包：在 Linux 上,
    /// Swift Testing 在主執行緒之外執行 main-actor 測試，而在那裡對 `wrappedValue` 賦值完全不會做動畫(2026-10-22
    /// 實測：`@MainActor` 測試內 `Thread.isMainThread` 為 false)。
    static func tweenApply<V: AnimatableValue>(
        storage: Storage, key: UUID, from start: V, to end: V
    ) -> (Double) -> Void {
        { [weak storage] progress in
            guard let storage else {
                AnimationDriver.shared.cancel(key: key)
                return
            }
            let value = clampedToSpan(
                V.interpolated(from: start, to: end, progress: progress),
                from: start,
                to: end
            )
            guard let value = value as? Storage.Value else { return }
            storage.value = value
            storage.postSet()
        }
    }

    /// `value` kept between `start` and `end` when `V` is an integer type,
    /// and `value` unchanged otherwise.
    ///
    /// A spring or a back-easing curve takes progress past `1` (and below
    /// `0`); for a `Double` that overshoot is the point, but an integer state
    /// is most often an index, and an index one past its target is out of
    /// range. So an integer tween never leaves the span it was asked to cover.
    ///
    /// 當 `V` 是整數型別時，把 `value` 限制在 `start` 與 `end` 之間;其他型別原樣回傳。
    ///
    /// 彈簧或 back 緩動曲線會讓進度超過 `1`(或低於 `0`);對 `Double` 而言，那個過衝正是重點，但整數狀態
    /// 多半是一個索引，而超過目標一格的索引就越界了。因此整數補間永遠不會離開它被要求涵蓋的區間。
    static func clampedToSpan<V>(_ value: V, from start: V, to end: V) -> V {
        guard let integer = value as? any BinaryInteger else { return value }
        func clamp<I: BinaryInteger>(_ value: I) -> V? {
            guard let start = start as? I, let end = end as? I else { return nil }
            return Swift.min(Swift.max(value, Swift.min(start, end)), Swift.max(start, end)) as? V
        }
        return clamp(integer) ?? value
    }

    private func wrappedValueCast(_ value: Any) -> Storage.Value {
        (value as? Storage.Value) ?? storage.value
    }

    var projectedValue: Binding<Storage.Value> {
        // Specifically link the binding to the inner storage instead of the
        // outer box which changes with each view update.
        //
        // A write through the binding is a plain assignment: it ends any tween
        // in flight, so the next frame of that tween does not overwrite it.
        //
        // 特意把 binding 連到內層 storage，而不是每次 view 更新都會換掉的外層 box。
        //
        // 透過 binding 的寫入是一次普通的賦值：它會結束飛行中的補間，使該補間的下一幀不會把它蓋掉。
        let storage = storage
        let box = box
        return Binding(
            get: { storage.value },
            set: { newValue in
                box.animationTarget = nil
                if Thread.isMainThread {
                    AnimationDriver.shared.cancel(key: box.animationKey)
                }
                storage.value = newValue
                storage.postSet()
            }
        )
    }

    func update(with environment: EnvironmentValues, previousValue: Self?) {
        if let previousValue {
            storage = previousValue.storage
        }
    }
}

protocol StateStorageProtocol: AnyObject {
    associatedtype Value
    var value: Value { get set }
    var didChange: Publisher { get }
    var downstreamObservation: Cancellable? { get set }
}

extension StateStorageProtocol {
    /// Call this to publish an observation to all observers after
    /// setting a new value. This isn't in a `didSet` property accessor
    /// because we want more granular control over when it does and
    /// doesn't trigger.
    ///
    /// Additionally points the downstream observation at the object now
    /// held, when the wrapped value is an ``ObservableObject`` or an
    /// `Optional<some ObservableObject>`: the old link is cancelled and a
    /// new one made on every assignment, so replacing one object with
    /// another (`objA` → `objB`, or `.some(objA)` → `.some(objB)`) observes
    /// the new object and stops observing the old one, and `.none` observes
    /// nothing.
    ///
    /// 設定新值之後呼叫它，以向所有觀察者發布一次觀察。不放在 `didSet` 存取器中，是因為我們想更細緻地
    /// 控制它何時觸發、何時不觸發。
    ///
    /// 此外，當包裝的值是 ``ObservableObject`` 或 `Optional<some ObservableObject>` 時，把下游觀察
    /// 指向目前持有的物件：每次賦值都取消舊的連結並建立新的，因此以另一個物件取代原物件(`objA` → `objB`,
    /// 或 `.some(objA)` → `.some(objB)`)時，會觀察新物件、不再觀察舊物件;`.none` 則什麼都不觀察。
    func postSet() {
        // Before casting the value we check the type, for the reason given
        // in `StateImpl.init`.
        // 轉型之前先檢查型別，理由見 `StateImpl.init`。
        let observesObject: Bool
        let upstream: Publisher?
        if let value = value as? OptionalObservableObject {
            observesObject = true
            upstream = value.didChange
        } else if Value.self is ObservableObject.Type, let object = value as? ObservableObject {
            observesObject = true
            upstream = object.didChange
        } else {
            observesObject = false
            upstream = nil
        }
        if observesObject {
            downstreamObservation?.cancel()
            downstreamObservation = upstream.map { didChange.link(toUpstream: $0) }
        }
        didChange.send()
    }
}
