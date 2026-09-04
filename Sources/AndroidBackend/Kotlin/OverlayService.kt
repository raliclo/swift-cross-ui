package dev.swiftcrossui.androidbackend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.provider.Settings
import android.view.View
import android.view.WindowManager

/**
 * Keeps a `windowLevel(.floating)` window on screen after the activity stops.
 *
 * **The overlay window was never the hard part.** Three things were tried
 * before this, and the third is why the service exists:
 *
 * 1. `Window.setType(TYPE_APPLICATION_OVERLAY)` on the activity's own window.
 *    No effect at all -- an activity's window type is assigned when it is
 *    attached.
 * 2. Adding the content to the WindowManager as `TYPE_APPLICATION_OVERLAY`.
 *    This works: measured 2026-09-04, the view laid out at 1080x2209, attached,
 *    and drew P37's text above everything -- until the activity stopped, at
 *    which point `dumpsys` reported `Surface: shown=false mLastHidden=true`
 *    with the view still VISIBLE and HAS_DRAWN, and the process listed as
 *    `prev /LAST`.
 * 3. The same through `applicationContext`'s WindowManager, in case the window
 *    was following the activity's token. Identical result. So it follows the
 *    *process* state, not the token.
 *
 * A foreground service is what keeps a process out of the cached state. That is
 * the whole of what this class is for; it draws nothing itself.
 *
 * **The notification is not optional and is not decoration.** A foreground
 * service must post one within a few seconds or the system kills the process,
 * and from API 34 it must also declare a `foregroundServiceType`. So an app
 * that floats on Android shows a notification. That is Android's price for the
 * feature rather than a choice made here, and it is why `.floating` is
 * expensive enough that `WindowLevel`'s own documentation says so.
 *
 * 讓一個 `windowLevel(.floating)` 的視窗在 activity 停止之後仍留在畫面上。
 *
 * **難的從來不是那個 overlay 視窗。** 在此之前試過三件事，而第三件正是本類別存在的理由：
 *
 * 1. 在 activity 自己的視窗上呼叫 `Window.setType(TYPE_APPLICATION_OVERLAY)`。毫無作用
 *    ——activity 的視窗型別是在它被 attach 時指派的。
 * 2. 把內容以 `TYPE_APPLICATION_OVERLAY` 加入 WindowManager。這是可行的：2026-09-04 實測，該 view
 *    以 1080x2209 完成佈局、已 attach，並把 P37 的文字畫在一切之上——直到 activity 停止為止；那一刻
 *    `dumpsys` 回報 `Surface: shown=false mLastHidden=true`，而該 view 仍是 VISIBLE 且 HAS_DRAWN，
 *    行程則被列為 `prev /LAST`。
 * 3. 同樣的做法，但改用 `applicationContext` 的 WindowManager，以防該視窗是在跟隨 activity 的
 *    token。結果完全相同。因此它跟隨的是**行程**狀態，不是 token。
 *
 * 而讓一個行程不進入 cached 狀態的東西，就是 foreground service。那就是本類別的全部用途；它自己
 * 不繪製任何東西。
 *
 * **那則通知不是選配，也不是裝飾。** foreground service 必須在數秒內發出一則通知，否則系統會終結
 * 該行程；而自 API 34 起，它還必須宣告 `foregroundServiceType`。因此一支在 Android 上浮動的 app
 * 會顯示一則通知。那是 Android 對這項功能的定價，而非此處所做的選擇——也正是為什麼 `.floating`
 * 昂貴到 `WindowLevel` 自己的文件要特別說明。
 */
class OverlayService : Service() {
    companion object {
        private const val CHANNEL_ID = "dev.swiftcrossui.overlay"
        private const val NOTIFICATION_ID = 1

        /** The view the service is currently holding, or null. */
        /** 本 service 當前持有的 view；若無則為 null。 */
        private var hosted: View? = null

        /**
         * Hands the view to the service and starts it.
         *
         * The view is passed through a static rather than an Intent extra
         * because a View is not parcelable and this is the same process either
         * way -- a service in its own process could not hold another process's
         * view at all.
         *
         * 透過 static 而非 Intent extra 把該 view 交給 service，因為 View 並非 parcelable，
         * 而兩者本來就在同一個行程中——一個位於自身行程中的 service，根本不可能持有另一個行程的 view。
         */
        @JvmStatic
        fun start(context: Context, view: View): Boolean {
            if (!Settings.canDrawOverlays(context)) {
                return false
            }
            hosted = view
            context.startForegroundService(Intent(context, OverlayService::class.java))
            return true
        }

        @JvmStatic
        fun stop(context: Context): View? {
            val view = hosted
            context.stopService(Intent(context, OverlayService::class.java))
            hosted = null
            return view
        }
    }

    private var attached: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Before the window, because the system gives a foreground service only
        // a few seconds to post its notification and adding a view can block.
        // 先於視窗，因為系統只給 foreground service 數秒鐘發出通知，而加入一個 view 可能會阻塞。
        startForeground(NOTIFICATION_ID, notification())

        val view = hosted ?: return START_NOT_STICKY
        if (attached === view) {
            return START_NOT_STICKY
        }

        (view.parent as? android.view.ViewGroup)?.removeView(view)

        val manager = getSystemService(WindowManager::class.java)
        manager.addView(
            view,
            WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                // NOT_TOUCH_MODAL so a touch outside this window still reaches
                // what is under it; without it the overlay would swallow every
                // touch on the screen, which is not what "in front" means.
                // 使用 NOT_TOUCH_MODAL，讓落在本視窗之外的觸控仍能抵達其下方的東西；少了它，這個
                // overlay 會吞掉螢幕上的每一次觸控，而那並不是「在前面」的意思。
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT,
            ),
        )
        attached = view
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        attached?.let { view ->
            getSystemService(WindowManager::class.java).removeView(view)
        }
        attached = null
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Floating window",
                    // LOW, so the notification does not make a sound every time
                    // an app floats. It cannot be hidden: a foreground service
                    // notification is what tells the user the app is running.
                    // 使用 LOW，使該通知不會在每次 app 浮動時發出聲音。它無法被隱藏：foreground
                    // service 的通知，正是用來告知使用者該 app 正在執行的東西。
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(applicationInfo.loadLabel(packageManager))
            .setContentText("Showing a floating window")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .build()
    }
}
