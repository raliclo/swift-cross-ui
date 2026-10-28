package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.os.Build
import android.os.OutcomeReceiver
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.util.Consumer
import androidx.core.app.MultiWindowModeChangedInfo
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import java.util.WeakHashMap

/**
 * `BackendFeatures.WindowBehaviors` on Android: what closable, minimizable and resizable mean for an
 * activity, and how each is enforced. AndroidBackend+WindowBehaviors.swift has the measurements.
 *
 * - closable false: an enabled OnBackPressedCallback takes Back. The dispatcher receives the Back
 *   key and the back gesture alike -- through Activity.onBackPressed while the manifest leaves
 *   enableOnBackInvokedCallback unset, through an OnBackInvokedCallback that ComponentActivity
 *   registers once it is set -- so one callback covers both paths and every API level from 31 up.
 *   Sheets are dialogs with their own Back handling and are not affected.
 * - minimizable false: lock task mode, which on a device that is not managed is screen pinning.
 *   The system asks the user to confirm; once pinned, Home and Recents do not leave the app. If the
 *   user declines or unpins, that stands until the behaviour is set to false again.
 * - resizable false: a window after the first starts as ScuiFixedSizeWindowActivity, which the
 *   manifest declares resizeableActivity="false"; that attribute exists only in the manifest. Any
 *   window -- the first included, and a later one whose behaviour changes after it opened -- that
 *   is in a free-form window while not resizable asks to go full screen, which is what the system
 *   itself does with a non-resizable activity started in free-form mode.
 *
 * Android 上的 `BackendFeatures.WindowBehaviors`:closable、minimizable、resizable 對一個 activity 的意義，以及
 * 各自如何執行。量測記錄在 AndroidBackend+WindowBehaviors.swift。
 *
 * - closable 為 false:一個啟用中的 OnBackPressedCallback 接下返回。dispatcher 同時收到返回鍵與返回手勢——manifest 未設
 *   enableOnBackInvokedCallback 時經由 Activity.onBackPressed,設了之後經由 ComponentActivity 註冊的 OnBackInvokedCallback——
 *   所以一個 callback 涵蓋兩條路徑，以及 31 以上的每個 API level。sheet 是有自己返回處理的 dialog,不受影響。
 * - minimizable 為 false:lock task 模式，在未受管理的裝置上就是螢幕固定。系統會請使用者確認；固定之後，Home 與「最近
 *   使用」都不會離開 app。使用者拒絕或取消固定時，該結果維持到行為再次被設為 false 為止。
 * - resizable 為 false:第一個之後的視窗以 ScuiFixedSizeWindowActivity 啟動，manifest 宣告它
 *   resizeableActivity="false";這個屬性只存在於 manifest。任何視窗——包括第一個，以及開啟後才改變行為的後續視窗——在
 *   不可縮放時若處於自由視窗中，會要求進入全螢幕，這正是系統本身對以自由視窗模式啟動的不可縮放 activity 所做的事。
 */
object ScuiWindowBehaviors {
    private const val TAG = "SCUI-WindowBehaviors"

    private class Behaviors(val closable: Boolean, val minimizable: Boolean, val resizable: Boolean)

    /** The behaviours of the windows after the first, by token, kept for their activities. */
    private val byToken = HashMap<String, Behaviors>()

    private val states = WeakHashMap<Activity, State>()

    /** Sets the behaviours of the first window, the app's own activity. 設定第一個視窗(app 自己的 activity)的行為。 */
    @JvmStatic
    fun setForActivity(activity: Activity, closable: Boolean, minimizable: Boolean, resizable: Boolean) {
        apply(activity, Behaviors(closable, minimizable, resizable))
    }

    /**
     * Sets the behaviours of a window after the first, whose activity may not have started yet:
     * ScuiWindowActivity applies them in onCreate, and openWindow picks the activity class by them.
     *
     * 設定第一個之後的視窗的行為，其 activity 可能尚未啟動:ScuiWindowActivity 在 onCreate 中套用，openWindow 依它們
     * 選擇 activity 類別。
     */
    @JvmStatic
    fun setForToken(token: String, closable: Boolean, minimizable: Boolean, resizable: Boolean) {
        val behaviors = Behaviors(closable, minimizable, resizable)
        byToken[token] = behaviors
        ScuiWindows.activities[token]?.let { apply(it, behaviors) }
    }

    /** Whether a later window should start as the non-resizable activity. 後續視窗是否應以不可縮放的 activity 啟動。 */
    @JvmStatic
    fun isResizable(token: String): Boolean = byToken[token]?.resizable ?: true

    @JvmStatic
    fun activityCreated(activity: Activity, token: String) {
        byToken[token]?.let { apply(activity, it) }
    }

    @JvmStatic
    fun windowClosed(activity: Activity, token: String) {
        byToken.remove(token)
        // The state holds its activity, so a weak key alone would never let it go.
        // state 持有它的 activity,只靠弱鍵永遠不會釋放。
        states.remove(activity)
    }

