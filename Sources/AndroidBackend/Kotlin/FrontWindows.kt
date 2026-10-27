package dev.swiftcrossui.androidbackend

import android.app.Activity
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
     * The front window with focus, or null when [activity]'s own window has it.
     *
     * A registered sheet or popover first. Otherwise any window of this process
     * that has focus other than [activity]'s own -- the window the synthesiser
     * dispatches into anyway: a PopupMenu, a Spinner's dropdown, an alert, or
     * another activity such as P60's settings window. The platform builds menus
     * and dropdowns and keeps them private, so they never register;
     * `WindowInspector.getGlobalWindowViews` (API 29, public, no permission) lists
     * every window root of the process, theirs included. Without it the replay
     * could open P92's menu and choose nothing from it ("no shown view has the
     * text Edit", 2026-10-21).
     *
     * Only [activity]'s decor is left out, compared by identity. Two broader rules
     * fail. Walking each root's context up to an Activity never matches, so the
     * target activity's window counts as a front window too, every key goes
     * straight to its decor, AndroidSynthesiser's Control-shortcut offer never
     * runs, and P94's editor reads "changes: 0". Leaving out every window of type
     * TYPE_BASE_APPLICATION loses P60's settings window, an activity of its own
     * ("no shown view has the text +1").
     *
     * 有焦點的前景視窗;[activity] 自己的視窗有焦點時為 null。先找登記過的 sheet 或 popover;否則找本行程中
     * 除了 [activity] 自己(synthesiser 本來就送進去的那個視窗)以外任何有焦點的視窗:PopupMenu、Spinner 的下拉、
     * alert,或另一個 activity,例如 P60 的設定視窗。選單與下拉由平台建立並保持私有，從不登記;
     * `WindowInspector.getGlobalWindowViews`(API 29,公開，不需權限)列出本行程每個視窗的根，包括它們。少了它，
     * 重放能打開 P92 的選單卻選不到任何東西(「no shown view has the text Edit」,2026-10-21)。
     * 只排除 [activity] 的 decor,以同一物件比較。兩種較寬的規則都不行。沿每個根的 context 找到 Activity 從不會比對成功,
     * 於是目標 activity 的視窗也被當成前景視窗，按鍵全部直接送進它的 decor,AndroidSynthesiser 補送 Control 快捷鍵的
     * 那一步不會執行,P94 的編輯器讀作「changes: 0」。排除所有 TYPE_BASE_APPLICATION 視窗，則會失去 P60 的設定視窗
     * ——它本身是個 activity(「no shown view has the text +1」)。
     */
    @JvmStatic
    fun focused(activity: Activity?): View? {
        roots.mapNotNull { it.get() }
            .lastOrNull { it.isAttachedToWindow && it.hasWindowFocus() }
            ?.let { return it }
        val own = activity?.window?.decorView
        return WindowInspector.getGlobalWindowViews().lastOrNull {
            it.isAttachedToWindow && it.hasWindowFocus() && it !== own
        }
    }

    /**
     * Delivers [event], given in the activity window's coordinates, to the
     * focused front window. Returns false when there is none.
     */
    @JvmStatic
    fun dispatch(activity: Activity, event: MotionEvent): Boolean {
        val root = focused(activity) ?: return false
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
     * when [activity]'s own window has focus. Without it every key went to
     * the activity and Escape left P49's sheet open (2026-10-20).
     */
    @JvmStatic
    fun dispatchKey(activity: Activity, event: KeyEvent): Boolean {
        val root = focused(activity) ?: return false
        root.dispatchKeyEvent(event)
        return true
    }
}
