import CGtk

open class GObject: GObjectRepresentable {
    public var gobjectPointer: UnsafeMutablePointer<CGtk.GObject>

    public var opaquePointer: OpaquePointer? {
        return OpaquePointer(gobjectPointer)
    }

    public init<T>(_ pointer: UnsafeMutablePointer<T>?) {
        gobjectPointer = pointer!.cast()
        g_object_ref(gobjectPointer)
    }

    public init(_ pointer: OpaquePointer) {
        gobjectPointer = UnsafeMutablePointer(pointer)
        g_object_ref(gobjectPointer)
    }

    deinit {
        // disconnect all GTK signal handlers before releasing the object
        // to prevent callbacks firing on deallocated Swift wrapper instances.
        for (id, _) in signals {
            g_signal_handler_disconnect(gobjectPointer, id)
        }

        g_object_unref(gobjectPointer)
    }

    // `gulong`, not `UInt`: they differ on Windows, where `long` is 32 bits.
    // See the note in Callbacks/Signals.swift.
    private var signals: [(gulong, Any)] = []

    /// GObject signals sometimes get invoked when you programmatically set
    /// something. If you don't want them to, you can temporarily disable
    /// them, by adding the signal name here and wrapping the set operation
    /// in ``GObject/withBlockedSignal(named:block:)``.
    ///
    /// We made blocking support opt in to save memory and computation.
    public static let blockableSignalNames: Set<String> = [
        "changed",
        "notify::active",
        "toggled",
        "value-changed",
    ]

    /// Stores the signal handler ID of the handler that we have registered for
    /// a given signal name.
    private var blockableSignalIDs: [String: gulong] = [:]

    open func registerSignals() {}

    func removeSignals() {
        for (handlerId, _) in signals {
            disconnectSignal(gobjectPointer, handlerId: handlerId)
        }

        signals = []
        blockableSignalIDs = [:]
    }

    /// Adds a signal that is not carrying any additional information.
    func addSignal(name: String, callback: @escaping () -> Void) {
        let box = SignalBox0(callback: callback)
        let handler:
            @convention(c) (
                UnsafeMutableRawPointer,
                UnsafeMutableRawPointer
            ) -> Void = { _, data in
                let box = Unmanaged<SignalBox0>.fromOpaque(data).takeUnretainedValue()
                box.callback()
            }

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: unsafeBitCast(handler, to: GCallback.self)
        )

        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1>(name: String, handler: GCallback, callback: @escaping (T1) -> Void) {
        let box = SignalBox1(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1, T2>(name: String, handler: GCallback, callback: @escaping (T1, T2) -> Void) {
        let box = SignalBox2(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1, T2, T3>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2, T3) -> Void
    ) {
        let box = SignalBox3(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    // Signals that return a value. Separate from the void overloads above
    // because the box has to keep a callback with a return type -- see the note
    // on ReturningSignalBox0 (issue #594). Named distinctly rather than
    // overloaded on the callback's return type, which Swift cannot disambiguate
    // at the call sites the generator emits.
    //
    // 有回傳值的 signal。與上方的 void 多載分開，因為其 box 必須保存一個帶有回傳型別的 callback
    // ——見 ReturningSignalBox0 的說明（issue #594）。採用不同名稱而非以 callback 回傳型別多載，
    // 因為 Swift 無法在產生器所輸出的呼叫端消解該多載。

    func addReturningSignal<R>(
        name: String,
        handler: GCallback,
        callback: @escaping () -> R
    ) {
        let box = ReturningSignalBox0(callback: callback)
        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )
        storeHandler(handlerId, box: box, for: name)
    }

    func addReturningSignal<T1, R>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1) -> R
    ) {
        let box = ReturningSignalBox1(callback: callback)
        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )
        storeHandler(handlerId, box: box, for: name)
    }

    func addReturningSignal<T1, T2, R>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2) -> R
    ) {
        let box = ReturningSignalBox2(callback: callback)
        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )
        storeHandler(handlerId, box: box, for: name)
    }

    func addReturningSignal<T1, T2, T3, R>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2, T3) -> R
    ) {
        let box = ReturningSignalBox3(callback: callback)
        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )
        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1, T2, T3, T4>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2, T3, T4) -> Void
    ) {
        let box = SignalBox4(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1, T2, T3, T4, T5>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2, T3, T4, T5) -> Void
    ) {
        let box = SignalBox5(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    func addSignal<T1, T2, T3, T4, T5, T6>(
        name: String,
        handler: GCallback,
        callback: @escaping (T1, T2, T3, T4, T5, T6) -> Void
    ) {
        let box = SignalBox6(callback: callback)

        let handlerId = connectSignal(
            gobjectPointer,
            name: name,
            data: Unmanaged.passUnretained(box).toOpaque(),
            handler: handler
        )

        storeHandler(handlerId, box: box, for: name)
    }

    private func storeHandler(_ id: gulong, box: Any, for signalName: String) {
        signals.append((id, box))
        if Self.blockableSignalNames.contains(signalName) {
            blockableSignalIDs[signalName] = id
        }
    }

    /// Executes a closure while temporarily suppressing a specific signal handler.
    /// You can only block signals included in ``GObject/blockableSignalNames``.
    ///
    /// - Parameters:
    ///   - signalName: The name of the GObject signal to block (e.g. "changed").
    ///   - block: The closure to execute while the signal is suppressed.
    /// - Note: If no signal ID is stored for the given name, the block executes
    ///   normally without suppression.
    public func withBlockedSignal(
        named signalName: String,
        block: @escaping () -> Void
    ) {
        guard let signalID = blockableSignalIDs[signalName] else {
            if !Self.blockableSignalNames.contains(signalName) {
                print(
                    """
                    Warning: Could not block signal '\(signalName)' because it \
                    is not included in GObject.blockableSignalNames.
                    """
                )
            }
            block()
            return
        }

        g_signal_handler_block(gobjectPointer, signalID)
        block()
        g_signal_handler_unblock(gobjectPointer, signalID)
    }
}
