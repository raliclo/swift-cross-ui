/// A property wrapper used to access environment values within a ``View`` or
/// ``App``.
///
/// Must not be used before the view graph accesses the view or app's `body`
/// (so, don't access it from an initializer).
///
/// ```swift
/// struct ContentView: View {
///     @Environment(\.colorScheme) var colorScheme
///
///     var body: some View {
///         Text("Current color scheme: \(colorScheme)")
///             .background(colorScheme == .light ? Color.black : Color.white)
///     }
/// }
/// ```
///
/// The environment also contains UI-related actions, such as the
/// ``EnvironmentValues/chooseFile`` action used to present 'Open file' dialogs.
///
/// ```swift
/// struct ContentView: View {
///     @Environment(\.chooseFile) var chooseFile
///
///     var body: some View {
///         Button("Open") {
///             Task {
///                 guard let file = await chooseFile() else {
///                     print("No file chosen")
///                     return
///                 }
///
///                 print("The user chose: \(file.path)")
///             }
///         }
///     }
/// }
/// ```
///
/// ## Reading an object by its type
///
/// `@Environment(Model.self)` reads an object that an ancestor placed with
/// ``View/environmentObject(_:)`` or ``Scene/environmentObject(_:)``, and
/// **redraws the view whenever that object publishes**. It is the modern
/// SwiftUI spelling of ``EnvironmentObject``, and since 2026-09-08 the two
/// behave identically; the older wrapper stays because
/// `@EnvironmentObject var model: Model` is still valid SwiftUI and is still
/// what a lot of existing code says.
///
/// ```swift
/// struct DeepChild: View {
///     @Environment(Session.self) var session
///
///     var body: some View {
///         Text(session.username)
///     }
/// }
/// ```
///
/// **Why the observation had to be added rather than documented away.** Until
/// 2026-09-08 this wrapper was only a ``DynamicProperty``. ``ViewGraphNode``
/// subscribes to every field that is an ``ObservableProperty`` and to nothing
/// else, so there was nothing here for it to subscribe to: the view rendered
/// once with correct data and then stayed stale for the rest of the process,
/// with no error at any layer. That is exactly the failure ``ObservedObject``
/// describes for a plain stored property, reached by a different route --
/// and a stale view is indistinguishable from a correct one until the moment
/// the data was supposed to move.
///
/// ## When nothing supplied the object
///
/// Reading the property logs the type and the fix, then traps. The reasoning
/// for trapping rather than degrading -- and why that does not contradict this
/// repository's `CLAUDE.md` rule about shipped backends -- is written out on
/// ``EnvironmentObject``, which reaches the same slot and makes the same
/// choice. What matters here is that the message **names the type and the
/// modifier that was forgotten**. It did not until 2026-09-08: the lookup was
/// force-cast with `as!` inside ``update(with:previousValue:)``, so a missing
/// object aborted the process before ``wrappedValue`` was ever reached, with
/// whatever the runtime says about an unexpected `nil` and not one word about
/// `Model` or `.environmentObject(_:)`.
///
/// ## 以型別讀取一個物件
///
/// `@Environment(Model.self)` 會讀取由祖先以 ``View/environmentObject(_:)`` 或
/// ``Scene/environmentObject(_:)`` 放入的物件，並在**該物件每次發佈變更時重繪該 view**。
/// 這是 ``EnvironmentObject`` 在 SwiftUI 中較新的寫法；自 2026-09-08 起兩者行為完全一致。
/// 舊的包裝器仍然保留，因為 `@EnvironmentObject var model: Model` 在 SwiftUI 中依然合法，
/// 也依然是大量既有程式碼的寫法。
///
/// **為何必須把觀察實作出來，而不是用文件把它說過去。** 在 2026-09-08 之前，本包裝器只是一個
/// ``DynamicProperty``。``ViewGraphNode`` 只訂閱身為 ``ObservableProperty`` 的欄位，其餘一律不訂閱，
/// 因此此處根本沒有東西可供它訂閱：view 會以正確資料繪出一次，然後在該行程的剩餘生命中永遠停滯，
/// 而任何一層都不會產生錯誤。這正是 ``ObservedObject`` 針對「一般儲存屬性」所描述的那種失敗，只是
/// 經由另一條路徑抵達——而一個停滯的 view 與一個正確的 view，在資料本該變動的那一刻之前完全無法
/// 分辨。
///
/// ## 當沒有任何人提供該物件時
///
/// 讀取該屬性會先記錄型別與修正方式，然後中止。「為何中止而非降級」，以及「為何這不牴觸本專案
/// `CLAUDE.md` 對已發布 backend 的規則」，完整理由寫在 ``EnvironmentObject`` 上——它讀的是同一個
/// 位置，也做了同樣的選擇。此處真正的重點是：那則訊息會**指名型別與被遺忘的那個 modifier**。
/// 在 2026-09-08 之前並非如此：查找結果在 ``update(with:previousValue:)`` 裡被 `as!` 強制轉型，
/// 因此物件不存在時，行程會在 ``wrappedValue`` 被觸及之前就中止，只留下執行期對「非預期的 `nil`」
/// 的說法，而關於 `Model` 或 `.environmentObject(_:)` 則一個字也沒有。
@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    private let mode: Mode

    /// Everything about this property that has to outlive the view struct.
    ///
    /// A view's `body` running builds a brand new `Environment` value -- many
    /// times a second while anything is animating -- so whatever is kept in the
    /// struct itself is discarded that often. ``ViewGraphNode`` subscribes to
    /// `didChange` exactly once, when the node is created, which means the
    /// publisher it subscribed to then has to still be the one being fed now.
    /// So it lives in a class, and ``update(with:previousValue:)`` carries the
    /// class across. Same shape, and for the same reason, as ``ObservedObject``
    /// and ``EnvironmentObject``.
    ///
    /// 本屬性中所有必須比 view 這個 struct 活得久的東西。
    ///
    /// view 的 `body` 每執行一次就會建出一個全新的 `Environment` 值——只要有任何動畫在跑，
    /// 每秒就是好幾次——因此放在 struct 本身裡的東西也就以那個頻率被丟棄。``ViewGraphNode``
    /// 只在節點建立時訂閱 `didChange` 一次，這表示它當時訂閱的那個 publisher 必須就是現在仍在
    /// 被餵資料的那一個。所以它住在一個 class 裡，並由 ``update(with:previousValue:)`` 跨更新
    /// 沿用。與 ``ObservedObject``、``EnvironmentObject`` 同一個形狀，理由也相同。
    private final class Storage {
        /// `nil` until an update fills it in -- and, in object mode, `nil` again
        /// if no ancestor supplies the object any more.
        /// 在某次更新填入之前為 `nil`；在物件模式下，若不再有祖先提供該物件，也會回到 `nil`。
        var value: Value?

        /// The object `upstream` currently forwards from. Kept solely for the
        /// identity check in ``adopt(_:)``.
        /// `upstream` 目前正在轉發的那個物件。保留它純粹是為了 ``adopt(_:)`` 中的 identity 檢查。
        private var observed: (any ObservableObject)?
        private var upstream: Cancellable?
        private var publisher: Publisher?

        /// Built on first access rather than in `init`.
        ///
        /// A ``Publisher`` owns a `DispatchQueue` and a `DispatchSemaphore`, and
        /// `@Environment` is the one wrapper in this directory that is mostly
        /// applied to things which cannot publish anything at all -- a colour
        /// scheme, a font, a locale, an action. Building the publisher eagerly
        /// would allocate a dispatch queue per such property per body
        /// evaluation, a cost paid by every view in the tree so that the few
        /// holding an object can be observed. Nothing asks for this except the
        /// ``ObservableProperty`` conformance below, and that conformance only
        /// exists where `Value: ObservableObject`.
        ///
        /// 於第一次存取時才建立，而非在 `init` 中。
        ///
        /// 一個 ``Publisher`` 持有一個 `DispatchQueue` 與一個 `DispatchSemaphore`，而
        /// `@Environment` 是本目錄中唯一大多套用在「根本無法發佈任何變更」之物上的包裝器——配色
        /// 方案、字型、地區設定、動作。若急切地建立該 publisher，等於每個這類屬性、每次 body
        /// 求值都配置一個 dispatch queue，而這筆代價由樹中每一個 view 支付，只為了讓少數持有
        /// 物件者能被觀察。除了下方的 ``ObservableProperty`` conformance 之外沒有人會索取它，
        /// 而該 conformance 只存在於 `Value: ObservableObject` 的情況。
        var didChange: Publisher {
            if let publisher {
                return publisher
            }
            let publisher = Publisher().tag(with: "Environment<\(Value.self)>")
            self.publisher = publisher
            // An object may already have been adopted by the time anyone asks
            // for the publisher: ``ViewGraphNode`` runs a full dynamic property
            // update pass before it walks the fields looking for something to
            // subscribe to. Linking here is what stops that ordering from
            // costing the first change.
            // 在有人索取 publisher 之前，物件可能早已被採用：``ViewGraphNode`` 會先跑完一整輪
            // dynamic property 更新，之後才走訪各欄位尋找可訂閱的對象。此處補上連結，正是為了
            // 不讓那個順序吃掉第一次變更。
            if let observed {
                upstream = publisher.link(toUpstream: observed.didChange)
            }
            return publisher
        }

        /// Stores `newValue` and, when it is an object, re-points the publisher
        /// chain at it.
        ///
        /// The identity check is what makes this safe to call on every update.
        /// Without it, `link` would run once per pass: ``ObservableObject``'s
        /// default `didChange` builds a FRESH publisher on every access, so the
        /// old chain is never the same object as the new one and cancelling
        /// could never be skipped. Two live chains deliver every change twice,
        /// which costs a second view update and reports nothing anywhere. The
        /// same hazard is written up on ``StateObject`` and ``EnvironmentObject``.
        ///
        /// 存下 `newValue`；若它是一個物件，則把 publisher 鏈重新指向它。
        ///
        /// 那個 identity 檢查正是此函式能在每次更新時被呼叫的原因。少了它，`link` 會每一輪執行
        /// 一次：``ObservableObject`` 的預設 `didChange` **每次存取都會產生一個全新的
        /// publisher**，因此舊鏈與新鏈永遠不是同一個物件，取消也就永遠無法省略。兩條同時存活的
        /// 鏈會讓每個變更抵達兩次，代價是多一次 view 更新，而且任何地方都不會回報。同樣的陷阱
        /// 已記錄於 ``StateObject`` 與 ``EnvironmentObject``。
        func adopt(_ newValue: Value?) {
            // Assigned before the guard, not after. A key path value is replaced
            // on every single update and is usually not an object at all, so an
            // early return taken on the object identity check must not be
            // allowed to skip the assignment -- that would freeze every
            // `@Environment(\.someKeyPath)` in the tree at its first value.
            // 在 guard 之前指派，而非之後。key path 的值每一次更新都會被換掉，而它通常根本不是
            // 物件，因此「因物件 identity 檢查而提前返回」絕不能跳過這次指派——否則樹中每一個
            // `@Environment(\.someKeyPath)` 都會被凍結在它的第一個值上。
            value = newValue

            let object = newValue as? any ObservableObject
            guard object !== observed else { return }
            observed = object
            upstream?.cancel()
            upstream = nil
            if let object, let publisher {
                upstream = publisher.link(toUpstream: object.didChange)
            }
        }
    }

    /// The underlying value, and the observation that goes with it.
    ///
    /// The value is `nil` if ``update(with:previousValue:)`` has not yet been
    /// called, or -- in object mode -- if nothing in the environment supplied
    /// one.
    private let box: Box<Storage>

    public func update(
        with environment: EnvironmentValues,
        previousValue: Self?
    ) {
        // Carried over so that `didChange` keeps its identity across the view
        // struct being rebuilt, which the view graph requires: ``ViewGraphNode``
        // subscribes to it once, at node creation, and a fresh publisher on the
        // next pass would simply never be heard from again.
        // 沿用先前的儲存體，好讓 `didChange` 在 view struct 被重建時仍保持同一個身分，而那是
        // view graph 的要求：``ViewGraphNode`` 只在建立節點時訂閱它一次，下一輪若換成一個全新的
        // publisher，就再也不會有人聽見它。
        if let previousValue {
            box.value = previousValue.box.value
        }

        switch mode {
            case .keyPath(let keyPath):
                box.value.adopt(environment[keyPath: keyPath])
            case .observableObject:
                // `as?`, never `as!`. This line read
                // `(environment[observable: type] as! Value)` until 2026-09-08,
                // and with nothing in the environment that is a force-cast of
                // `nil`: the process died here, before ``wrappedValue`` was ever
                // reached, naming neither the type nor the modifier that was
                // forgotten. Absence is recorded instead and reported by
                // ``wrappedValue``, which is the only place that knows a value
                // was actually required.
                //
                // 用 `as?`，絕不用 `as!`。此行在 2026-09-08 之前是
                // `(environment[observable: type] as! Value)`，而當 environment 中什麼都沒有時，
                // 那就是一次對 `nil` 的強制轉型：行程在此處死去，``wrappedValue`` 根本不會被觸及，
                // 既沒指出型別，也沒指出被遺忘的那個 modifier。此處改為記下「不存在」，交由
                // ``wrappedValue`` 回報，因為只有它知道「這次真的需要一個值」。
                if let type = Value.self as? any ObservableObject.Type {
                    box.value.adopt(environment[observable: type] as? Value)
                }
        }
    }

    /// The environment value that this property refers to.
    public var wrappedValue: Value {
        guard let value = box.value.value else {
            let message = mode.missingValueMessage
            // Logged as well as trapped, for the reason spelled out on
            // ``EnvironmentObject``: `fatalError`'s message goes to stderr, and
            // on Android nobody reads stderr -- logcat is where the sentence has
            // to arrive.
            // 既記錄也中止，理由已寫在 ``EnvironmentObject`` 上：`fatalError` 的訊息走 stderr，
            // 而在 Android 上沒有人會去讀 stderr——那句話必須抵達 logcat。
            logger.critical("\(message)")
            fatalError(message)
        }
        return value
    }

    /// Initializes an ``Environment`` property wrapper.
    ///
    /// - Parameter keyPath: A key path to the enviornment value to access.
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.box = Box(Storage())
        self.mode = .keyPath(keyPath)
    }

    public init(_ type: Value.Type) where Value: ObservableObject {
        self.box = Box(Storage())
        self.mode = .observableObject
    }

    private enum Mode {
        /// A key path to the enviornment value to access.
        case keyPath(KeyPath<EnvironmentValues, Value>)
        /// An observable object.
        case observableObject

        var pathDescription: String {
            switch self {
                case .keyPath(let keyPath):
                    "\(keyPath)"
                case .observableObject:
                    "\(Value.self).self"
            }
        }

        /// What to say when ``wrappedValue`` is read and there is nothing there.
        ///
        /// Two sentences, because they are two different mistakes with two
        /// different fixes. A key path always resolves -- an ``EnvironmentKey``
        /// has a default value -- so an empty one can only mean the property was
        /// read before the view graph filled it in, and the fix is to stop doing
        /// that. An object can be genuinely absent for the whole life of the
        /// program, and the fix is a call the author never wrote, so the message
        /// names the type and the call.
        ///
        /// 兩句話，因為那是兩種不同的錯誤，對應兩種不同的修法。key path 一定解析得出東西——
        /// 一個 ``EnvironmentKey`` 必有預設值——所以它為空只可能代表「該屬性在 view graph
        /// 填入之前就被讀取」，修法是別再那樣做。而一個物件則可能在整個程式生命中真的不存在，
        /// 其修法是一次作者從未寫下的呼叫，因此訊息會指名該型別與該次呼叫。
        var missingValueMessage: String {
            switch self {
                case .keyPath:
                    """
                    Environment value at \(pathDescription) used before initialization. Don't \
                    use @Environment properties before SwiftCrossUI requests the \
                    view's body.
                    """
                case .observableObject:
                    """
                    no \(Value.self) in the environment. A view declared \
                    '@Environment(\(Value.self).self) var …' and read it, but no ancestor view \
                    or scene ever called '.environmentObject(_:)' with a \(Value.self). Add \
                    '.environmentObject(<your \(Value.self)>)' to an ancestor -- commonly the \
                    WindowGroup in your App's body -- and make sure the object is owned by \
                    something that outlives the view, e.g. an @State or @StateObject property.
                    """
            }
        }
    }
}

