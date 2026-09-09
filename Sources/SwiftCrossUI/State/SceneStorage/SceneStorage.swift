import Foundation
import Mutex

private let sceneStoragePublisherCache: Mutex<[String: Publisher]> = Mutex([:])

/// Like ``AppStorage``, but scoped to one window rather than to the app.
///
/// Two windows of the same ``WindowGroup`` each keep their own value: a draft in
/// one window and a different draft in the other, both surviving a relaunch.
/// ``AppStorage`` would give them a single shared value, so the second window to
/// write would silently overwrite the first.
///
/// ```swift
/// struct Editor: View {
///     @SceneStorage("draft") var draft = ""       // per window
///     @AppStorage("fontSize") var fontSize = 14.0 // one value for the app
/// }
/// ```
///
/// **It is UI state, not data.** A scene's storage is keyed by the window id,
/// and a window that is closed and never reopened leaves its entry behind; the
/// selected tab, a scroll offset or an unsent draft belong here, a document does
/// not.
///
/// WHERE IT IS STORED. The same ``AppStorageProvider`` ``AppStorage`` uses,
/// under a key prefixed with the scene id: `scene.<id>.<key>`. That is
/// deliberate rather than a shortcut -- it means this feature adds **no new
/// backend requirement and no second persistence path**, so it works on all five
/// backends the day it lands, and a provider that already persists correctly
/// keeps doing so.
///
/// MEASURED, not assumed (2026-09-09, P59 on AppKit). After typing three times
/// in window A and then opening window B, the app's `UserDefaults` domain held
/// exactly three keys:
///
///     draft                                         "AAA"   app-wide
///     scene.TupleView1<HotReloadableView>-0.draft   "AAA"   window A
///     (no scene.p59-second.draft at all)                    window B never wrote
///
/// and window B rendered `scene draft: (empty)` beside `app draft: AAA`. The
/// absent third key is the part that matters: scoping is not "a different value
/// under the same key", it is a different key.
///
/// 以量測而非假設(2026-09-09,P59 於 AppKit)。在視窗 A 打三次字、接著開啟視窗 B 之後,該 app 的
/// `UserDefaults` domain 中恰好有三個鍵(見上方英文),而視窗 B 畫出的是
/// `scene draft: (empty)` 與 `app draft: AAA` 並列。真正關鍵的是那個**不存在**的第三個鍵:
/// 有範圍不是「同一個鍵底下的不同值」,而是不同的鍵。
///
/// WHAT HAPPENS OUTSIDE A WINDOW. ``EnvironmentValues/sceneID`` is `nil` there,
/// and this wrapper then behaves as plain in-memory state: the value works for
/// the lifetime of the view and is never written. Inventing a scope instead --
/// falling back to an app-wide key, say -- would make two windows share a value
/// that the type promises to keep separate, which is exactly the bug this
/// wrapper exists to prevent, arriving silently.
///
/// 與 ``AppStorage`` 類似,但其範圍是**一個視窗**,而不是整個 app。
///
/// 同一個 ``WindowGroup`` 的兩個視窗各自保有自己的值:一個視窗裡的草稿,與另一個視窗裡的另一份草稿,
/// 而且都能存活過重新啟動。``AppStorage`` 會給它們單一一個共用的值,於是後寫入的那個視窗會靜默地
/// 覆蓋掉前一個。
///
/// **它是 UI 狀態,不是資料。** 一個 scene 的儲存以視窗 id 為索引鍵,而一個被關閉且再也沒有重開的
/// 視窗會留下它的項目;選在哪個分頁、捲動位置、還沒送出的草稿屬於這裡,一份文件不屬於。
///
/// 存在哪裡。與 ``AppStorage`` 相同的 ``AppStorageProvider``,索引鍵前綴為 scene id:
/// `scene.<id>.<key>`。這是刻意的、而非便宜行事——它意味著這項功能**不新增任何 backend requirement,
/// 也不新增第二條持久化路徑**,因此它落地當天就在五個 backend 上都成立,而一個原本就能正確持久化的
/// provider 會繼續正確。
///
/// 在視窗之外會怎樣。``EnvironmentValues/sceneID`` 在那裡是 `nil`,而本 wrapper 此時的行為就是單純的
/// 記憶體狀態:該值在這個 view 的生命週期內可用,而且永遠不會被寫出。反過來自行捏造一個範圍——例如
/// 退回使用一個 app 層級的索引鍵——會讓兩個視窗共用一個「這個型別承諾要分開」的值,而那正是本 wrapper
/// 存在所要防止的缺陷,只是它會靜悄悄地發生。
@propertyWrapper
public struct SceneStorage<Value: Codable & Sendable>: ObservableProperty {
    private final class Storage: StateStorageProtocol {
        let key: String
        let defaultValue: Value
        var downstreamObservation: Cancellable?
        var provider: (any AppStorageProvider)?
        var sceneID: String?

