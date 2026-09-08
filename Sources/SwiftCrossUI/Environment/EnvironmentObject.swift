/// A property wrapper that reads an ``ObservableObject`` placed in the
/// environment by an ancestor, and redraws the view when that object publishes.
///
/// The object is looked up by its **type**, not by a key path. That is the
/// whole difference from ``Environment``, and it is what lets a view read a
/// model no intermediate view has to know about:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     @State var session = Session()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()          // knows nothing about Session
///         }
///         .environmentObject(session)
///     }
/// }
///
/// struct DeepChild: View {           // any depth below, no plumbing between
///     @EnvironmentObject var session: Session
///
///     var body: some View {
///         Text(session.username)
///     }
/// }
/// ```
///
/// ## Why this exists when ``Environment`` already accepts a type
///
/// `@Environment(Session.self)` reads the very same slot -- both go through
/// `EnvironmentValues`'s `[observable:]` subscript -- and since 2026-09-08 it
/// also observes, so the two are equivalent. Keep this one because
/// `@EnvironmentObject var session: Session` is still valid SwiftUI and is
/// still what a lot of code says; pick either in new code.
///
/// **The paragraph that stood here until 2026-09-08 is kept, wrong, because
/// what it described was real and is the thing to recognise if it comes back:**
/// *"``Environment`` is only a ``DynamicProperty``: it has no `didChange`, so
/// ``ViewGraphNode`` never subscribes to it, and the view does not redraw when
/// the object publishes."* That was accurate at the time. It was closed by
/// giving ``Environment`` a conditional ``ObservableProperty`` conformance
/// rather than by documenting the difference, because "use the other wrapper"
/// is not a fix for a wrapper that compiles, renders correctly once, and then
/// silently stops.
///
/// ## When nothing supplied the object
///
/// Reading the property logs the type and the fix, and then traps. That is what
/// SwiftUI does, and it is deliberately *not* the answer this repository's
/// `CLAUDE.md` requires for a missing backend feature. The two cases differ in
/// three ways, and all three point the same direction:
///
/// - **Whose defect it is.** A backend gap is the framework's: the application
///   wrote correct, portable code and cannot close the hole from its side. This
///   one is the application's -- a single `.environmentObject(_:)` missing from
///   an ancestor -- and the message names both the type and the call to add.
/// - **Whether it can reach a user.** A backend gap fails on one backend and
///   passes on another, so it survives review on macOS and then kills the app
///   on Android. This fails identically on all five backends, on the first
///   render, for everyone; it cannot get past the developer who wrote it.
/// - **Whether there is anything to show instead.** `VisualEffects` had one:
///   the unmodified view. Here `Value` is an arbitrary user class with no
///   default to invent. The alternatives are to hand back an object that does
///   not exist, or to make `wrappedValue` a `Value?` -- which is not SwiftUI's
///   shape and merely relocates the same trap into user code as a `!`.
///
/// The neighbours had already settled it: ``Environment/wrappedValue`` traps
/// when read before the graph has filled it in, and `EnvironmentValues`'s
/// `[observable:]` subscript traps on a type mismatch. A different answer here
/// would make one class of mistake behave two different ways.
///
/// The `logger.critical` ahead of the trap is not decoration. `fatalError`'s
/// message goes to stderr, and on Android stderr is not where anybody looks --
/// logcat is. The sentence naming the type has to travel through the logger to
/// arrive.
///
/// The trap is on **read**, not on update: a view that declares the property
/// but never reaches it on this pass keeps running. That is more forgiving than
/// SwiftUI and costs nothing.
///
/// 一個屬性包裝器，讀取由祖先放入 environment 的 ``ObservableObject``，並在該物件發佈變更時重繪
/// 該 view。
///
/// 該物件是以**型別**查找，而非以 key path。這正是它與 ``Environment`` 的根本差別，也使得一個
/// view 能讀到中間任何一層都不必知道的 model。
///
/// ## 既然 ``Environment`` 已經可以接受型別，為何還需要這個
///
/// `@Environment(Session.self)` 讀的是完全相同的位置——兩者都經過 `EnvironmentValues` 的
/// `[observable:]` subscript——而自 2026-09-08 起它也會觀察，因此兩者等價。保留這一個，是因為
/// `@EnvironmentObject var session: Session` 在 SwiftUI 中依然合法，也依然是大量既有程式碼的
/// 寫法；新程式碼兩者任選其一即可。
///
/// **以下這段文字在 2026-09-08 之前立於此處，如今是錯的，但仍予保留，因為它所描述的情況確實
/// 存在過，而且一旦重演就要認得出來：**
/// *「``Environment`` 僅是 ``DynamicProperty``：它沒有 `didChange`，因此 ``ViewGraphNode``
/// 從不訂閱它，物件發佈變更時 view 也不會重繪。」* 這在當時是準確的。它最後是以「給
/// ``Environment`` 一個條件式的 ``ObservableProperty`` conformance」來關閉，而不是以「把差異寫進
/// 文件」來關閉——因為對於一個「編得過、正確繪出一次、然後靜默停止」的包裝器而言，「請改用另一個
/// 包裝器」並不是修正。
///
/// ## 當沒有任何人提供該物件時
///
/// 讀取該屬性會先記錄型別與修正方式，然後中止。這與 SwiftUI 的做法相同，而且是刻意**不**採用本專案
/// `CLAUDE.md` 對「缺失的 backend 功能」所要求的答案。這兩種情況有三點差異，而三點都指向同一個方向：
///
/// - **這是誰的缺陷。** backend 的缺口是框架的：應用程式寫的是正確且可攜的程式碼，卻無法從自己這端
///   把洞補起來。這一個則是應用程式的——祖先少了一次 `.environmentObject(_:)`——而訊息會同時指出
///   型別與應該補上的呼叫。
/// - **它能不能流到使用者手上。** backend 的缺口會在某個 backend 失敗、在另一個通過，於是它通過了
///   macOS 上的審查，然後在 Android 上讓 app 死掉。這一個在五個 backend 上以完全相同的方式、於
///   第一次繪製時、對所有人失敗；它過不了寫出它的那位開發者這一關。
/// - **有沒有別的東西可以顯示。** `VisualEffects` 有：未經修飾的 view。此處 `Value` 是使用者自訂的
///   任意類別，沒有可以憑空生出的預設值。其餘選項是交回一個並不存在的物件，或把 `wrappedValue`
///   改成 `Value?`——那不是 SwiftUI 的形狀，也只是把同一個中止以 `!` 的形式搬進使用者的程式碼裡。
///
/// 鄰居們早已定調：``Environment/wrappedValue`` 在 graph 尚未填入前被讀取時就會中止，而
/// `EnvironmentValues` 的 `[observable:]` subscript 在型別不符時也會中止。此處若給出不同答案，
/// 會讓同一類錯誤出現兩種行為。
///
/// 中止前的那行 `logger.critical` 不是裝飾。`fatalError` 的訊息走的是 stderr，而在 Android 上
/// 沒有人會去看 stderr——大家看的是 logcat。那句指名型別的話必須經由 logger 才能送達。
///
/// 中止發生在**讀取**時，而非更新時：一個宣告了此屬性、但這一輪並未真的讀到它的 view 仍可繼續執行。
/// 這比 SwiftUI 更寬鬆，而且不花任何代價。
@propertyWrapper
public struct EnvironmentObject<Value: ObservableObject>: ObservableProperty {
    private final class Storage {
        /// `nil` until `update(with:previousValue:)` finds an object of this
        /// type in the environment, and again if an ancestor stops supplying it.
        /// 在 `update(with:previousValue:)` 於 environment 中找到此型別的物件之前為 `nil`；
        /// 若某個祖先不再提供它，也會回到 `nil`。
        var value: Value?