/// `@Environment(SomeObject.self)` observes the object it reads, exactly as
/// ``EnvironmentObject`` does.
///
/// Conditional rather than unconditional, and the condition is load-bearing in
/// both directions. ``ViewGraphNode`` and ``_App`` find observable properties
/// with a runtime `as? any ObservableProperty` cast, which honours a conditional
/// conformance -- so `@Environment(\.colorScheme)` does not match, is not
/// subscribed to, and never has to build the publisher whose cost is described
/// on `Storage.didChange`. A `Value` that *is* an ``ObservableObject`` matches
/// whichever way it was written, key path or type, which is the right answer for
/// both: an object read out of the environment is an object whose changes the
/// reader wants.
///
/// `@Environment(SomeObject.self)` 會觀察它所讀取的物件，與 ``EnvironmentObject`` 完全一致。
///
/// 這裡採用條件式而非無條件的 conformance，而那個條件在兩個方向上都承重。``ViewGraphNode``
/// 與 ``_App`` 是以執行期的 `as? any ObservableProperty` 轉型來尋找 observable 屬性的，而該轉型
/// 會遵守條件式 conformance——因此 `@Environment(\.colorScheme)` 不會命中、不會被訂閱，也就
/// 永遠不必建立那個成本記載於 `Storage.didChange` 的 publisher。而一個**確實**是
/// ``ObservableObject`` 的 `Value`，無論寫成 key path 或型別都會命中，且這對兩者都是正確答案：
/// 會從 environment 中讀出一個物件的人，要的就是那個物件的變更。
extension Environment: ObservableProperty where Value: ObservableObject {
    public var didChange: Publisher { box.value.didChange }
}
