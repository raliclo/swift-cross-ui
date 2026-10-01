package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.MotionEvent
import android.view.View
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
 * Menus and Spinner dropdowns are built by the platform and never pass through
 * here; those remain out of reach and the synthesiser still says so.
 *
 * 本 app 放在 activity 前方的視窗——sheet 與 popover——好讓行程內的 synthesiser 碰得到它們。
 * `Activity.dispatchTouchEvent` 只投遞到 activity 自己的視窗。sheet 是一個 Dialog、popover 是一個
 * PopupWindow,各自都是獨立的視窗，因此每一次瞄準它們的合成點擊都落在後方的 activity 上:P60 設定
 * sheet 裡的「+1」被按了，count 仍是 0(2026-10-01)。它們在顯示期間把根 view 登記在這裡;synthesiser
 * 把事件交給有焦點的那一個，並把座標從 activity 視窗換算到該視窗自己的座標。選單與 Spinner 下拉由
 * 平台建立，不經過這裡，仍然碰不到，synthesiser 也照樣會說出來。
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

    /** The front window with focus, or null when the activity's own window has it. */
    @JvmStatic
    fun focused(): View? =
        roots.mapNotNull { it.get() }.lastOrNull { it.isAttachedToWindow && it.hasWindowFocus() }

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
}