        /// Must outlive every view update, because ``ViewGraphNode`` subscribes
        /// to it exactly once, when the node is created -- and, in this
        /// wrapper's case, at a moment when `value` may still be `nil`. The
        /// publisher therefore cannot be the object's own; it has to be ours,
        /// with the object's linked in behind it once one turns up.
        /// 必須比每一次 view 更新都活得久，因為 ``ViewGraphNode`` 只在節點建立時訂閱它一次——而在
        /// 本包裝器的情況下，那一刻 `value` 可能仍是 `nil`。因此這個 publisher 不能是物件自己的，
        /// 它必須是我們自己的，等物件出現後再把物件的接到它後面。
        let didChange = Publisher()
        private var upstream: Cancellable?

        /// Points the publisher chain at `object`, and does nothing at all if
        /// that is already where it points.
        ///
        /// The identity check is what makes this safe to call on every update.
        /// Without it, `link` would run once per pass: `ObservableObject`'s
        /// default `didChange` builds a FRESH publisher on every access, so the
        /// old chain is never the same object as the new one and cancelling
        /// cannot be skipped. Two live chains deliver every change twice, which
        /// costs a second view update and reports nothing anywhere. The same
        /// hazard is written up in ``StateObject``.
        ///
        /// 把 publisher 鏈指向 `object`；若它本來就指在那裡，則什麼也不做。
        ///
        /// 那個 identity 檢查正是此函式能在每次更新時被呼叫的原因。少了它，`link` 會每一輪執行一次：
        /// `ObservableObject` 的預設 `didChange` **每次存取都會產生一個全新的 publisher**，因此
        /// 舊鏈與新鏈永遠不會是同一個物件，取消也就無法省略。兩條同時存活的鏈會讓每個變更抵達兩次，
        /// 代價是多一次 view 更新，而且任何地方都不會回報。同樣的陷阱已記錄於 ``StateObject``。
        func adopt(_ object: Value?) {
            guard object !== value else { return }
            value = object
            upstream?.cancel()
            upstream = object.map { didChange.link(toUpstream: $0.didChange) }
        }
    }

