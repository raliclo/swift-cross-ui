package dev.swiftcrossui.androidbackend

import android.content.Context
import android.view.KeyEvent
import android.view.ViewGroup

/**
 * A view that takes focus and reports the keys it receives.
 *
 * **Taking focus is half the feature and the half that is easy to leave out**, which is the lesson
 * `NSKeyEventTarget` wrote down after the AppKit version compiled, ran, and reported nothing. On
 * Android the two halves are `isFocusableInTouchMode` and an actual `requestFocus()`: a container
 * is not focusable by default, and a focusable view that nothing ever focuses receives no keys
 * however well the rest is written.
 *
 * **`dispatchKeyEvent`, and `super` first.** A focused descendant -- a text field -- must see its
 * own keys before this container claims anything, so `super.dispatchKeyEvent` runs first and a
 * `true` from it ends the matter. That is the same rule AppKit's version states as "a text control
 * keeps focus": typing into a field is exactly where taking the keys away is plainly wrong.
 *
 * **`onKeyDown`/`onKeyUp` would not have been enough.** They are only called for keys the view
 * hierarchy did not otherwise consume, and a modifier such as Shift is consumed by the framework's
 * meta-state tracking before it gets there -- so a modifiers-only change, which `KeyPress` reports
 * as `key == nil`, would never arrive.
 *
 * 一個會取得焦點、並回報它所收到的按鍵的 view。
 *
 * **取得焦點是這項功能的一半,而且是容易被漏掉的那一半**——那正是 AppKit 版本「編得過、跑得動、 卻什麼都不回報」之後,`NSKeyEventTarget` 記下的教訓。在
 * Android 上,那兩半是 `isFocusableInTouchMode` 與一次真正的 `requestFocus()`:容器預設不可聚焦,而一個「可聚焦但從來 沒有人去聚焦它」的
 * view,不論其餘部分寫得多好,都收不到任何按鍵。
 *
 * **用 `dispatchKeyEvent`,而且 `super` 先跑。** 一個持有焦點的後代——例如文字欄位——必須先看到 屬於它自己的按鍵,然後這個容器才認領任何東西;因此
 * `super.dispatchKeyEvent` 先執行,而它回傳 `true` 就到此為止。這與 AppKit 版本所寫的「文字控制項保有焦點」是同一條規則:正在輸入,
 * 正是把按鍵搶走明顯錯誤的那個情況。
 *
 * **`onKeyDown`/`onKeyUp` 不夠用。** 它們只在 view 階層沒有以其他方式消耗掉該按鍵時才會被呼叫, 而像 Shift 這類修飾鍵,在抵達那裡之前就已被框架的
 * meta-state 追蹤消耗掉了——於是 「只有修飾鍵改變」(`KeyPress` 以 `key == nil` 回報的那一種)永遠不會送達。
 */
class KeyEventContainer(context: Context) : ViewGroup(context) {
    companion object {
        const val PHASE_DOWN = 0
        const val PHASE_UP = 1
        const val PHASE_REPEAT = 2
    }

    var onKey: SwiftAction? = null

    /** Android's `KeyEvent` keycode, which the Swift side maps to a `KeyEquivalent`. */
    var keyCode = 0
        private set

    /** The character this key produces with NO modifiers -- which key it is. */
    var bareChar = 0
        private set

    /** The character it produced WITH the modifiers held -- what it typed. */
    var typedChar = 0
        private set

    var metaState = 0
        private set

    var phase = PHASE_DOWN
        private set

    var isModifier = false
        private set

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        // Descendants keep their own focus; this container only takes it when nothing else wants
        // it. FOCUS_BEFORE_DESCENDANTS is the default and would put a text field behind us.
        // 後代保有它們自己的焦點;只有在沒有別的東西要它時,這個容器才拿走。
        // 預設的 FOCUS_BEFORE_DESCENDANTS 會把文字欄位排在我們後面。
        descendantFocusability = FOCUS_AFTER_DESCENDANTS
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            getChildAt(i).layout(0, 0, r - l, b - t)
        }
    }

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        measureChildren(widthSpec, heightSpec)
        setMeasuredDimension(resolveSize(0, widthSpec), resolveSize(0, heightSpec))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestFocus()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val action = onKey ?: return super.dispatchKeyEvent(event)
        if (super.dispatchKeyEvent(event)) return true

        phase =
            when {
                event.action == KeyEvent.ACTION_UP -> PHASE_UP
                event.repeatCount > 0 -> PHASE_REPEAT
                else -> PHASE_DOWN
            }
        keyCode = event.keyCode
        metaState = event.metaState
        isModifier = KeyEvent.isModifierKey(event.keyCode)
        // `getUnicodeChar(0)` asks which key this is, ignoring what is held; the no-argument form
        // asks what it produced. `SwiftUnhandledKeyListener` records the same distinction, and
        // `KeyPress` is written in exactly these two halves.
        // `getUnicodeChar(0)` 問的是「這是哪一個鍵」,與按著什麼無關;不帶引數的那個問的是
        // 「它產生了什麼」。`SwiftUnhandledKeyListener` 記載了同一個分別,而 `KeyPress` 正是由
        // 這兩半寫成的。
        bareChar = event.getUnicodeChar(0)
        typedChar = event.unicodeChar
        action.call()

        // **Not consumed.** Reporting a key is not the same as handling it, and swallowing every
        // key would take Back and Tab away from the rest of the app. AppKit's version calls
        // `super` for anything it did not report, for the same reason.
        // **不消耗它。** 回報一個按鍵與處理一個按鍵不是同一件事;吞掉每一個按鍵,會把 Back 與 Tab
        // 從 app 其餘部分手上拿走。AppKit 的版本對它沒有回報的東西呼叫 `super`,理由相同。
        return false
    }
}
