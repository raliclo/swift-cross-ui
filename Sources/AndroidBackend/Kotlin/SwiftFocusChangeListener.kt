package dev.swiftcrossui.androidbackend

import android.view.View
import android.view.ViewTreeObserver

/**
 * Reports every focus move in the window, back into Swift.
 *
 * **`View.setOnFocusChangeListener` was tried first and reports the wrong thing.** It fires for the
 * view it is set on and for nothing inside it, and a SwiftCrossUI widget is usually a container:
 * the `EditText` takes the focus and the container's listener stays silent. Measured on 2026-09-16
 * with P70 on the emulator -- a tap put a caret in the email field while the app still showed
 * `focused field: none` and `focus changes heard: 0`.
 *
 * `ViewTreeObserver.OnGlobalFocusChangeListener` is the Android counterpart of watching AppKit's
 * window first responder, and for the same reason the AppKit file gives: the event being reported
 * is one the widget is not told about -- the focus LEAVING it. A view learns it lost the focus only
 * if it was the one that had it directly.
 *
 * **An id and a native method, not a stored closure.** A JNI native method carries no captured
 * state, so the Swift side keeps the handlers and this class carries the key -- the same
 * arrangement `CustomListAdapter`'s lazy rows use. `SwiftAction` would not do: it takes no
 * arguments, and the id is exactly what has to travel.
 *
 * 把視窗內**每一次**焦點移動回報進 Swift。
 *
 * **先試過 `View.setOnFocusChangeListener`,而它回報的是錯的東西。** 它只為「被設定的那個 view」觸發、
 * 不為它裡面的任何東西觸發;而一個 SwiftCrossUI 的 widget 通常是一個容器:`EditText` 取得了焦點,而
 * 容器上的 listener 保持沉默。2026-09-16 在模擬器上以 P70 量到——一次點擊把游標放進了 email 欄位,
 * 而 app 仍然顯示 `focused field: none` 與 `focus changes heard: 0`。
 *
 * `ViewTreeObserver.OnGlobalFocusChangeListener` 是「觀察 AppKit 視窗 first responder」在 Android 上的
 * 對應物,理由與 AppKit 那個檔案所給的相同:要回報的那個事件,正是 widget 不會被告知的事件——焦點
 * **離開**它。一個 view 只有在「焦點原本就直接在它身上」時,才會知道自己失去了焦點。
 *
 * **用一個 id 加一個 native method,而不是存一個 closure。** 一個 JNI native method 不帶任何被捕捉的
 * 狀態,因此 Swift 那一側保有 handler,而這個類別帶著鍵——與 `CustomListAdapter` 的懶載入列是同一種
 * 安排。`SwiftAction` 不夠用:它不帶引數,而那個 id 正是必須被帶過去的東西。
 *
 * **On the window's observer only while the view is attached.** The listener used to be added to
 * `getViewTreeObserver()` once and never removed, so the window kept every listener for every view
 * that had ever been `.focused`, each reporting an id whose Swift watch held its view. The view now
 * holds this as an attach-state listener and moves it on and off the observer; nothing but the
 * view holds the view, and when Swift says the id is gone the listener takes itself off.
 *
 * **只在 view 附加期間掛在視窗的 observer 上。** 這個 listener 原本一次加到 `getViewTreeObserver()` 上、
 * 從不移除，於是視窗留著每一個曾經 `.focused` 的 view 的 listener,各自回報一個「其 Swift watch 持有該 view」
 * 的 id。現在由 view 以 attach-state listener 持有它，並把它掛上、拿下 observer;除了 view 自己沒有東西持有
 * view,而 Swift 說 id 已不存在時,listener 會把自己拿掉。
 */
class SwiftFocusChangeListener(private val id: Int) :
    ViewTreeObserver.OnGlobalFocusChangeListener, View.OnAttachStateChangeListener {

    private var observer: ViewTreeObserver? = null

    fun install(view: View) {
        view.addOnAttachStateChangeListener(this)
        if (view.isAttachedToWindow) attach(view)
    }

    override fun onViewAttachedToWindow(v: View) = attach(v)

    override fun onViewDetachedFromWindow(v: View) = detach()

    private fun attach(view: View) {
        detach()
        val treeObserver = view.viewTreeObserver
        treeObserver.addOnGlobalFocusChangeListener(this)
        observer = treeObserver
    }

    private fun detach() {
        observer?.let { if (it.isAlive) it.removeOnGlobalFocusChangeListener(this) }
        observer = null
    }

    override fun onGlobalFocusChanged(oldFocus: View?, newFocus: View?) {
        // No view is passed on. Swift re-asks its own widget `hasFocus()` instead, because the
        // question is "does the watched widget, or anything inside it, have the focus" --
        // and neither `oldFocus` nor `newFocus` answers that without walking the tree here.
        // 不傳遞任何 view。Swift 改為重新去問它自己的 widget `hasFocus()`,因為問題是「被觀察的那個
        // widget、或它裡面的任何東西,有沒有焦點」——而 `oldFocus` 與 `newFocus` 都無法在不於此處
        // 走訪整棵樹的情況下回答它。
        if (!swiftFocusChanged(id)) detach()
    }

    private external fun swiftFocusChanged(id: Int): Boolean
}
