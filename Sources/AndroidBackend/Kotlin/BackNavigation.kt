package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import java.util.WeakHashMap

/**
 * `BackendFeatures.BackNavigation` on Android: the system Back -- the key and the back gesture --
 * pops the innermost NavigationStack that has anything pushed (AndroidBackend+BackNavigation.swift).
 *
 * Each window's activity gets one OnBackPressedCallback, enabled only while Swift has a handler,
 * which is only while some stack can pop. Disabled, it is skipped by the dispatcher and Back does
 * what it does without it: the next enabled callback -- ScuiWindowBehaviors' blocker when the
 * window is not closable -- or the activity's own Back, which finishes a later window and sends the
 * first to the background. The dispatcher runs the enabled callback added last, so the callback
 * is added again each time it is enabled, which puts it above the blocker: a stack pops before
 * the window refuses to close.
 *
 * If Swift finds nothing to pop after all (a stack left the view graph since the handler was
 * set), it calls notHandled() from inside the callback; the callback is disabled and Back is
 * dispatched again on the next turn of the main loop, reaching whatever is below it.
 *
 * Android 上的 `BackendFeatures.BackNavigation`:系統返回——按鍵與返回手勢——彈出推入了內容的最內層 NavigationStack
 * (AndroidBackend+BackNavigation.swift)。
 *
 * 每個視窗的 activity 有一個 OnBackPressedCallback,只在 Swift 有 handler 時啟用，也就是只在某個堆疊可以彈出時啟用。停用時
 * dispatcher 會略過它，返回便做沒有它時會做的事：下一個啟用中的 callback——視窗不可關閉時是 ScuiWindowBehaviors 的攔截
 * ——或 activity 自己的返回，它結束後續視窗、把第一個視窗送到背景。dispatcher 執行最後加入的啟用中 callback,因此每次啟用
 * 時都重新加入它，讓它位於攔截之上：堆疊先彈出，視窗才拒絕關閉。
 *
 * 若 Swift 最後發現沒有東西可彈出(自 handler 設定以來有堆疊離開了 view graph),它會在 callback 內呼叫 notHandled();
 * callback 被停用，返回在主迴圈的下一輪再派送一次，抵達它底下的東西。
 */
object ScuiBackNavigation {
    private const val TAG = "SCUI-BackNavigation"

    /** The handlers of windows after the first, by token, kept for their activities. */
    private val byToken = HashMap<String, SwiftAction>()

    private val states = WeakHashMap<Activity, State>()

    /** What notHandled() does for the callback that is running. notHandled() 對正在執行的 callback 所做的事。 */
    private var letThrough: (() -> Unit)? = null

    /** Sets the handler of the first window, the app's own activity. 設定第一個視窗(app 自己的 activity)的 handler。 */
    @JvmStatic
    fun setForActivity(activity: Activity, action: SwiftAction?) {
        apply(activity, action)
    }

    /**
     * Sets the handler of a window after the first, whose activity may not have started yet.
     * 設定第一個之後的視窗的 handler,其 activity 可能尚未啟動。
     */
    @JvmStatic
    fun setForToken(token: String, action: SwiftAction?) {
        if (action != null) byToken[token] = action else byToken.remove(token)
        ScuiWindows.activities[token]?.let { apply(it, action) }
    }

    @JvmStatic
    fun activityCreated(activity: Activity, token: String) {
        byToken[token]?.let { apply(activity, it) }
    }

    @JvmStatic
    fun windowClosed(activity: Activity, token: String) {
        byToken.remove(token)
        states.remove(activity)?.let { it.callback.remove() }
    }

    /**
     * Called by Swift from inside the callback when there was nothing to pop: lets this Back through.
     * 沒有東西可彈出時，由 Swift 在 callback 內呼叫：讓這次返回通過。
     */
    @JvmStatic
    fun notHandled() {
        val letThrough = letThrough ?: return
        Log.i(TAG, "nothing to pop; Back passed on")
        letThrough()
    }

    /**
     * Runs a Back handler; if Swift calls notHandled() from inside it, `letThrough` disables the
     * callback that ran it and dispatches Back again. Used by windows here and by CustomSheet.
     * 執行一個返回 handler;若 Swift 在其中呼叫 notHandled(),`letThrough` 停用執行它的 callback 並再派送一次返回。
     * 由這裡的視窗與 CustomSheet 使用。
     */
    fun dispatch(action: SwiftAction, letThrough: () -> Unit) {
        this.letThrough = letThrough
        try {
            action.call()
        } finally {
            this.letThrough = null
        }
    }

    private fun apply(activity: Activity, action: SwiftAction?) {
        val component = activity as? ComponentActivity
        if (component == null) {
            Log.w(TAG, "not a ComponentActivity, Back not handled: $activity")
            return
        }
        states.getOrPut(activity) { State(component) }.update(action)
    }

    private class State(val activity: ComponentActivity) {
        var action: SwiftAction? = null

        val callback =
            object : OnBackPressedCallback(false) {
                override fun handleOnBackPressed() {
                    val action = action ?: return
                    dispatch(action) {
                        isEnabled = false
                        activity.window.decorView.post { activity.onBackPressedDispatcher.onBackPressed() }
                    }
                }
            }

        fun update(action: SwiftAction?) {
            this.action = action
            if (action != null) {
                if (!callback.isEnabled) {
                    callback.remove()
                    activity.onBackPressedDispatcher.addCallback(activity, callback)
                    callback.isEnabled = true
                    Log.i(TAG, "Back pops a NavigationStack")
                }
            } else if (callback.isEnabled) {
                callback.isEnabled = false
                Log.i(TAG, "Back released: no NavigationStack can pop")
            }
        }
    }
}
