import AndroidKit
import SwiftCrossUI

@JavaClass(
    "dev.swiftcrossui.androidbackend.SwiftFocusChangeListener",
    implements: AndroidKit.ViewTreeObserver.OnGlobalFocusChangeListener.self
)
class SwiftFocusChangeListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(_ id: Int32, environment: JNIEnvironment? = nil)

    /// Adds the listener to the view, which puts it on its window's observer while attached.
    /// 把 listener 加到 view 上；view 附加期間會把它放到所屬視窗的 observer 上。
    @JavaMethod
    func install(_ view: AndroidKit.View?)
}

@JavaImplementation("dev.swiftcrossui.androidbackend.SwiftFocusChangeListener")
extension SwiftFocusChangeListener {
    /// `false` tells the listener its id is gone, and it takes itself off.
    /// `false` 告訴 listener 它的 id 已不存在，它便把自己拿掉。
    @JavaMethod
    func swiftFocusChanged(_ id: Int32) -> Bool {
        FocusHandlers.recheck(id: id)
    }
}

/// The Swift side of the focus listener's id.
///
/// A JNI native method carries no captured state, so the handler cannot travel
/// with the listener object; it lives here and the listener carries a key.
///
/// `nonisolated(unsafe)` because every access is on the
/// Android main thread -- registration from a layout pass, reporting from a view
/// callback -- and the type is not reachable from anywhere else.
///
/// 那個 focus listener 的 id 在 Swift 這一側的部分。
///
/// 一個 JNI native method 不帶任何被捕捉的狀態,因此 handler 無法隨著那個 listener 物件一起移動;
/// 它住在這裡,而 listener 帶著一把鍵。
///
/// 之所以 `nonisolated(unsafe)`:每一次存取都在 Android 主執行緒上——註冊來自一次
/// 版面計算,回報來自一次 view 回呼——而這個型別在別處無從觸及。
enum FocusHandlers {
    /// One watched widget: what to call, and what it last answered.
    ///
    /// `lastValue` is kept because the global listener fires for EVERY focus
    /// move in the window, most of which are about some other widget. Without
    /// it, every watched view would report on every move, and `@FocusState`
    /// would write itself the same value repeatedly -- a view-graph update per
    /// keystroke-sized event.
    ///
    /// **The view is held through a Java weak reference.** It was held by its
    /// Swift wrapper, which is a JNI global reference: this table lives for the
    /// process, so every view that was ever `.focused` stayed alive, and so did
    /// the listener its window's observer held. See `JavaWeakReference`.
    /// 一個被觀察的 widget:要呼叫什麼，以及它上一次的答案是什麼。
    ///
    /// 保留 `lastValue`,是因為那個全域 listener 會為視窗內**每一次**焦點移動觸發，而其中大多數與
    /// 別的 widget 有關。少了它，每一個被觀察的 view 都會在每一次移動時回報，而 `@FocusState` 會反覆
    /// 把同一個值寫給自己——每一個按鍵大小的事件就是一次 view graph 更新。
    ///
    /// **view 經由 Java 弱參照持有。** 它原本由它的 Swift 包裝持有，那是一個 JNI 全域參照：這張表與行程同壽，
    /// 所以每一個曾經 `.focused` 的 view 都一直活著，它的視窗 observer 所持有的 listener 也是。見 `JavaWeakReference`。
    final class Watch {
        private let view: JavaWeakReference
        var handler: (Bool) -> Void
        var lastValue: Bool

        @MainActor init(widget: AndroidKit.View, handler: @escaping (Bool) -> Void) {
            self.view = JavaWeakReference(widget, environment: AndroidBackend.env)
            self.handler = handler
            self.lastValue = widget.hasFocus()
        }

        /// The view, or `nil` once Java has collected it.
        /// 那個 view;Java 回收它之後為 `nil`。
        var widget: AndroidKit.View? {
            view.get()?.as(AndroidKit.View.self)
        }
    }

