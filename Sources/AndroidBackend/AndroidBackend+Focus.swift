import AndroidKit
import SwiftCrossUI

@JavaClass(
    "dev.swiftcrossui.androidbackend.SwiftFocusChangeListener",
    implements: AndroidKit.ViewTreeObserver.OnGlobalFocusChangeListener.self
)
class SwiftFocusChangeListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(_ id: Int32, environment: JNIEnvironment? = nil)
}

@JavaImplementation("dev.swiftcrossui.androidbackend.SwiftFocusChangeListener")
extension SwiftFocusChangeListener {
    @JavaMethod
    func swiftFocusChanged(_ id: Int32) {
        FocusHandlers.recheck(id: id)
    }
}

/// The Swift side of the focus listener's id.
///
/// A JNI native method carries no captured state, so the handler cannot travel
/// with the listener object; it lives here and the listener carries a key. Same
/// arrangement as `LazyListProviders`.
///
/// `nonisolated(unsafe)` for the reason that one gives: every access is on the
/// Android main thread -- registration from a layout pass, reporting from a view
/// callback -- and the type is not reachable from anywhere else.
///
/// 那個 focus listener 的 id 在 Swift 這一側的部分。
///
/// 一個 JNI native method 不帶任何被捕捉的狀態,因此 handler 無法隨著那個 listener 物件一起移動;
/// 它住在這裡,而 listener 帶著一把鍵。與 `LazyListProviders` 是同一種安排。
///
/// `nonisolated(unsafe)` 的理由與那邊給的相同:每一次存取都在 Android 主執行緒上——註冊來自一次
/// 版面計算,回報來自一次 view 回呼——而這個型別在別處無從觸及。
enum FocusHandlers {
    /// One watched widget: what to call, and what it last answered.
    ///
    /// `lastValue` is kept because the global listener fires for EVERY focus
    /// move in the window, most of which are about some other widget. Without
    /// it, every watched view would report on every move, and `@FocusState`
    /// would write itself the same value repeatedly -- a view-graph update per
    /// keystroke-sized event.
    /// 一個被觀察的 widget:要呼叫什麼,以及它上一次的答案是什麼。
    ///
    /// 保留 `lastValue`,是因為那個全域 listener 會為視窗內**每一次**焦點移動觸發,而其中大多數與
    /// 別的 widget 有關。少了它,每一個被觀察的 view 都會在每一次移動時回報,而 `@FocusState` 會反覆
    /// 把同一個值寫給自己——每一個按鍵大小的事件就是一次 view graph 更新。
    final class Watch {
        let widget: AndroidKit.View
        var handler: (Bool) -> Void
        var lastValue: Bool

        init(widget: AndroidKit.View, handler: @escaping (Bool) -> Void) {
            self.widget = widget
            self.handler = handler
            self.lastValue = widget.hasFocus()
        }
    }

    nonisolated(unsafe) private static var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private static var nextID: Int32 = 1

    /// Registers a widget, reusing its id where one was already issued.
    ///
    /// Reuse matters because this is called from `computeLayout` -- every frame.
    /// A fresh id per frame would leave the table growing without bound, and a
    /// fresh `Watch` would take `lastValue` from the CURRENT state, which is the
    /// silent swallow the AppKit file records: the frame beats the callback and
    /// the change is compared against itself.
    /// 註冊一個 widget;若先前已發過 id 則沿用。
    ///
    /// 沿用很重要,因為這是從 `computeLayout` 呼叫的——每一幀都會。每幀發一個新 id 會讓那張表無上限
    /// 地成長;而一個全新的 `Watch` 會把 `lastValue` 取自**當下**的狀態,那正是 AppKit 那個檔案所
    /// 記載的那種無聲吞噬:那一幀跑贏了回呼,於是那次改變是拿自己跟自己比。
    static func register(
        widget: AndroidKit.View,
        handler: @escaping (Bool) -> Void,
        reusing existing: Int32?
    ) -> Int32 {
        if let existing, let watch = watches[existing] {
            watch.handler = handler
            return existing
        }
        let id = existing ?? nextID
        if existing == nil { nextID += 1 }
        watches[id] = Watch(widget: widget, handler: handler)
        return id
    }

    static func recheck(id: Int32) {
        guard let watch = watches[id] else { return }
        let now = watch.widget.hasFocus()
        guard now != watch.lastValue else { return }
        watch.lastValue = now
        watch.handler(now)
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
        let key = ObjectIdentifier(widget)
        let existing = Self.focusListenerIDs[key]
        let id = FocusHandlers.register(widget: widget, handler: handler, reusing: existing)
        guard existing == nil else { return }
        Self.focusListenerIDs[key] = id
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
        widget.getViewTreeObserver()!.addOnGlobalFocusChangeListener(
            SwiftFocusChangeListener(id, environment: Self.env)
                .as(AndroidKit.ViewTreeObserver.OnGlobalFocusChangeListener.self)
        )
    }

    nonisolated(unsafe) static var focusListenerIDs: [ObjectIdentifier: Int32] = [:]
}