        /// The value while there is nowhere to persist it.
        ///
        /// Held rather than recomputed, so a `@SceneStorage` used outside a
        /// window still behaves like ``State`` instead of resetting to its
        /// default on every read.
        /// 在「無處可存」時所持有的值。
        ///
        /// 選擇持有而非每次重算，好讓一個用在視窗之外的 `@SceneStorage` 仍然表現得像 ``State``，
        /// 而不是每次讀取都退回預設值。
        var inMemoryValue: Value

        init(key: String, defaultValue: Value, provider: (any AppStorageProvider)?) {
            self.key = key
            self.defaultValue = defaultValue
            self.provider = provider
            self.inMemoryValue = defaultValue
        }

        /// `scene.<id>.<key>`, or `nil` when there is no scene.
        ///
        /// The prefix is what keeps two windows apart, and it is also what keeps
        /// a scene's keys out of ``AppStorage``'s namespace: an app storing
        /// `"draft"` app-wide and a scene storing `"draft"` per window do not
        /// collide, because only one of them is prefixed.
        /// `scene.<id>.<key>`，在沒有 scene 時為 `nil`。
        ///
        /// 那個前綴既是「讓兩個視窗分得開」的東西，也是「讓 scene 的索引鍵不闖進 ``AppStorage``
        /// 命名空間」的東西：一個在 app 層級存 `"draft"`、一個在視窗層級存 `"draft"`，兩者不會相撞，
        /// 因為只有其中一個帶前綴。
        var scopedKey: String? {
            guard let sceneID else { return nil }
            return "scene.\(sceneID).\(key)"
        }

        lazy var didChange: Publisher = {
            sceneStoragePublisherCache.withLock { cache in
                let cacheKey = scopedKey ?? "scene.<unscoped>.\(key)"
                guard let publisher = cache[cacheKey] else {
                    let newPublisher = Publisher()
                    cache[cacheKey] = newPublisher
                    return newPublisher
                }
                return publisher
            }
        }()

        var value: Value {
            get {
                guard let provider, let scopedKey else { return inMemoryValue }
                return provider.getValue(key: scopedKey, defaultValue: defaultValue)
            }
            set {
                // No `fatalError` when there is nowhere to write, unlike
                // ``AppStorage``. A scene id arrives with the environment, and a
                // view's properties are read before the first environment update
                // in some paths -- aborting there would kill an app for using a
                // wrapper correctly.
                // 在無處可寫時不呼叫 `fatalError`，這一點與 ``AppStorage`` 不同。scene id 是隨著
                // environment 抵達的，而在某些路徑上，一個 view 的屬性會在第一次 environment 更新
                // 之前就被讀取——在那裡中止行程，等於因為「正確地使用了一個 wrapper」而殺掉整個 app。
                inMemoryValue = newValue
                guard let provider, let scopedKey else { return }
                provider.setValue(key: scopedKey, newValue: newValue)
            }
        }
    }

    private let implementation: StateImpl<Storage>
    private var storage: Storage { implementation.storage }

    public var didChange: Publisher { storage.didChange }

    public var wrappedValue: Value {
        get { implementation.wrappedValue }
        nonmutating set { implementation.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> { implementation.projectedValue }

    public init(wrappedValue defaultValue: Value, _ key: String) {
        implementation = StateImpl(
            initialStorage: Storage(key: key, defaultValue: defaultValue, provider: nil)
        )
    }

    public init(_ key: String) where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil, key)
    }

    public func update(with environment: EnvironmentValues, previousValue: SceneStorage<Value>?) {
        implementation.update(with: environment, previousValue: previousValue?.implementation)

        // Both come from the environment on every update, and the scene id is
        // the one that can legitimately change: a window closed and reopened is
        // a new `WindowReference` with the same id, but a view moved between
        // windows is the same view with a different one.
        // 兩者都在每一次更新時取自 environment，而其中 scene id 是那個「可以合理改變」的:一個被關掉
        // 又重開的視窗，是一個帶著相同 id 的新 `WindowReference`；而一個在視窗之間移動的 view，
        // 則是同一個 view 帶著不同的 id。
        if storage.provider == nil {
            storage.provider = environment.appStorageProvider
        }
        storage.sceneID = environment.sceneID
    }
}
