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
        get { storage.value }
        nonmutating set {
            // An animatable assignment made inside `withAnimation` becomes a
            // tween; everything else is the assignment it always was.
            //
            // The old value is read BEFORE the write, obviously, and the tween
            // closure writes through `storage` rather than capturing `self`: a
            // `StateImpl` is a struct and the closure outlives this call.
            //
            // 一個在 `withAnimation` 內、且型別可動畫的賦值，會變成一次補間;其餘一切仍然是它一向
            // 所是的那個賦值。
            //
            // 舊值當然是在寫入**之前**讀的，而那個補間 closure 是透過 `storage` 寫入、而非捕捉
            // `self`:`StateImpl` 是一個 struct，而該 closure 的生命比這次呼叫更長。
            if let animation = currentAnimation,
                let start = storage.value as? any AnimatableValue,
                let end = newValue as? any AnimatableValue
            {
                animate(from: start, to: end, animation: animation)
                return
            }

            cancelAnyAnimation()
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
                storage.value = self.wrappedValueCast(end as Any)
                storage.postSet()
                return
            }
            let storage = self.storage
            AnimationDriver.shared.start(key: animationKey, animation: animation) { progress in
                let value = V.interpolated(from: start, to: end, progress: progress)
                guard let value = value as? Storage.Value else { return }
                storage.value = value
                storage.postSet()
            }
        }
        run(start)
    }

    private func wrappedValueCast(_ value: Any) -> Storage.Value {
        (value as? Storage.Value) ?? storage.value
    }

    var projectedValue: Binding<Storage.Value> {
        // Specifically link the binding to the inner storage instead of the
        // outer box which changes with each view update.
        let storage = storage
        return Binding(
            get: { storage.value },
            set: { newValue in
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
    /// Additionally updates the downstream observation if the
    /// wrapped value is an `Optional<some ObservableObject>` and the
    /// current case has toggled.
    func postSet() {
        // If the wrapped value is an `Optional<some ObservableObject>`
        // then we need to observe/unobserve whenever the optional
        // toggles between `.some` and `.none`.
        if let value = value as? OptionalObservableObject {
            if let innerDidChange = value.didChange, downstreamObservation == nil {
                downstreamObservation = didChange.link(toUpstream: innerDidChange)
            } else if value.didChange == nil, let observation = downstreamObservation {
                observation.cancel()
                downstreamObservation = nil
            }
        }
        didChange.send()
    }
}
