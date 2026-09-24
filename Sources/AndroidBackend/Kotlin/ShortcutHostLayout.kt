package dev.swiftcrossui.androidbackend

import android.content.Context
import android.view.KeyEvent
import android.widget.LinearLayout

/**
 * The window's content view, with one addition: it offers an unconsumed key to the app's shortcut
 * table before giving up on it.
 *
 * **Why this exists, and it is a reachability problem rather than a correctness one.** App-menu
 * shortcuts already worked through `View.OnUnhandledKeyEventListener` on the decor view -- `adb
 * shell input keycombination` fires all three of P71's, including the disabled one staying silent.
 * What could not reach them was an action file. `AndroidSynthesiser` posts through
 * `Activity.dispatchKeyEvent`, and `ViewRootImpl` runs the unhandled-key manager AFTER
 * `mView.dispatchKeyEvent` returns -- one level above anything an application can post to. The way
 * round it was tried and refused: `Instrumentation.sendKeySync` needs INJECT_EVENTS, a permission
 * an app cannot hold, and the SecurityException is quoted in `AndroidSynthesiser`.
 *
 * **This keeps the semantics and lowers the altitude.** `super.dispatchKeyEvent` runs first, so the
 * table is consulted only after the whole view hierarchy has declined the key -- which is exactly
 * what "unhandled" meant, one level down. A text field still sees its own keys first, and a plain
 * `s` typed into one never reaches the table.
 *
 * **Nothing fires twice.** Returning true here makes `mView.dispatchKeyEvent` return true, so
 * `ViewRootImpl` stops before the unhandled-key manager. The decor listener stays installed and
 * simply never sees a key this one matched.
 *
 * It holds the listener rather than a native method of its own: `SwiftUnhandledKeyListener` already
 * carries the ACTION_DOWN guard, the `getUnicodeChar(0)` decision and the JNI binding, and a second
 * copy of those is a second place for them to drift.
 *
 * 這個視窗的 content view,外加一件事:在放棄一個沒有被消耗的按鍵之前,先把它交給 app 的快捷鍵表。
 *
 * **它為何存在——那是一個「抵達不了」的問題,不是「不正確」的問題。** app 選單快捷鍵原本就能經由 decor view 上的
 * `View.OnUnhandledKeyEventListener` 運作——`adb shell input keycombination` 會觸發 P71 的三個
 * 快捷鍵,包含「已停用的那個保持沉默」。抵達不了它們的是**動作檔**。`AndroidSynthesiser` 是經由 `Activity.dispatchKeyEvent` 投遞的,而
 * `ViewRootImpl` 是在 `mView.dispatchKeyEvent` 回傳**之後** 才執行 unhandled-key
 * manager——那比任何應用程式投遞得到的層級高一層。繞過去的辦法試過也被拒了: `Instrumentation.sendKeySync` 需要 INJECT_EVENTS,那是一個 app
 * 持有不了的權限, 而那個 SecurityException 引在 `AndroidSynthesiser` 裡。
 *
 * **這個做法保留語意、降低高度。** `super.dispatchKeyEvent` 先跑,因此只有在**整個 view 階層都拒絕**了
 * 該按鍵之後,才會去查那張表——那正是「unhandled」原本的意思,只是低了一層。文字欄位仍然先看到屬於它 自己的按鍵,而打進欄位裡的一個普通 `s` 永遠到不了那張表。
 *
 * **不會有東西觸發兩次。** 此處回傳 true 會讓 `mView.dispatchKeyEvent` 回傳 true,於是 `ViewRootImpl` 在 unhandled-key
 * manager 之前就停了。decor 上的那個 listener 仍然掛著,只是再也看不到被這裡比中的按鍵。
 *
 * 它**持有**那個 listener,而不是自己再宣告一個 native method:`SwiftUnhandledKeyListener` 已經帶著 ACTION_DOWN
 * 的守衛、`getUnicodeChar(0)` 的抉擇、以及那個 JNI 綁定;再抄一份,就是多一個讓它們漂移的地方。
 */
class ShortcutHostLayout(context: Context) : LinearLayout(context) {
    var shortcutListener: SwiftUnhandledKeyListener? = null

    init {
        // **A key event follows the FOCUS CHAIN, and without this the override below is never
        // called at all.**
        //
        // `ViewGroup.dispatchKeyEvent` does not walk its children: it dispatches to `mFocused`, or
        // to itself if it is the focused view, and otherwise returns false. So when nothing in the
        // app has focus -- which is the ordinary state of a window with no text field, and exactly
        // P71's state -- the decor's `mFocused` is null and no view below it ever sees the key.
        // That is measured, not assumed: an instrumented build of this class logged nothing at all
        // across 21 replayed actions on 2026-09-23, and it is the same reason an app-menu shortcut
        // needs the unhandled-key manager in the first place.
        //
        // `FOCUS_AFTER_DESCENDANTS` is what keeps this from taking focus away from anything that
        // wants it: a text field, a button, anything focusable inside gets first refusal, and this
        // view holds focus only when the alternative is nobody holding it. `KeyEventContainer`
        // uses the same pair for the same reason.
        //
        // **一個按鍵事件跟著**焦點鏈**走,而少了這一段,下面那個覆寫根本不會被呼叫。**
        //
        // `ViewGroup.dispatchKeyEvent` 不會走訪它的子節點:它只把事件派給 `mFocused`,或在自己就是
        // 聚焦 view 時派給自己,否則直接回傳 false。因此當 app 裡沒有任何東西持有焦點時
        // ——一個沒有文字欄位的視窗本來就是這個狀態,而那正是 P71 的狀態——decor 的 `mFocused` 是 null,
        // 它底下沒有任何 view 看得到那個按鍵。這是量出來的、不是假設的:2026-09-23,一個對本類別加了
        // 儀器的版本,在 21 個重放動作之間**一行都沒有印出來**;而那也正是「app 選單快捷鍵一開始就需要
        // unhandled-key manager」的同一個理由。
        //
        // `FOCUS_AFTER_DESCENDANTS` 是讓它不會把焦點從「想要焦點的東西」手上搶走的關鍵:文字欄位、按鈕、
        // 任何在裡面可聚焦的東西都有優先權;而這個 view 只在「否則就沒有人持有焦點」時才持有它。
        // `KeyEventContainer` 基於同樣的理由使用同一組設定。
        isFocusable = true
        isFocusableInTouchMode = true
        descendantFocusability = FOCUS_AFTER_DESCENDANTS
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestFocus()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (super.dispatchKeyEvent(event)) return true
        return shortcutListener?.onUnhandledKeyEvent(this, event) ?: false
    }
}