    /// The Swift wrapper an id was issued for, held weakly.
    ///
    /// **Weakly, so a freed wrapper's address cannot pass its id on.** The
    /// table was keyed by `ObjectIdentifier` alone, and a new widget at a dead
    /// one's address was handed the dead one's id: its handler replaced the
    /// old one's, but the watch still asked the OLD view, and no listener was
    /// ever installed on the new one.
    /// 某個 id 當初發給的那個 Swift 包裝，以弱參照持有。
    ///
    /// **用弱參照，好讓已釋放之包裝的位址無法把它的 id 傳下去。** 這張表原本只以 `ObjectIdentifier` 為鍵，
    /// 而位於已死 widget 位址上的新 widget 會拿到舊的 id:它的 handler 取代了舊的，但 watch 問的仍是**舊的**
    /// view,而新的 view 上從來沒有裝過 listener。
    final class Registration {
        weak var widget: AndroidKit.View?
        let id: Int32

        init(widget: AndroidKit.View, id: Int32) {
            self.widget = widget
            self.id = id
        }
    }

    nonisolated(unsafe) private static var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private static var registrations: [ObjectIdentifier: Registration] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    /// Registers a widget, or replaces the handler of one already registered.
    ///
    /// Returns the new id when a listener has to be installed, `nil` when the
    /// widget already has one. Reuse matters because this is called on every
    /// frame: a fresh `Watch` would take `lastValue` from the CURRENT state,
    /// which is the silent swallow the AppKit file records -- the frame beats the
    /// callback and the change is compared against itself. Entries whose wrapper
    /// has been freed are dropped when a new widget registers.
    /// 註冊一個 widget,或替換已註冊者的 handler。
    ///
    /// 需要安裝 listener 時回傳新的 id,widget 已有 listener 時回傳 `nil`。沿用很重要，因為這是每一幀都會
    /// 呼叫的：一個全新的 `Watch` 會把 `lastValue` 取自**當下**的狀態，那正是 AppKit 那個檔案所記載的無聲
    /// 吞噬——那一幀跑贏了回呼，於是那次改變是拿自己跟自己比。新的 widget 註冊時，清掉包裝已被釋放的項目。
    @MainActor static func register(
        widget: AndroidKit.View,
        handler: @escaping (Bool) -> Void
    ) -> Int32? {
        let key = ObjectIdentifier(widget)
        if let registration = registrations[key], registration.widget === widget,
            let watch = watches[registration.id]
        {
            watch.handler = handler
            return nil
        }
        for (deadKey, registration) in registrations where registration.widget == nil {
            registrations[deadKey] = nil
            watches[registration.id] = nil
        }
        let id = nextID
        nextID += 1
        registrations[key] = Registration(widget: widget, id: id)
        watches[id] = Watch(widget: widget, handler: handler)
        return id
    }

    /// Reports a change for this id, if there is one.
    ///
    /// `false` when the id is no longer watched -- its widget was dropped, or Java
    /// collected the view -- which tells the listener to take itself off.
    /// 若這個 id 有改變就回報。id 已不再被觀察(widget 被清掉，或 view 已被 Java 回收)時回傳 `false`,
    /// 讓 listener 把自己拿掉。
    static func recheck(id: Int32) -> Bool {
        guard let watch = watches[id] else { return false }
        guard let widget = watch.widget else {
            watches[id] = nil
            return false
        }
        let now = widget.hasFocus()
        guard now != watch.lastValue else { return true }
        watch.lastValue = now
        watch.handler(now)
        return true
    }
}