    private fun apply(activity: Activity, behaviors: Behaviors) {
        val component = activity as? ComponentActivity
        if (component == null) {
            Log.w(TAG, "not a ComponentActivity, behaviours not applied: $activity")
            return
        }
        states.getOrPut(activity) { State(component) }.update(behaviors)
    }

    private class State(val activity: ComponentActivity) {
        var closable = true
        var minimizable = true
        var resizable = true
        /** Set when this code started lock task mode, so it stops only what it started. */
        var pinned = false

        val backBlocker =
            object : OnBackPressedCallback(false) {
                override fun handleOnBackPressed() {
                    Log.i(TAG, "Back ignored: the window is not closable")
                }
            }

        init {
            activity.onBackPressedDispatcher.addCallback(activity, backBlocker)
            activity.addOnMultiWindowModeChangedListener(
                Consumer<MultiWindowModeChangedInfo> { info ->
                    if (info.isInMultiWindowMode && !resizable) leaveFreeform()
                }
            )
        }

        fun update(behaviors: Behaviors) {
            if (closable != behaviors.closable) {
                closable = behaviors.closable
                backBlocker.isEnabled = !closable
                Log.i(TAG, "closable=$closable")
            }
            if (resizable != behaviors.resizable) {
                resizable = behaviors.resizable
                Log.i(TAG, "resizable=$resizable")
                if (!resizable) whenResumed { leaveFreeform() }
            }
            if (minimizable != behaviors.minimizable) {
                minimizable = behaviors.minimizable
                Log.i(TAG, "minimizable=$minimizable")
                if (!minimizable) {
                    whenResumed { pin() }
                } else if (pinned) {
                    pinned = false
                    runCatching { activity.stopLockTask() }
                        .onFailure { Log.w(TAG, "stopLockTask failed: $it") }
                }
            }
        }

        /**
         * startLockTask needs a resumed activity, and the first behaviours arrive from onCreate.
         * startLockTask 需要已 resume 的 activity,而第一次的行為來自 onCreate。
         */
        private fun whenResumed(action: () -> Unit) {
            val lifecycle = activity.lifecycle
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                action()
                return
            }
            lifecycle.addObserver(
                object : LifecycleEventObserver {
                    override fun onStateChanged(
                        source: androidx.lifecycle.LifecycleOwner,
                        event: Lifecycle.Event,
                    ) {
                        if (event == Lifecycle.Event.ON_RESUME) {
                            lifecycle.removeObserver(this)
                            action()
                        }
                    }
                }
            )
        }

        private fun pin() {
            if (minimizable || pinned) return
            pinned = true
            runCatching { activity.startLockTask() }
                .onSuccess { Log.i(TAG, "startLockTask requested") }
                .onFailure { Log.w(TAG, "startLockTask failed: $it") }
        }

        /**
         * A free-form window goes full screen (API 34, Activity.requestFullscreenMode). The call is
         * made in any multi-window mode; where the system does not grant it the refusal is logged and
         * the window stays where it is. Split screen on a large screen was not measured.
         * 自由視窗進入全螢幕(API 34,Activity.requestFullscreenMode)。在任何多視窗模式下都會呼叫；系統不允許時會記錄被拒絕，
         * 視窗維持原處。大螢幕上的分割畫面未量測。
         */
        private fun leaveFreeform() {
            if (resizable || !activity.isInMultiWindowMode) return
            if (Build.VERSION.SDK_INT < 34) {
                Log.w(TAG, "not resizable, but requestFullscreenMode needs API 34")
                return
            }
            activity.requestFullscreenMode(
                Activity.FULLSCREEN_MODE_REQUEST_ENTER,
                object : OutcomeReceiver<Void, Throwable> {
                    override fun onResult(result: Void?) {
                        Log.i(TAG, "not resizable: left the free-form window for full screen")
                    }

                    override fun onError(error: Throwable) {
                        Log.w(TAG, "not resizable: full screen refused: $error")
                    }
                },
            )
        }
    }
}

/**
 * A later window that must not be resized: the same activity, declared resizeableActivity="false"
 * in the manifest (package_android.zsh). Measured on the API 36 emulator with freeform enabled: an
 * activity declared so and started with --windowingMode 5 opened full screen, and `am task resize`
 * on its task logged "resizeTask not allowed".
 *
 * 不可縮放的後續視窗：同一個 activity,在 manifest(package_android.zsh)中宣告 resizeableActivity="false"。在啟用
 * freeform 的 API 36 emulator 上實測：如此宣告的 activity 以 --windowingMode 5 啟動時開成全螢幕，對其工作執行
 * `am task resize` 會記錄「resizeTask not allowed」。
 */
class ScuiFixedSizeWindowActivity : ScuiWindowActivity()