    private let box: Box<Storage>

    public var didChange: Publisher { box.value.didChange }

    public var wrappedValue: Value {
        guard let value = box.value.value else {
            let message = """
                no \(Value.self) in the environment. A view declared \
                '@EnvironmentObject var … : \(Value.self)' and read it, but no ancestor \
                view or scene ever called '.environmentObject(_:)' with a \(Value.self). \
                Add '.environmentObject(<your \(Value.self)>)' to an ancestor -- commonly \
                the WindowGroup in your App's body -- and make sure the object is owned \
                by something that outlives the view, e.g. an @State or @StateObject property.
                """
            logger.critical("\(message)")
            fatalError(message)
        }
        return value
    }

    /// A binding to the object, so that `$model.someProperty` works the way it
    /// does on ``ObservedObject``.
    ///
    /// The setter deserves a note. `$model.someProperty = x` does not only run
    /// the key path write; ``Binding/subscript(dynamicMember:)`` reads
    /// `wrappedValue`, mutates through it, then writes `wrappedValue` back --
    /// so this setter is called with the *same* object it already holds, which
    /// is a no-op and correct, because the mutation already landed through the
    /// class reference.
    ///
    /// Nothing is published from here. The object's own `didChange` is already
    /// linked into ours, so a `@Published` property that was just written has
    /// published already; sending again would deliver every `$model.x` write
    /// twice -- the double-update hazard described on `Storage.adopt(_:)` above.
    ///
    /// Assigning a *different* object through `$model` is not supported: the
    /// environment is the source of truth and the next update would silently
    /// put the old object back. Rather than let that happen quietly, the
    /// attempt is refused and logged.
    ///
    /// 一個指向該物件的 binding，讓 `$model.someProperty` 的行為與 ``ObservedObject`` 上一致。
    ///
    /// setter 值得一提。`$model.someProperty = x` 不只執行 key path 寫入；
    /// ``Binding/subscript(dynamicMember:)`` 會先讀 `wrappedValue`、透過它進行修改，再把
    /// `wrappedValue` 寫回——因此這個 setter 收到的是它本來就持有的**同一個**物件，於是它是個
    /// no-op，而這是正確的，因為那次修改早已經由類別參考生效。
    ///
    /// 此處不發佈任何東西。物件自己的 `didChange` 已經接到我們的後面，因此剛被寫入的 `@Published`
    /// 屬性早已發佈過；再送一次會讓每一次 `$model.x` 寫入都抵達兩次——即上方 `Storage.adopt(_:)`
    /// 所描述的重複更新陷阱。
    ///
    /// 透過 `$model` 指派一個**不同的**物件並不受支援：environment 才是真實來源，下一次更新會
    /// 靜默地把舊物件放回去。與其讓那件事無聲發生，這裡選擇拒絕並記錄該次嘗試。
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                guard newValue !== self.box.value.value else { return }
                logger.critical(
                    """
                    ignoring an attempt to replace the @EnvironmentObject of type \
                    \(Value.self) through its binding. The environment owns this object; \
                    the replacement would be reverted by the next view update. Change the \
                    object passed to '.environmentObject(_:)' by the ancestor instead.
                    """
                )
            }
        )
    }

    public init() {
        box = Box(Storage())
    }

    public func update(
        with environment: EnvironmentValues,
        previousValue: EnvironmentObject<Value>?
    ) {
        // The storage is carried over so that `didChange` keeps its identity,
        // which the view graph requires: `ViewGraphNode` subscribes to it once,
        // at node creation. Unlike ``ObservedObject`` there is no value to
        // preserve alongside it -- this wrapper has no initialiser that could
        // have carried one in, and the environment is the only source there is.
        //
        // 儲存體被沿用，是為了讓 `didChange` 保持同一個身分，而那是 view graph 的要求：
        // `ViewGraphNode` 只在建立節點時訂閱它一次。與 ``ObservedObject`` 不同，這裡沒有需要
        // 一併保留的值——本包裝器沒有任何可以帶值進來的初始化式，environment 是唯一的來源。
        if let previousValue {
            box.value = previousValue.box.value
        }

        // Deliberately not a trap when the lookup comes back empty. Not every
        // update reaches the property, and an ancestor that has not supplied the
        // object *yet* is a legitimate intermediate state; the trap belongs on
        // the read, where a value is actually required. See the type's
        // documentation for why a read traps at all.
        //
        // 查找結果為空時刻意不中止。並非每一次更新都會用到該屬性，而某個祖先「尚未」提供該物件
        // 是合法的中間狀態；中止屬於讀取那一端，因為那裡才真的需要一個值。至於讀取為何會中止，
        // 見本型別的文件。
        box.value.adopt(environment[observable: Value.self])
    }
}
