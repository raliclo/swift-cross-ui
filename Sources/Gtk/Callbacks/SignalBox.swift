//
//  Copyright © 2016 Tomas Linhart. All rights reserved.
//

import CGtk

protocol SignalBox {
    associatedtype CallbackType
    var callback: CallbackType { get }
    init(callback: CallbackType)
}

func gCallback<T>(_ closure: T) -> GCallback {
    return unsafeBitCast(closure, to: GCallback.self)
}

class SignalBox0: SignalBox {
    typealias CallbackType = () -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }
}

// Boxes for signals that return a value, which the plain SignalBoxN above
// cannot express -- their callbacks are all `-> Void`, so the handler returned
// nothing and GTK read whatever the ABI left behind. For a `gboolean` signal
// that means the handler could never say "handled, stop here": `key-pressed`
// always propagated, and `format-value` could not be wired up at all because
// GTK frees a string the handler was supposed to return. That is issue #594.
//
// Arities 0 through 3 only, which covers every returning signal in the classes
// the generator emits (measured from the GIR: 9 signals, all 0-3 parameters).
// The generator falls back to the void form for anything else, so an unhandled
// arity is a compile error in generated code rather than a silent wrong return.
//
// 用於「有回傳值」的 signal 的 box——上方一般的 SignalBoxN 無法表達，因為其 callback 全為
// `-> Void`，處理常式不回傳任何東西，GTK 讀到的是 ABI 遺留的內容。對 `gboolean` signal 而言，
// 這代表處理常式永遠無法表示「已處理，到此為止」：`key-pressed` 總是繼續傳播，而 `format-value`
// 根本無法接上，因為 GTK 會去釋放一個處理常式本應回傳的字串。此即 issue #594。
//
// 僅提供 arity 0 至 3，已涵蓋產生器所輸出類別中的每一個有回傳值的 signal（由 GIR 量測：9 個
// signal，參數皆為 0-3 個）。產生器對其餘情況回退為 void 形式，因此未支援的 arity 會在產生的
// 程式碼中造成編譯錯誤，而非悄悄回傳錯誤的值。

class ReturningSignalBox0<R>: SignalBox {
    typealias CallbackType = () -> R

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(_ data: UnsafeMutableRawPointer) -> R {
        let box = Unmanaged<ReturningSignalBox0<R>>.fromOpaque(data)
            .takeUnretainedValue()
        return box.callback()
    }
}

class ReturningSignalBox1<T1, R>: SignalBox {
    typealias CallbackType = (T1) -> R

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(_ data: UnsafeMutableRawPointer, _ value1: T1) -> R {
        let box = Unmanaged<ReturningSignalBox1<T1, R>>.fromOpaque(data)
            .takeUnretainedValue()
        return box.callback(value1)
    }
}

class ReturningSignalBox2<T1, T2, R>: SignalBox {
    typealias CallbackType = (T1, T2) -> R

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(_ data: UnsafeMutableRawPointer, _ value1: T1, _ value2: T2) -> R {
        let box = Unmanaged<ReturningSignalBox2<T1, T2, R>>.fromOpaque(data)
            .takeUnretainedValue()
        return box.callback(value1, value2)
    }
}

class ReturningSignalBox3<T1, T2, T3, R>: SignalBox {
    typealias CallbackType = (T1, T2, T3) -> R

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(
        _ data: UnsafeMutableRawPointer,
        _ value1: T1,
        _ value2: T2,
        _ value3: T3
    ) -> R {
        let box = Unmanaged<ReturningSignalBox3<T1, T2, T3, R>>.fromOpaque(data)
            .takeUnretainedValue()
        return box.callback(value1, value2, value3)
    }
}

class SignalBox1<T1>: SignalBox {
    typealias CallbackType = (T1) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(_ data: UnsafeMutableRawPointer, _ value1: T1) {
        let box = Unmanaged<SignalBox1<T1>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1)
    }
}

class SignalBox2<T1, T2>: SignalBox {
    typealias CallbackType = (T1, T2) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(_ data: UnsafeMutableRawPointer, _ value1: T1, _ value2: T2) {
        let box = Unmanaged<SignalBox2<T1, T2>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1, value2)
    }
}

class SignalBox3<T1, T2, T3>: SignalBox {
    typealias CallbackType = (T1, T2, T3) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(
        _ data: UnsafeMutableRawPointer,
        _ value1: T1,
        _ value2: T2,
        _ value3: T3
    ) {
        let box = Unmanaged<SignalBox3<T1, T2, T3>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1, value2, value3)
    }
}

class SignalBox4<T1, T2, T3, T4>: SignalBox {
    typealias CallbackType = (T1, T2, T3, T4) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(
        _ data: UnsafeMutableRawPointer,
        _ value1: T1,
        _ value2: T2,
        _ value3: T3,
        _ value4: T4
    ) {
        let box = Unmanaged<SignalBox4<T1, T2, T3, T4>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1, value2, value3, value4)
    }
}

class SignalBox5<T1, T2, T3, T4, T5>: SignalBox {
    typealias CallbackType = (T1, T2, T3, T4, T5) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(
        _ data: UnsafeMutableRawPointer,
        _ value1: T1,
        _ value2: T2,
        _ value3: T3,
        _ value4: T4,
        _ value5: T5
    ) {
        let box = Unmanaged<SignalBox5<T1, T2, T3, T4, T5>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1, value2, value3, value4, value5)
    }
}

class SignalBox6<T1, T2, T3, T4, T5, T6>: SignalBox {
    typealias CallbackType = (T1, T2, T3, T4, T5, T6) -> Void

    let callback: CallbackType

    required init(callback: @escaping CallbackType) {
        self.callback = callback
    }

    static func run(
        _ data: UnsafeMutableRawPointer,
        _ value1: T1,
        _ value2: T2,
        _ value3: T3,
        _ value4: T4,
        _ value5: T5,
        _ value6: T6
    ) {
        let box = Unmanaged<SignalBox6<T1, T2, T3, T4, T5, T6>>.fromOpaque(data)
            .takeUnretainedValue()
        box.callback(value1, value2, value3, value4, value5, value6)
    }
}
