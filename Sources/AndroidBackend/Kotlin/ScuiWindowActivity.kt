package dev.swiftcrossui.androidbackend

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity

// A SwiftCrossUI window after the first, as an activity of its own.
//
// Android's unit of a window is an activity: on a phone each one is a task of
// its own in Recents, on a tablet or foldable it can sit beside the first in
// split screen (FLAG_ACTIVITY_LAUNCH_ADJACENT), and on a desktop-mode device it
// is a separate resizable window. AndroidBackend builds the window's content
// in Swift, leaves it in ScuiWindows under a token, and starts this activity
// with that token; the activity takes the content as its own. Added
// 2026-10-06 -- before, every createWindow returned a placeholder and a second
// window replaced the first's content.
//
// 第一個之後的 SwiftCrossUI 視窗，以獨立的 activity 呈現。Android 的「視窗」單位就是 activity:在手機上每個都是
// 「最近使用」裡的一個獨立工作，在平板或折疊機上可在分割畫面中與第一個並排(FLAG_ACTIVITY_LAUNCH_ADJACENT),在桌面
// 模式的裝置上則是可縮放的獨立視窗。AndroidBackend 在 Swift 中建好視窗內容，以 token 放進 ScuiWindows,再帶著
// 該 token 啟動此 activity;activity 把內容據為己有。2026-10-06 加入——之前每次 createWindow 都回傳佔位物件，
// 第二個視窗會取代第一個的內容。
class ScuiWindowActivity : AppCompatActivity() {
    private var token: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val token = intent.getStringExtra(EXTRA_TOKEN)
        val content = token?.let { ScuiWindows.contents[it] }
        if (token == null || content == null) {
            // Recreated by the system after the process died: the Swift side
            // that owned this window is gone, so there is nothing to show.
            // 行程結束後被系統重建：擁有此視窗的 Swift 端已不在，沒有東西可顯示。
            finish()
            return
        }
        this.token = token
        (content.parent as? ViewGroup)?.removeView(content)
        setContentView(content)
        ScuiWindows.activities[token] = this
        // The window's size is whatever this activity is given -- full screen,
        // half of a split, a free-form window -- and changes with it, so Swift
        // hears about every new size rather than computing one up front.
        // 視窗尺寸就是此 activity 被分配到的大小——全螢幕、分割的一半、自由視窗——並隨之改變，所以 Swift 會聽到每個
        // 新尺寸，而不是事先算一個。
        content.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) {
                ScuiWindows.onResized[token]?.call()
            }
        }
        ScuiWindows.titles[token]?.let { AndroidBackendHelpers().setWindowTitle(this, it) }
    }

    override fun onDestroy() {
        val token = token
        if (token != null && isFinishing) {
            ScuiWindows.activities.remove(token)
            ScuiWindows.contents.remove(token)
            ScuiWindows.titles.remove(token)
            ScuiWindows.onResized.remove(token)
            ScuiWindows.onClosed.remove(token)?.call()
        }
        super.onDestroy()
    }

    companion object {
        const val EXTRA_TOKEN = "scui_window_token"
    }
}

/** The windows after the first, by token. 第一個之後的視窗，以 token 為鍵。 */
object ScuiWindows {
    val contents = HashMap<String, View>()
    val titles = HashMap<String, String>()
    val activities = HashMap<String, ScuiWindowActivity>()
    val onClosed = HashMap<String, SwiftAction>()
    val onResized = HashMap<String, SwiftAction>()
}
