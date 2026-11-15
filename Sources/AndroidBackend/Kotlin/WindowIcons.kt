package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.util.WeakHashMap

/**
 * `windowIcon(_:)` on Android: the icon of the window's task in Recents, set through
 * `Activity.setTaskDescription` together with the label, which the title also sets.
 * Both go through [taskDescription], so neither a new title nor a new icon drops the
 * other. The PNG is decoded once per change; a null path restores the app's own icon.
 * The icons live here rather than on an AndroidBackendHelpers instance, because a
 * second window's activity applies its title through a new instance.
 *
 * Android 上的 `windowIcon(_:)`:視窗所屬 task 在「最近使用」中的圖示，經由 `Activity.setTaskDescription` 與標籤
 * 一起設定(標題也設定這個標籤)。兩者都經過 [taskDescription],所以新標題不會丟掉圖示，新圖示也不會丟掉標題。
 * PNG 在每次變更時解碼一次;null 路徑恢復 app 自己的圖示。圖示放在這裡而不是 AndroidBackendHelpers 的實例上，
 * 因為第二個視窗的 activity 是透過新的實例套用標題的。
 */
object ScuiWindowIcons {
    val byActivity = WeakHashMap<Activity, Bitmap>()
    val byToken = HashMap<String, String>()

    fun load(activity: Activity, path: String?) {
        val bitmap = path?.let { BitmapFactory.decodeFile(it) }
        if (bitmap == null) byActivity.remove(activity) else byActivity[activity] = bitmap
    }

    @Suppress("DEPRECATION")
    fun taskDescription(activity: Activity, label: String): ActivityManager.TaskDescription {
        // The Bitmap constructor: TaskDescription.Builder (API 33) takes an icon only as
        // a resource id, and the icon here is a file chosen at run time.
        // 用 Bitmap 版的建構子:TaskDescription.Builder(API 33)只接受資源 id 形式的圖示，而這裡的圖示是執行期選的檔案。
        val icon = byActivity[activity]
        return if (icon != null) ActivityManager.TaskDescription(label, icon)
        else ActivityManager.TaskDescription(label)
    }

    /**
     * The centre pixel (ARGB) of the icon the system holds for this activity's task, read
     * back from ActivityManager, or 0 when the task has no icon of its own. For P118.
     * 系統為這個 activity 的 task 所持有之圖示的中心像素(ARGB),讀自 ActivityManager;task 沒有自己的圖示時為 0。給 P118 用。
     */
    @Suppress("DEPRECATION")
    fun taskIconCentre(activity: Activity): Int {
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val task = manager.appTasks.firstOrNull { it.taskInfo.taskId == activity.taskId } ?: return 0
        val icon = task.taskInfo.taskDescription?.icon ?: return 0
        return icon.getPixel(icon.width / 2, icon.height / 2)
    }
}