extension AndroidBackend: BackendFeatures.FocusableViews {
    /// Asks the view for the focus, making it focusable first.
    ///
    /// **`setFocusableInTouchMode(true)` is not a workaround; it is what the
    /// request MEANS on Android.** In touch mode a view is not focusable by
    /// default and `requestFocus()` returns `false` -- that is the platform
    /// behaviour `plan-focus-protocol.md` singled out as having no counterpart
    /// on the other four. An app that writes `focused = true` has said it wants
    /// the keyboard there, which is exactly the statement touch-mode focusability
    /// encodes, so setting it here is honouring the request rather than
    /// sidestepping a refusal.
    ///
    /// The `Bool` still matters after that: a disabled view, a view not attached
    /// to a window, and a view with visibility GONE all still decline.
    ///
    /// 向這個 view 要求焦點,並先讓它成為可取得焦點的。
    ///
    /// **`setFocusableInTouchMode(true)` 不是一個繞道,它就是這個請求在 Android 上的**語意**。**
    /// 在 touch mode 下,一個 view 預設不可取得焦點,`requestFocus()` 會回傳 `false`——那正是
    /// `plan-focus-protocol.md` 特別點名「其餘四個平台沒有對應物」的那個平台行為。一個寫下
    /// `focused = true` 的 app,已經表明它要鍵盤在那裡,而那恰恰就是「touch mode 下可取得焦點」
    /// 所編碼的那句陳述;因此在此設定它,是**履行**那個請求,而不是迴避一次拒絕。
    ///
    /// 在那之後那個 `Bool` 仍然重要:一個被停用的 view、一個未附加到視窗的 view、一個 visibility 為
    /// GONE 的 view,全都仍然會拒絕。
    @discardableResult
    public func focus(_ widget: Widget) -> Bool {
        // `.focusable(false)` is a refusal, not something to switch back on here.
        // `.focusable(false)` 是拒絕，不是要在這裡重新打開的東西。
        if let container = widget.as(FocusableContainer.self), !container.getFocusableNow() {
            return false
        }
        widget.setFocusable(true)
        widget.setFocusableInTouchMode(true)
        return widget.requestFocus()
    }

    public func unfocus(_ widget: Widget) {
        guard widget.hasFocus() else { return }
        widget.clearFocus()
    }

    /// Whether this view or something inside it has the focus.
    ///
    /// `hasFocus()` rather than `isFocused()`: a SwiftCrossUI widget is often a
    /// container and the focus lands on a child, which `isFocused()` -- true
    /// only for the view itself -- would report as unfocused. `hasFocus()`
    /// covers the subtree, which is the question being asked.
    ///
    /// 這個 view、或它裡面的某個東西,是否持有焦點。
    ///
    /// 用 `hasFocus()` 而不是 `isFocused()`:一個 SwiftCrossUI 的 widget 往往是一個容器,而焦點落在
    /// 某個子元件上;`isFocused()`——只在 view 自己持有焦點時為真——會把那回報為「沒有焦點」。
    /// `hasFocus()` 涵蓋整棵子樹,而那才是這裡要問的問題。
    public func isFocused(_ widget: Widget) -> Bool {
        widget.hasFocus()
    }

    public func setFocusChangeHandler(
        ofWidget widget: Widget,
        to handler: @escaping (Bool) -> Void
    ) {
        // `nil` when this widget already has its listener: only the handler was
        // replaced.
        // widget 已有 listener 時為 `nil`:只換了 handler。
        guard let id = FocusHandlers.register(widget: widget, handler: handler) else { return }
        // Installed once, not once per frame: a listener added on every layout
        // pass would allocate a Java object per frame AND leave every previous
        // one attached to the observer, so one focus move would fire the handler
        // as many times as there had been frames.
        //
        // On the view tree observer, not on the view. `setOnFocusChangeListener`
        // reports only the view it is set on -- see the Kotlin file for the
        // measurement that ruled it out.
        //
        // 只安裝一次,不是每幀一次:每一次版面計算都加一個 listener,不只會每幀配置一個 Java 物件,
        // 還會讓先前每一個都繼續掛在那個 observer 上——於是一次焦點移動,會觸發 handler「有過幾幀」
        // 那麼多次。
        //
        // 掛在 view tree observer 上,不是掛在 view 上。`setOnFocusChangeListener` 只回報它被設定的
        // 那個 view——排除它的那次量測見那個 Kotlin 檔案。
        //
        // **Installed on the view, which adds it to its window's observer while
        // attached and takes it off when detached.** It used to go straight onto
        // `getViewTreeObserver()` and stay there for the life of the window,
        // reporting an id whose watch held the view strongly: neither the view
        // nor the listener could ever be freed. See the Kotlin file.
        // **裝在 view 上，由 view 在附加期間把它加進所屬視窗的 observer、分離時拿掉。** 它原本直接掛在
        // `getViewTreeObserver()` 上，與視窗同壽，回報一個「其 watch 強參照著 view」的 id:view 與 listener
        // 都永遠無法被釋放。見那個 Kotlin 檔案。
        SwiftFocusChangeListener(id, environment: Self.env).install(widget)
    }
}
