package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.inspector.WindowInspector
import java.lang.ref.WeakReference

/**
 * The windows this app puts in front of its activity -- sheets and popovers --
 * so the in-process synthesiser can reach them.
 *
 * `Activity.dispatchTouchEvent` delivers to the activity's own window only. A
 * sheet is a Dialog and a popover a PopupWindow, each a window of its own, so
 * every synthesised tap aimed at one landed on the activity behind it: P60's
 * "+1" inside its settings sheet was pressed and the count stayed 0 (2026-10-01).
 * Each of them registers its root view here while shown; the synthesiser hands
 * an event to the focused one, translated from activity-window coordinates to
 * that window's own.
 *
 * Menus and Spinner dropdowns are built by the platform and never register
 * here; focused() finds them through WindowInspector instead.
 *
 * 本 app 放在 activity 前方的視窗——sheet 與 popover——好讓行程內的 synthesiser 碰得到它們。
 * `Activity.dispatchTouchEvent` 只投遞到 activity 自己的視窗。sheet 是一個 Dialog、popover 是一個
 * PopupWindow,各自都是獨立的視窗，因此每一次瞄準它們的合成點擊都落在後方的 activity 上:P60 設定
 * sheet 裡的「+1」被按了，count 仍是 0(2026-10-01)。它們在顯示期間把根 view 登記在這裡;synthesiser
 * 把事件交給有焦點的那一個，並把座標從 activity 視窗換算到該視窗自己的座標。選單與 Spinner 下拉由
 * 平台建立，不經過這裡登記，由 focused() 以 WindowInspector 找到。
 */
object FrontWindows {
    private val roots = ArrayList<WeakReference<View>>()

    @JvmStatic
    fun add(root: View) {
        remove(root)
        roots.add(WeakReference(root))
    }

    @JvmStatic
    fun remove(root: View) {
        roots.removeAll { it.get() == null || it.get() === root }
    }

    /**
     * The front window with focus, or null when an activity's own window has it.
     *
     * A registered sheet or popover first. Otherwise any window of this process
     * that has focus and is not an activity's own: a PopupMenu, a Spinner's
     * dropdown, an alert. The platform builds those and keeps them private, so
     * they never register; `WindowInspector.getGlobalWindowViews` (API 29, public,
     * no permission) lists every window root of the process, theirs included.
     * Without it the replay could open P92's menu and choose nothing from it
     * ("no shown view has the text Edit", 2026-10-21).
     *
     * 有焦點的前景視窗；某個 activity 自己的視窗有焦點時為 null。先找登記過的 sheet 或 popover;否則找本行程
     * 中任何有焦點、且不是 activity 自身的視窗:PopupMenu、Spinner 的下拉、alert。這些由平台建立並保持私有，
     * 從不登記;`WindowInspector.getGlobalWindowViews`(API 29,公開，不需權限)列出本行程每個視窗的根，
     * 包括它們。沒有它時，重放能打開 P92 的選單，卻選不了任何項目(2026-10-21)。
     */
    @JvmStatic
    fun focused(): View? {
        roots.mapNotNull { it.get() }
            .lastOrNull { it.isAttachedToWindow && it.hasWindowFocus() }
            ?.let { return it }
        return WindowInspector.getGlobalWindowViews().lastOrNull {
            it.isAttachedToWindow && it.hasWindowFocus() && !isActivityWindow(it)
        }
    }

    /** Whether [root] is the decor view of the activity it was made for. */
    private fun isActivityWindow(root: View): Boolean {
        var context: Context? = root.context
        while (context is ContextWrapper) {
            if (context is Activity) return context.window?.decorView === root
            context = context.baseContext
        }
        return false
    }

    /**
     * Delivers [event], given in the activity window's coordinates, to the
     * focused front window. Returns false when there is none.
     */
    @JvmStatic
    fun dispatch(activity: Activity, event: MotionEvent): Boolean {
        val root = focused() ?: return false
        val decor = activity.window?.decorView ?: return false
        val activityOrigin = IntArray(2)
        val rootOrigin = IntArray(2)
        decor.getLocationOnScreen(activityOrigin)
        root.getLocationOnScreen(rootOrigin)
        val copy = MotionEvent.obtain(event)
        copy.offsetLocation(
            (activityOrigin[0] - rootOrigin[0]).toFloat(),
            (activityOrigin[1] - rootOrigin[1]).toFloat(),
        )
        root.dispatchTouchEvent(copy)
        copy.recycle()
        return true
    }

    /**
     * Delivers a key to the focused front window, as a keyboard does: Escape
     * or Back then reaches the sheet's dialog, which cancels it. Returns false
     * when the activity's own window has focus. Without it every key went to
     * the activity and Escape left P49's sheet open (2026-10-20).
     */
    @JvmStatic
    fun dispatchKey(event: KeyEvent): Boolean {
        val root = focused() ?: return false
        root.dispatchKeyEvent(event)
        return true
    }
}
