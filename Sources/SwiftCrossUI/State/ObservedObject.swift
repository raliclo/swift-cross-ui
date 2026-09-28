/// A property wrapper for an ``ObservableObject`` the view was handed rather
/// than one it owns.
///
/// The counterpart to ``StateObject``. The difference is ownership and it
/// decides which of the two you want:
///
/// - `@StateObject` **creates** the object and keeps it. The initialiser runs
///   once.
/// - `@ObservedObject` **adopts** whatever the enclosing view was constructed
///   with, on every update, and subscribes to it. It creates nothing.
///
/// ```swift
/// struct RowView: View {
///     @ObservedObject var model: RowModel   // passed in by the parent
///
///     var body: some View {
///         Text(model.title)
///     }
/// }
/// ```
///
/// **Why this is not just a stored property.** A plain `let model: RowModel`
/// compiles, renders correctly the first time, and then never updates again --
/// nothing subscribes to the object's publisher, so a change to `model.title`
/// reaches no one. That failure has no error attached to it at any layer: the
/// object mutates, the view simply does not redraw.
///
/// 一個屬性包裝器，用於「由外部交給該 view」而非「該 view 自己擁有」的 ``ObservableObject``。
///
/// 它是 ``StateObject`` 的對應物。兩者的差別在於所有權，而所有權決定你要用哪一個：
///
/// - `@StateObject` **建立**該物件並保留它，初始化式只執行一次。
/// - `@ObservedObject` 在每次更新時**採用**外層 view 建構時所帶入的那個物件，並訂閱它。它不建立
///   任何東西。
///
/// **為何這不能只寫成一個一般的儲存屬性。** 單純寫 `let model: RowModel` 能編譯、第一次也能正確
/// 繪出，然後就再也不會更新——沒有任何東西訂閱該物件的 publisher，因此對 `model.title` 的修改
/// 不會傳達給任何人。這個失敗在每一層都不附帶任何錯誤：物件確實變了，view 只是不重繪。
@propertyWrapper
public struct ObservedObject<Value: ObservableObject>: ObservableProperty {
    private final class Storage {
        var value: Value

        /// Must outlive every view update, because ``ViewGraphNode`` subscribes
        /// to it exactly once, when the node is created.
        /// 必須比每一次 view 更新都活得久，因為 ``ViewGraphNode`` 只在節點建立時訂閱它一次。
        let didChange = Publisher()
        private var upstream: Cancellable?

        init(_ value: Value) {
            self.value = value
            relink()
        }

        /// Points the publisher chain at the object currently in `value`.
        ///
        /// The `cancel()` matters for the reason spelled out in
        /// ``StateObject``: `ObservableObject`'s default `didChange` returns a
        /// new publisher on every access, so linking twice without cancelling
        /// delivers every change twice.
        ///
        /// 把 publisher 鏈指向目前存放在 `value` 中的物件。
        ///
        /// 那個 `cancel()` 的重要性，理由已寫在 ``StateObject`` 中：`ObservableObject` 的預設
        /// `didChange` 每次存取都回傳一個新的 publisher，因此不取消就連第二次，會讓每個變更被
        /// 送達兩次。
        func relink() {
            upstream?.cancel()
            upstream = didChange.link(toUpstream: value.didChange)
        }
    }

    private let box: Box<Storage>

    public var didChange: Publisher { box.value.didChange }

    public var wrappedValue: Value {
        get { box.value.value }
        nonmutating set {
            box.value.value = newValue
            box.value.relink()
            box.value.didChange.send()
        }
    }

    public var projectedValue: Binding<Value> {
        let storage = box.value
        return Binding(
            get: { storage.value },
            set: { newValue in
                storage.value = newValue
                storage.relink()
                storage.didChange.send()
            }
        )
    }

    public init(wrappedValue: Value) {
        box = Box(Storage(wrappedValue))
    }

    public func update(with environment: EnvironmentValues, previousValue: ObservedObject<Value>?) {
        guard let previousValue else { return }

        // The storage is carried over so that `didChange` keeps its identity,
        // but the VALUE is not: this instance was just constructed with whatever
        // the parent passed this time round, and that is the object to observe.
        // Taking the previous storage wholesale -- which is what ``State`` and
        // ``StateObject`` correctly do -- would pin the view to the object it
        // saw first and silently ignore every later one the parent handed it.
        //
        // 沿用儲存體是為了讓 `didChange` 保持同一個身分，但**值**不沿用：此實例剛剛才以父層這一輪
        // 傳進來的東西建構完成，而那才是應該被觀察的物件。整份接收先前的儲存體——那是 ``State``
        // 與 ``StateObject`` 正確的做法——會把這個 view 釘死在它最初看到的那個物件上，並靜默忽略
        // 父層此後交給它的每一個。
        //
        // **Except an object nobody else holds.** This framework re-creates a view
        // struct far more often than SwiftUI: every layout pass evaluates `body`,
        // and a child's resize lays its parent out again, so a view's OWN @State
        // change rebuilds it from its parent. An inline `@ObservedObject var m =
        // Model()` then arrived as a brand-new Model each time and replaced the
        // one holding the app's data -- measured 2026-09-28 with P45: the model
        // constructed 8 times in one run, and a button that wrote @State and the
        // model left the model's writes at 0.
        //
        // An object a parent really passed down is one the parent holds too, so
        // its reference count is at least two. One that only this wrapper's
        // storage references was built by the wrapper's own initial-value
        // expression during this re-creation, and cannot be "the parent's next
        // object"; adopting it would only discard the carried one's state. So the
        // carried object is kept. A parent that switches to an object it keeps --
        // the case the paragraph above protects -- is still adopted.
        //
        // **除非那個物件沒有別人持有。**本框架重建 view struct 的頻率遠高於 SwiftUI:每次排版都會求值
        // `body`,子節點改變尺寸會讓父節點重新排版,所以 view **自己的** @State 改變就會讓父層重建它。內嵌的
        // `@ObservedObject var m = Model()` 於是每次都以全新的 Model 抵達,並取代掌握 app 資料的那一個——
        // 2026-09-28 以 P45 實測:一次執行建構了 8 次 model,一顆同時寫 @State 與 model 的按鈕讓 model 的
        // writes 停在 0。父層真正傳下來的物件,父層自己也持有,參考計數至少為二;只被這個 wrapper 的儲存體參考
        // 的物件,是 wrapper 自己的初始值運算式在這次重建中建出來的,不可能是「父層的下一個物件」,採用它只會
        // 丟掉沿用那一個的狀態。所以保留沿用的物件。父層改用一個它自己持有的物件——上一段所保護的情況——仍會被採用。
        let incomingStorage = box.value
        let carried = previousValue.box.value
        if carried.value !== incomingStorage.value,
            !isKnownUniquelyReferenced(&incomingStorage.value)
        {
            carried.value = incomingStorage.value
            carried.relink()
        }
        box.value = carried
    }
}
