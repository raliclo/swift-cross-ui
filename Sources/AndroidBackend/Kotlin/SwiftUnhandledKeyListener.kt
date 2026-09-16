package dev.swiftcrossui.androidbackend

import android.view.KeyEvent
import android.view.View

/**
 * Application-menu shortcuts on Android, which has no menu bar to hang them on.
 *
 * **`.commands` cannot draw anything here, and that is the platform's answer rather than a gap.**
 * Android has no application menu: an app's global actions live in a toolbar overflow or a
 * navigation drawer, both of which belong to the app's own layout rather than to the window
 * chrome. What a `CommandMenu` item still means on Android is its SHORTCUT -- an attached
 * hardware keyboard should fire it -- and that is what upstream's own TODO asked for:
 * "Register app menu items as shortcuts when we support keyboard shortcuts."
 *
 * **`OnUnhandledKeyEventListener`, not `OnKeyListener`.** The unhandled variant runs only after
 * every view in the hierarchy has declined the event, which is exactly what an app-level shortcut
 * must do: Cmd-S while a text field has focus must not be swallowed before the field sees it, and
 * a plain `s` typed into that field must never reach here at all. An `OnKeyListener` on the root
 * sees events first and would have to guess which ones were meant for the focused view.
 *
 * Android 上的應用程式選單快捷鍵——而 Android 沒有選單列可以掛它們。
 *
 * **`.commands` 在此畫不出任何東西,而那是這個平台的答案,不是一個缺口。** Android 沒有應用程式選單:
 * 一個 app 的全域動作住在 toolbar 的溢位選單或側邊抽屜裡,而那兩者都屬於 app 自己的版面、不屬於視窗外框。
 * 一個 `CommandMenu` 項目在 Android 上仍然成立的部分是它的**快捷鍵**——接上的實體鍵盤應該要能觸發它
 * ——而那正是上游自己的 TODO 所要的:「Register app menu items as shortcuts when we support keyboard
 * shortcuts.」
 *
 * **用 `OnUnhandledKeyEventListener`,不是 `OnKeyListener`。** unhandled 這個變體只在 view 階層中
 * 每一個 view 都拒絕了該事件之後才執行,而那正是一個 app 層級的快捷鍵**必須**做的事:當文字欄位持有
 * 焦點時,Cmd-S 不該在該欄位看到它之前就被吞掉;而打進那個欄位的一個普通 `s`,則根本不該抵達這裡。
 * 掛在根節點上的 `OnKeyListener` 會**先**看到事件,於是它得去猜哪些是給那個聚焦 view 的。
 */
class SwiftUnhandledKeyListener(private val id: Int) : View.OnUnhandledKeyEventListener {
    override fun onUnhandledKeyEvent(view: View?, event: KeyEvent?): Boolean {
        if (event == null) return false
        // ACTION_DOWN only. A key press delivers down and up, and acting on both would run every
        // shortcut twice -- which for a "delete" command is not a cosmetic difference.
        // 只處理 ACTION_DOWN。一次按鍵會送出 down 與 up 兩個事件,兩個都處理會讓每一個快捷鍵執行兩次
        // ——而對一個「刪除」命令來說,那不是外觀上的差別。
        if (event.action != KeyEvent.ACTION_DOWN) return false
        // `getUnicodeChar(0)` -- the character the key would produce with NO modifiers.
        //
        // The no-argument `unicodeChar` applies the live meta state, and a Ctrl combination
        // usually maps to a control code or to 0 there, so Ctrl-S would arrive as nothing to
        // compare against. Passing 0 asks the same question the shortcut is written in: which
        // key is this, ignoring what is held down.
        //
        // 用 `getUnicodeChar(0)`——「這個鍵在**沒有任何修飾鍵**時會產生的字元」。
        //
        // 不帶引數的 `unicodeChar` 會套用當下的 meta state,而 Ctrl 組合在那裡通常對應到一個控制碼
        // 或 0,於是 Ctrl-S 抵達時會是一個無從比對的東西。傳入 0,問的才是「這是哪一個鍵」——正是那個
        // 快捷鍵被寫下來時所用的問法,與按著什麼無關。
        return swiftUnhandledKey(id, event.getUnicodeChar(0), event.metaState)
    }

    /**
     * Returns whether a shortcut matched, which is what the listener must report.
     *
     * Saying `true` for a key nothing matched would swallow it from everything downstream.
     * 回傳「是否有快捷鍵相符」,那正是這個 listener 必須回報的東西。
     *
     * 對一個沒有任何東西相符的按鍵回答 `true`,會把它從下游的一切手中吞掉。
     */
    private external fun swiftUnhandledKey(id: Int, unicodeChar: Int, metaState: Int): Boolean
}
