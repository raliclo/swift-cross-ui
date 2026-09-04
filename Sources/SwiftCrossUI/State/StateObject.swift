/// A property wrapper that creates an ``ObservableObject`` once and keeps it for
/// the lifetime of the view.
///
/// ``State`` already forwards an observable's `didChange`, so
/// `@State var model = Model()` has worked for some time. What it does not do is
/// stop `Model()` from being *evaluated* on every view update -- the value is
/// built, then thrown away when ``StateImpl/update(with:previousValue:)`` swaps
/// the previous storage back in. For a plain struct that is a wasted
/// initialiser. For a model object that opens a file, starts a timer or issues a
/// request from `init`, it is a side effect per keystroke.
///
/// `@StateObject` closes exactly that gap: the initialiser arrives as an
/// `@autoclosure` and is called at most once, on first access. Everything else
/// -- the storage carried across updates, the link to the object's publisher --
/// is ``State``'s existing mechanism.
///
/// ```swift
/// struct CounterView: View {
///     @StateObject var model = CounterModel()   // CounterModel() runs once
///
///     var body: some View {
///         Button("count: \(model.count)") { model.count += 1 }
///     }
/// }
/// ```
///
/// Use `@StateObject` where the view **owns** the object and `@ObservedObject`
/// where it was handed one. Getting that backwards is not a compile error and
/// not a visible fault either: an owned object declared `@ObservedObject` is
/// rebuilt whenever the parent's body runs, which reads as state that
/// mysteriously resets.
///
/// 一個屬性包裝器，只建立 ``ObservableObject`` 一次，並在該 view 的整個生命週期中保留它。
///
/// ``State`` 本來就會轉發 observable 的 `didChange`，因此 `@State var model = Model()`
/// 早已可用。它沒有做到的是阻止 `Model()` 在每次 view 更新時**被求值**——值被建立出來，然後在
/// ``StateImpl/update(with:previousValue:)`` 換回先前的儲存體時被丟棄。對一個單純的 struct
/// 而言那只是浪費一次初始化；但對一個會在 `init` 裡開檔案、啟動計時器或發出請求的 model 物件而言，
/// 那是每敲一個鍵就發生一次的副作用。
///
/// `@StateObject` 正是用來補上這個缺口：初始化式以 `@autoclosure` 傳入，且最多只在第一次存取時
/// 被呼叫一次。其餘的部分——跨更新保留的儲存體、與物件 publisher 的連結——都是 ``State`` 既有的
/// 機制。
///
/// 當 view **擁有**該物件時用 `@StateObject`，當物件是別人交給它的時候用 `@ObservedObject`。
/// 把兩者用反不會產生編譯錯誤，也不會產生看得見的故障：一個被宣告為 `@ObservedObject` 的自有物件
/// 會在父層 body 執行時重建，其表現是「狀態莫名其妙被重設」。
@propertyWrapper
public struct StateObject<Value: ObservableObject>: ObservableProperty {
    private final class Storage {
        /// Cleared as soon as it has been called, so the reference the closure
        /// captured cannot be held for the life of the view.
        /// 一經呼叫立即清除，使該閉包所捕獲的參考不會被保留至 view 的生命週期結束。
        private var make: (() -> Value)?
        private var made: Value?

        let didChange = Publisher()
        private var upstream: Cancellable?

        init(_ make: @escaping () -> Value) {
            self.make = make
        }

        var value: Value {
            get {
                if let made {
                    return made
                }
                let value = make!()
                make = nil
                adopt(value)
                return value
            }
            set {
                make = nil
                adopt(newValue)
            }
        }

        /// Stores the object and re-points the publisher chain at it.
        ///
        /// The `upstream?.cancel()` is not tidying up. `ObservableObject`'s
        /// default `didChange` builds a FRESH publisher on every access, so a
        /// second `link` without cancelling the first leaves both chains live
        /// and every change arrives twice -- which produces two view updates
        /// instead of one and reports nothing anywhere.
        ///
        /// 儲存該物件，並把 publisher 鏈重新指向它。
        ///
        /// `upstream?.cancel()` 不是在做清理。`ObservableObject` 的預設 `didChange`
        /// **每次存取都會產生一個全新的 publisher**，因此若不取消前一條就再 `link` 一次，兩條鏈
        /// 都會存活，每個變更都會抵達兩次——結果是一次更新變成兩次，而且任何地方都不會回報這件事。
        private func adopt(_ value: Value) {
            made = value
            upstream?.cancel()
            upstream = didChange.link(toUpstream: value.didChange)
        }
    }

    private let box: Box<Storage>

    public var didChange: Publisher { box.value.didChange }

    public var wrappedValue: Value { box.value.value }

    public var projectedValue: Binding<Value> {
        let storage = box.value
        return Binding(
            get: { storage.value },
            set: { newValue in
                storage.value = newValue
                storage.didChange.send()
            }
        )
    }

    public init(wrappedValue make: @autoclosure @escaping () -> Value) {
        box = Box(Storage(make))
    }

    public func update(with environment: EnvironmentValues, previousValue: StateObject<Value>?) {
        if let previousValue {
            // Carrying the whole storage is what keeps this instance's own
            // `make` closure from ever being called -- and it is also what keeps
            // `didChange` identical across updates, which the view graph
            // requires: `ViewGraphNode` subscribes to it once, at node creation.
            // 整個儲存體被沿用，正是此實例自己的 `make` 閉包永遠不會被呼叫的原因——同時也讓
            // `didChange` 在各次更新間維持為同一個物件，而那是 view graph 的要求：
            // `ViewGraphNode` 只在建立節點時訂閱它一次。
            box.value = previousValue.box.value
        }
    }
}
