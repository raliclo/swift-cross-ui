package dev.swiftcrossui.androidbackend

import android.R
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.os.Environment
import android.os.FileObserver
import android.provider.DocumentsContract
import java.io.File
import android.icu.util.TimeZone
import android.net.Uri
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.view.WindowInsets
import android.widget.TextView
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import dev.swiftcrossui.androidbackend.activityresults.*

class AndroidBackendHelpers {
    companion object {
        private const val DEVICE_CLASS_DESKTOP: Short = 0
        private const val DEVICE_CLASS_PHONE: Short = 1
        private const val DEVICE_CLASS_TABLET: Short = 2
        private const val DEVICE_CLASS_TV: Short = 3
        private const val DEVICE_CLASS_WATCH: Short = 4
    }

    // In API 34 and earlier, the insets are accounted for by the system, and it's impossible to
    // render anything within them. resources.configuration has the correct size.
    // Starting in API 35, it is possible to render things in the insets, and the system bars are
    // transparent.
    fun getSafeWindowWidth(activity: Activity): Int {
        if (Build.VERSION.SDK_INT <= 34) return activity.resources.configuration.screenWidthDp

        val windowMetrics = activity.getWindowManager().getCurrentWindowMetrics()
        val displayMetrics = activity.resources.displayMetrics
        val insets =
            windowMetrics
                .getWindowInsets()
                .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars())
        // density is very frequently a fractional value like 1.5, so cast to int after division
        // instead of before
        return ((windowMetrics.getBounds().width() - insets.left - insets.right).toFloat() /
                displayMetrics.density)
            .toInt()
    }

    fun getSafeWindowHeight(activity: Activity): Int {
        if (Build.VERSION.SDK_INT <= 34) return activity.resources.configuration.screenHeightDp

        val windowMetrics = activity.getWindowManager().getCurrentWindowMetrics()
        val displayMetrics = activity.resources.displayMetrics
        val insets =
            windowMetrics
                .getWindowInsets()
                .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars())
        return ((windowMetrics.getBounds().height() - insets.top - insets.bottom).toFloat() /
                displayMetrics.density)
            .toInt()
    }

    fun getSafeAreaLeftInset(activity: Activity): Int {
        if (Build.VERSION.SDK_INT <= 34) return 0

        val windowMetrics = activity.getWindowManager().getCurrentWindowMetrics()
        val displayMetrics = activity.resources.displayMetrics
        val insets =
            windowMetrics
                .getWindowInsets()
                .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars())
        return (insets.left.toFloat() / displayMetrics.density).toInt()
    }

    fun getSafeAreaTopInset(activity: Activity): Int {
        if (Build.VERSION.SDK_INT <= 34) return 0

        val windowMetrics = activity.getWindowManager().getCurrentWindowMetrics()
        val displayMetrics = activity.resources.displayMetrics
        val insets =
            windowMetrics
                .getWindowInsets()
                .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars())
        return (insets.top.toFloat() / displayMetrics.density).toInt()
    }

    private var largeTextSize: Float? = null
    private var titleTextSize: Float? = null
    private var mediumTextSize: Float? = null
    private var smallTextSize: Float? = null

    private fun getFontSizeFromResource(activity: Activity, resId: Int): Float {
        val sizePixels = TextView(activity, null, 0, resId).paint.textSize
        val displayMetrics = activity.resources.displayMetrics
        if (Build.VERSION.SDK_INT >= 34) {
            return TypedValue.deriveDimension(
                TypedValue.COMPLEX_UNIT_SP,
                sizePixels,
                displayMetrics,
            )
        } else {
            return sizePixels / displayMetrics.scaledDensity
        }
    }

    fun clearTextSizeCache() {
        largeTextSize = null
        titleTextSize = null
        mediumTextSize = null
        smallTextSize = null
    }

    fun getLargeTextSize(activity: Activity): Float {
        val size =
            largeTextSize
                ?: getFontSizeFromResource(activity, R.style.TextAppearance_DeviceDefault_Large)
        largeTextSize = size
        return size
    }

    fun getTitleTextSize(activity: Activity): Float {
        val size =
            titleTextSize
                ?: getFontSizeFromResource(
                    activity,
                    R.style.TextAppearance_DeviceDefault_WindowTitle,
                )
        titleTextSize = size
        return size
    }

    fun getMediumTextSize(activity: Activity): Float {
        val size =
            mediumTextSize
                ?: getFontSizeFromResource(activity, R.style.TextAppearance_DeviceDefault_Medium)
        mediumTextSize = size
        return size
    }

    // RootScrollHost.originDisplacement for the host `view` sits in, or 0,0 when
    // it is in none. 取 `view` 所在宿主的 RootScrollHost.originDisplacement,沒有宿主時為 0,0。
    fun rootScrollDisplacement(view: View): IntArray {
        var parent = view.parent
        while (parent != null) {
            if (parent is RootScrollHost) return parent.originDisplacement()
            parent = parent.parent
        }
        return intArrayOf(0, 0)
    }

    // RootScrollHost.reveal for the host `view` sits in, or 0,0 when it is in
    // none. 取 `view` 所在宿主的 RootScrollHost.reveal,沒有宿主時為 0,0。
    fun rootScrollReveal(view: View, x: Int, y: Int): IntArray {
        var parent = view.parent
        while (parent != null) {
            if (parent is RootScrollHost) return parent.reveal(x, y)
            parent = parent.parent
        }
        return intArrayOf(0, 0)
    }

    // A ToggleButton (`.toggleStyle(.button)`, the default style) shows on and
    // off only by the colour of a thin underline, and on the API 36 emulator the
    // two looked the same: P12's "Opposite states: they must look different"
    // failed, and P2/P15's toggles gave no sign of being on. The body is tinted
    // instead -- the accent when checked, the theme's button colour when not --
    // as UIKit fills a selected button-style toggle.
    // ToggleButton(`.toggleStyle(.button)`,即預設樣式)只靠一條細底線的顏色表示開關，在 API 36 emulator 上兩者
    // 看起來一樣:P12 的「相反狀態必須看起來不同」不成立,P2/P15 的開關看不出是開的。改為替按鈕本體上色——
    // 開時 accent,關時主題的按鈕色——如同 UIKit 把選取的按鈕樣式開關填滿。
    fun styleToggleButton(button: android.widget.ToggleButton) {
        val context = button.context
        val primary = themeColorOf(context, android.R.attr.colorPrimary)
        val density = context.resources.displayMetrics.density
        // As UIKit draws a button-style toggle (user, 2026-10-09: Android lines
        // up with iOS): off is a borderless label in the tint, on is the tint
        // filled behind a white label. The earlier tinted grey Material button
        // read as "a grey button, slightly purple" beside iOS's blue fill (P12).
        // 與 UIKit 畫按鈕樣式開關的方式相同(使用者,2026-10-09:Android 對齊 iOS):關是強調色的無框標籤，開是強調色填滿、
        // 白色標籤。先前那個上了色的灰色 Material 按鈕，在 iOS 的藍色填滿旁邊讀起來只是「偏紫的灰按鈕」(P12)。
        val filled = android.graphics.drawable.GradientDrawable()
        filled.cornerRadius = 8 * density
        filled.setColor(primary)
        val background = android.graphics.drawable.StateListDrawable()
        background.addState(intArrayOf(android.R.attr.state_checked), filled)
        background.addState(intArrayOf(), android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
        button.background = background
        button.backgroundTintList = null
        button.stateListAnimator = null
        button.elevation = 0f
        val pad = (8 * density).toInt()
        button.setPadding(pad, pad / 2, pad, pad / 2)
        button.minHeight = 0
        button.minimumHeight = 0
        button.minWidth = 0
        button.minimumWidth = 0
    }

    // The label colours for a button-style toggle: white on the filled (checked)
    // state, the tint otherwise, both at 38% when disabled. Called after the text
    // style, which sets one solid colour. 按鈕樣式開關的標籤顏色：填滿(開)時白色，其他時候強調色，停用時兩者都 38%。
    // 在文字樣式之後呼叫，因為文字樣式只設單一顏色。
    fun applyToggleButtonTextColors(button: android.widget.ToggleButton, enabled: Boolean) {
        val primary = themeColorOf(button.context, android.R.attr.colorPrimary)
        fun fade(c: Int) = if (enabled) c else (c and 0x00FFFFFF) or 0x61000000
        button.setTextColor(
            android.content.res.ColorStateList(
                arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                intArrayOf(fade(android.graphics.Color.WHITE), fade(primary))
            )
        )
    }

    // A Switch coloured from the SwiftCrossUI scheme rather than the activity
    // theme: on is colorPrimary (track) with a white thumb; off is the current
    // foreground at 30% (track) and 70% (thumb). Under preferredColorScheme(.dark)
    // the light theme's off track was invisible on black and only a grey dot
    // showed, where iOS draws a dark grey track (P15-DARK, 2026-10-09).
    // 依 SwiftCrossUI 的配色而非 activity 主題替 Switch 上色：開時軌道是 colorPrimary、滑塊白色；關時軌道是目前前景色的 30%、
    // 滑塊 70%。在 preferredColorScheme(.dark) 下，淺色主題的關閉軌道在黑底上看不見，只剩一個灰點，iOS 則畫出深灰的軌道。
    fun styleSwitch(switchView: android.widget.CompoundButton, foreground: Int, enabled: Boolean) {
        if (switchView !is android.widget.Switch) return
        val key = "$foreground/$enabled"
        if (switchStyles[switchView] == key) return
        switchStyles[switchView] = key
        val primary = themeColorOf(switchView.context, android.R.attr.colorPrimary)
        val density = switchView.context.resources.displayMetrics.density
        fun alpha(c: Int, a: Int) = (c and 0x00FFFFFF) or (a shl 24)
        val fade = if (enabled) 1f else 0.38f
        fun f(c: Int) = alpha(c, (((c ushr 24) and 0xFF) * fade).toInt())
        val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
        // Drawn shapes rather than tints: the framework track drawable carries
        // its own transparency, so a tinted checked track came out pale and the
        // white thumb on it read as "off" (P15), and the off track at 30% was
        // still barely there on black (P15-DARK). A pill and a white disc, as
        // iOS draws them; the off track is the foreground at 18% -- (46,46,46)
        // on black against iOS's (57,57,61).
        // 以畫出的形狀而非 tint:框架的軌道圖本身帶透明度，所以上色後的開啟軌道很淡，上面的白色滑塊讀起來像「關」(P15),
        // 而 30% 的關閉軌道在黑底上仍幾乎看不見(P15-DARK)。改成與 iOS 相同的膠囊與白色圓盤;關閉軌道是前景色的 18%。
        val track = android.graphics.drawable.GradientDrawable()
        track.cornerRadius = 16 * density
        track.setSize((52 * density).toInt(), (32 * density).toInt())
        track.color = android.content.res.ColorStateList(
            states, intArrayOf(f(primary), f(alpha(foreground, 0x2E)))
        )
        val disc = android.graphics.drawable.GradientDrawable()
        disc.shape = android.graphics.drawable.GradientDrawable.OVAL
        disc.setSize((24 * density).toInt(), (24 * density).toInt())
        // A faint ring, so the white disc still has an edge on a white page --
        // iOS gives its thumb a shadow for the same reason. 一圈很淡的邊，讓白色圓盤在白色頁面上仍看得出邊緣——iOS 為同樣理由給滑塊陰影。
        disc.setStroke(maxOf(1, (0.5f * density).toInt()), 0x33000000)
        disc.setColor(f(android.graphics.Color.WHITE))
        // 4 dp round the 24 dp disc: the thumb stays 32 dp for the Switch's width
        // arithmetic, while the disc sits inside the 28 dp track the Switch
        // draws. With a 28 dp disc it overhung the track and, white on a light
        // page, the checked switch looked bitten off (P15, measured: track
        // 136x74 px, thumb 83x84 px past its right end).
        // 24 dp 圓盤外留 4 dp:滑塊仍是 32 dp 供 Switch 計算寬度，圓盤則落在 Switch 畫出的 28 dp 軌道之內。用 28 dp 圓盤時它
        // 超出軌道，在淺色頁面上白色的部分讓開啟的開關看起來像被咬掉一塊(P15 實測：軌道 136x74 px,滑塊 83x84 px 超出右端)。
        val inset = (4 * density).toInt()
        switchView.thumbTintList = null
        switchView.trackTintList = null
        switchView.thumbDrawable = android.graphics.drawable.InsetDrawable(disc, inset)
        switchView.trackDrawable = track
        switchView.switchMinWidth = (52 * density).toInt()
    }

    private val switchStyles = java.util.WeakHashMap<android.view.View, String>()

    private fun themeColorOf(context: android.content.Context, attr: Int): Int {
        val value = TypedValue()
        if (!context.theme.resolveAttribute(attr, value, true)) return 0
        return if (value.resourceId != 0) context.getColor(value.resourceId) else value.data
    }

    // .listStyle(.sidebar) on a ListView, drawn as a Material navigation drawer:
    // the theme's floating-surface background, no dividers, and a pill-shaped
    // selection inset from the edges, tinted with colorControlHighlight. Off
    // restores what createSelectableListView set: no background, the theme's
    // listDivider, the flat grey selector.
    // ListView 上的 .listStyle(.sidebar),畫成 Material 的 navigation drawer:主題的浮動表面背景、沒有分隔線、
    // 內縮的膠囊形選取(colorControlHighlight)。關閉時還原 createSelectableListView 所設的樣子。
    fun setListSidebar(listView: android.widget.ListView, sidebar: Boolean) {
        val context = listView.context
        fun themeColor(attr: Int): Int {
            val value = TypedValue()
            if (!context.theme.resolveAttribute(attr, value, true)) return 0
            return if (value.resourceId != 0) context.getColor(value.resourceId) else value.data
        }
        if (sidebar) {
            val density = context.resources.displayMetrics.density
            // The floating surface with the highlight laid over it, so the drawer
            // reads as a panel: on the API 36 emulator colorBackgroundFloating
            // alone equals the window background (P83, 2026-10-08).
            // 浮動表面再疊上 highlight,讓抽屜看得出是一塊面板:API 36 emulator 上單用 colorBackgroundFloating
            // 與視窗背景相同(P83,2026-10-08)。
            listView.background = android.graphics.drawable.LayerDrawable(
                arrayOf(
                    android.graphics.drawable.ColorDrawable(themeColor(android.R.attr.colorBackgroundFloating)),
                    android.graphics.drawable.ColorDrawable(themeColor(android.R.attr.colorControlHighlight))
                )
            )
            listView.divider = null
            listView.dividerHeight = 0
            val pill = android.graphics.drawable.GradientDrawable()
            pill.cornerRadius = 28 * density
            pill.setColor(themeColor(android.R.attr.colorControlHighlight))
            // An InsetDrawable reports its insets as padding, and AbsListView
            // adds a selector's padding to the list padding it lays rows out
            // in: every row moved 8 dp right and overflowed the right edge, so
            // the pill's right inset was clipped away (P83, measured 2026-10-09:
            // panel 561..1033 px, pill 603..1033). The insets stay in the
            // drawing; the padding is reported as none.
            // InsetDrawable 會把 inset 當成 padding 回報，而 AbsListView 把 selector 的 padding 加進排列各列的
            // list padding:每一列右移 8 dp 並超出右緣，膠囊的右側內縮被裁掉(P83,2026-10-09 量測：面板 561..1033 px,
            // 膠囊 603..1033)。inset 仍留在繪製中，padding 則回報為零。
            listView.selector = object : android.graphics.drawable.InsetDrawable(
                pill, (8 * density).toInt(), (2 * density).toInt(),
                (8 * density).toInt(), (2 * density).toInt()
            ) {
                override fun getPadding(padding: android.graphics.Rect): Boolean {
                    padding.set(0, 0, 0, 0)
                    return false
                }
            }
            // The selected row: a pill in the accent at a quarter strength, the
            // drawer's active indicator. 被選取的列：四分之一強度的 accent 膠囊，即抽屜的 active indicator。
            val accent = themeColor(android.R.attr.colorAccent)
            (listView.adapter as? dev.swiftcrossui.androidbackend.lists.CustomListAdapter)
                ?.setSidebarStyle(true, (accent and 0x00FFFFFF) or 0x40000000, density)
            (listView.adapter as? dev.swiftcrossui.androidbackend.lists.CustomListAdapter)
                ?.setRowBackground(0)
        } else {
            listView.background = null
            // Each row on the theme's window background, as UIKit draws a List's
            // cells on the system background while the table itself stays
            // clear: a transparent row put its default black text straight onto
            // whatever the app painted behind the list, and P3's lists on
            // `.background(Color.black)` showed no rows at all on Android while
            // iOS showed white cells (2026-10-09). Rows, not the ListView: the
            // empty space under the last row stays the app's, as on iOS.
            // 每一列畫在主題的視窗背景上，如同 UIKit 把 List 的 cell 畫在系統背景上、表格本身維持透明：透明的列會把預設黑字
            // 直接畫在 app 畫在清單後面的東西上,P3 在 `.background(Color.black)` 上的清單在 Android 一列都看不到，iOS 則是
            // 白色 cell(2026-10-09)。加在列上而不是 ListView:最後一列下方的空白仍屬於 app,與 iOS 相同。
            (listView.adapter as? dev.swiftcrossui.androidbackend.lists.CustomListAdapter)
                ?.setRowBackground(themeColor(android.R.attr.colorBackground))
            val attrs = context.obtainStyledAttributes(intArrayOf(android.R.attr.listDivider))
            listView.divider = attrs.getDrawable(0)
            attrs.recycle()
            listView.selector = android.graphics.drawable.ColorDrawable(0x32a1a1a1)
            (listView.adapter as? dev.swiftcrossui.androidbackend.lists.CustomListAdapter)
                ?.setSidebarStyle(false, 0, 1f)
        }
    }

    // The theme's colorError: the colour Material gives a destructive action, and
    // so the label colour of a ButtonRole.destructive button. 0 when the theme
    // defines none, which the Swift side reports rather than guessing a red.
    // 主題的 colorError:Material 給危險動作的顏色，也就是 ButtonRole.destructive 按鈕的標籤顏色。主題沒有定義時
    // 回傳 0,由 Swift 端回報，而不是猜一個紅色。
    fun getErrorColor(activity: Activity): Int {
        val value = TypedValue()
        if (!activity.theme.resolveAttribute(android.R.attr.colorError, value, true)) return 0
        return if (value.resourceId != 0) activity.getColor(value.resourceId) else value.data
    }

    // The theme's colorPrimary: what a Material text button's label is drawn in,
    // and so the label colour of a borderless button -- Android's counterpart
    // of the blue UIKit gives one. 0 when the theme defines none.
    // 主題的 colorPrimary:Material 文字按鈕的標籤顏色，也就是無框按鈕的標籤顏色——對應 UIKit 給的藍色。主題沒有定義時為 0。
    fun getPrimaryColor(activity: Activity): Int {
        val value = TypedValue()
        if (!activity.theme.resolveAttribute(android.R.attr.colorPrimary, value, true)) return 0
        return if (value.resourceId != 0) activity.getColor(value.resourceId) else value.data
    }

    fun getSmallTextSize(activity: Activity): Float {
        val size =
            smallTextSize
                ?: getFontSizeFromResource(activity, R.style.TextAppearance_DeviceDefault_Small)
        smallTextSize = size
        return size
    }

    fun isNightMode(activity: Activity): Boolean {
        var uiModeNight =
            activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK

        if (uiModeNight == Configuration.UI_MODE_NIGHT_UNDEFINED) {
            uiModeNight =
                activity.applicationContext.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK
        }

        return uiModeNight == Configuration.UI_MODE_NIGHT_YES
    }

    fun getDeviceClass(activity: Activity): Short {
        // Code from the official Android compatibility test suite.
        // https://stackoverflow.com/a/69564916
        val pm = activity.packageManager
        if (
            pm.hasSystemFeature("org.chromium.arc") ||
                pm.hasSystemFeature("org.chromium.arc.device_management")
        )
            return DEVICE_CLASS_DESKTOP

        val configuration = activity.resources.configuration
        val uiModeType = configuration.uiMode and Configuration.UI_MODE_TYPE_MASK

        return when (uiModeType) {
            Configuration.UI_MODE_TYPE_CAR,
            Configuration.UI_MODE_TYPE_VR_HEADSET -> DEVICE_CLASS_TABLET

            Configuration.UI_MODE_TYPE_TELEVISION -> DEVICE_CLASS_TV

            Configuration.UI_MODE_TYPE_WATCH -> DEVICE_CLASS_WATCH

            else -> {
                val sw = configuration.smallestScreenWidthDp

                val isTablet =
                    if (sw == Configuration.SMALLEST_SCREEN_WIDTH_DP_UNDEFINED)
                        configuration.isLayoutSizeAtLeast(Configuration.SCREENLAYOUT_SIZE_XLARGE)
                    else sw >= 600

                if (isTablet) DEVICE_CLASS_TABLET else DEVICE_CLASS_PHONE
            }
        }
    }

    /**
     * The window title: the activity's title, which accessibility services
     * announce, and the task's label in Recents, which is where a user sees it.
     */
    fun setWindowTitle(activity: Activity, title: String) {
        activity.title = title
        val description =
            if (Build.VERSION.SDK_INT >= 33) {
                android.app.ActivityManager.TaskDescription.Builder().setLabel(title).build()
            } else {
                @Suppress("DEPRECATION")
                android.app.ActivityManager.TaskDescription(title)
            }
        activity.setTaskDescription(description)
    }

    /** Opens a window after the first as a ScuiWindowActivity; see that file. */
    fun openWindow(
        from: Activity,
        token: String,
        title: String,
        content: View,
        onClosed: SwiftAction,
        onResized: SwiftAction,
    ) {
        ScuiWindows.contents[token] = content
        ScuiWindows.titles[token] = title
        ScuiWindows.onClosed[token] = onClosed
        ScuiWindows.onResized[token] = onResized
        val intent =
            Intent(from, ScuiWindowActivity::class.java)
                .putExtra(ScuiWindowActivity.EXTRA_TOKEN, token)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_DOCUMENT or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT
                )
        from.startActivity(intent)
    }

    fun closeWindow(token: String) {
        ScuiWindows.activities[token]?.finish()
    }

    /** The window's activity once it exists, else null. */
    fun windowActivity(token: String): Activity? = ScuiWindows.activities[token]

    fun setTitleOfWindow(token: String, title: String) {
        ScuiWindows.titles[token] = title
        ScuiWindows.activities[token]?.let { setWindowTitle(it, title) }
    }

    /** The URL an intent carries (`am start -d`, a tapped link), or null. */
    fun getIntentDataString(intent: Intent?): String? = intent?.dataString

    fun getTimeZoneIdentifier(): String? {
        val tz = TimeZone.getDefault()

        // Keep the helper compatible with the Android API used by the current
        // Swift Android SDK. Android 16 adds getIanaID, but compiling against an
        // older SDK cannot resolve that symbol even when guarded by SDK_INT.
        // 使用目前 Swift Android SDK 支援的 API，確保相容性。Android 16 雖新增
        // getIanaID，但即使以 SDK_INT 保護，舊版 compile SDK 仍無法解析該符號。
        return TimeZone.getCanonicalID(tz.getID())
    }

    private lateinit var filesLauncher: ActivityResultLauncher<FilesActivityContract.Options>
    private lateinit var folderLauncher: ActivityResultLauncher<Uri?>
    private var filesResult: FilesActivityCallback? = null
    private var folderResult: FolderActivityCallback? = null
    private var saveResult: FolderActivityCallback? = null

    // A dialog asked for from a window after the first starts from THAT
    // window's activity, so DocumentsUI returns to it rather than bringing the
    // first window's task to the front. The launchers above were registered on
    // the first activity before it started, which is the only time
    // registerForActivityResult allows; a later window registers one launcher
    // on its own registry for this one request and unregisters it with the
    // result. 2026-10-07.
    //
    // 由第一個之後的視窗要求的對話框，從**該**視窗的 activity 啟動，讓 DocumentsUI 回到它，而不是把第一個
    // 視窗的工作帶到前面。上面的 launcher 是在第一個 activity 啟動前註冊的——registerForActivityResult 只允許
    // 那個時機；之後的視窗則在自己的 registry 上為這一次要求註冊一個 launcher,拿到結果就註銷。2026-10-07。
    private fun <I, O> launchOnce(
        activity: ScuiWindowActivity,
        contract: androidx.activity.result.contract.ActivityResultContract<I, O>,
        callback: androidx.activity.result.ActivityResultCallback<O>,
        input: I,
    ) {
        var launcher: ActivityResultLauncher<I>? = null
        launcher =
            activity.activityResultRegistry.register("scui-${System.nanoTime()}", contract) { result ->
                callback.onActivityResult(result)
                launcher?.unregister()
            }
        launcher.launch(input)
    }

    fun launchFilesActivityFrom(activity: Activity?, options: FilesActivityContract.Options) {
        val window = activity as? ScuiWindowActivity
        val callback = filesResult
        if (window == null || callback == null) return launchFilesActivity(options)
        launchOnce(window, FilesActivityContract(), callback, options)
    }

    fun launchFolderActivityFrom(activity: Activity?, urlString: String?) {
        val window = activity as? ScuiWindowActivity
        val callback = folderResult
        if (window == null || callback == null) return launchFolderActivity(urlString)
        launchOnce(
            window, ActivityResultContracts.OpenDocumentTree(), callback,
            urlString?.let { Uri.parse(it) },
        )
    }

    fun launchSaveActivityFrom(activity: Activity?, defaultName: String) {
        val window = activity as? ScuiWindowActivity
        val callback = saveResult
        if (window == null || callback == null) return launchSaveActivity(defaultName)
        launchOnce(window, ActivityResultContracts.CreateDocument("*/*"), callback, defaultName)
    }

    fun registerActivityResults(
        activity: FragmentActivity,
        filesCallback: FilesActivityCallback,
        folderCallback: FolderActivityCallback,
    ) {
        filesResult = filesCallback
        folderResult = folderCallback
        filesLauncher = activity.registerForActivityResult(FilesActivityContract(), filesCallback)

        folderLauncher =
            activity.registerForActivityResult(
                ActivityResultContracts.OpenDocumentTree(),
                folderCallback,
            )
    }

    fun launchFilesActivity(options: FilesActivityContract.Options) {
        filesLauncher.launch(options)
    }

    // Delegates to the HitTesting object. An instance method here because that
    // is how every other Swift -> Kotlin call in this backend is bound, and a
    // second binding style would be a second thing to get wrong.
    //
    // 委派給 HitTesting 物件。此處使用實例方法，因為本 backend 中每一個 Swift -> Kotlin 的呼叫
    // 都是這樣綁定的；多一種綁定風格就是多一件會出錯的事。
    // The window's own background, which is the one surface SwiftCrossUI does
    // not paint. Everything the framework draws resolves through
    // `environment.colorScheme`, so a dark request already reaches every colour
    // in the view tree -- and then sits on a decor view that the Activity's
    // theme painted white, which is what P15 measured: the words changed and
    // the mean luminance of the page did not.
    //
    // `background_dark` and `background_light` rather than literals, because
    // these are the platform's own answer to "what colour is a window in this
    // scheme" and a hard-coded 0xFF000000 would be this backend inventing one.
    //
    // 視窗自身的背景，也是 SwiftCrossUI 唯一不會繪製的表面。框架所畫的一切都經由
    // `environment.colorScheme` 解析，因此一個 dark 請求其實早已抵達 view tree 中的每一個顏色
    // ——然後坐落在一個被 Activity 主題塗成白色的 decor view 上，而那正是 P15 所量到的：文字變了，
    // 頁面的平均亮度沒變。
    //
    // 使用 `background_dark` 與 `background_light` 而非字面值，因為它們是平台自己對「在這個配色下
    // 視窗是什麼顏色」的回答，而寫死 0xFF000000 等於由本 backend 自行發明一個。
    // A button's background is a drawable from the Activity's theme, and the
    // theme does not know the app asked for a colour scheme. SwiftCrossUI sets
    // the label colour from the environment, so making dark mode work turned
    // P15's three scheme buttons into white text on the theme's light grey --
    // the labels followed the request and the surface under them did not.
    //
    // Tinted rather than replaced, so the button keeps the ripple, the pressed
    // state and the rounded shape the platform drew; only the colour of that
    // drawable changes.
    //
    // `system_neutral1_*` is the platform's own neutral ramp, public since API
    // 31 and this project's `min_sdk` is 31. The first attempt used
    // `btn_default_material_dark`, which is what the framework's own button
    // drawable references -- and it does not compile, because it is a private
    // framework resource. It is named here so the next person does not spend
    // the same build finding that out.
    //
    // 按鈕的背景是來自 Activity 主題的 drawable，而該主題並不知道 app 要求了某個配色。SwiftCrossUI
    // 會依 environment 設定標籤顏色，因此「讓深色模式生效」這件事，把 P15 的三顆配色按鈕變成了
    // 「主題淺灰底上的白字」——標籤跟隨了請求，而它們底下的表面沒有。
    //
    // 採用 tint 而非替換，使按鈕保留平台所繪製的漣漪效果、按下狀態與圓角形狀；只有該 drawable 的
    // 顏色改變。
    //
    // `system_neutral1_*` 是平台自己的中性色階，自 API 31 起為公開資源，而本專案的 `min_sdk`
    // 即為 31。第一次嘗試用的是 `btn_default_material_dark`——那正是框架自身按鈕 drawable 所引用的
    // 資源——而它無法編譯，因為那是框架的私有資源。此處寫下它的名字，以免下一個人再花一次建置去
    // 發現這件事。
    fun setButtonColorScheme(button: android.widget.Button, dark: Boolean) {
        val resource = if (dark) R.color.system_neutral1_700 else R.color.system_neutral1_100
        button.backgroundTintList =
            android.content.res.ColorStateList.valueOf(button.context.getColor(resource))
    }

    // `.floating` on Android, and the answer is not a flag on the activity's
    // window -- it is a different kind of window. `TYPE_APPLICATION_OVERLAY`
    // is what "above other applications" means here, and it is gated on
    // SYSTEM_ALERT_WINDOW, a permission the user grants in Settings rather than
    // one an app can declare into existence.
    //
    // Returns whether the request took, so `supportedWindowLevels` can tell the
    // truth instead of the app finding out by looking.
    //
    // Android 上的 `.floating`，而它的答案不是在 activity 的視窗上設一個旗標——它是一種不同的視窗。
    // 「位於其他應用程式之上」在此處的意思就是 `TYPE_APPLICATION_OVERLAY`，而它受
    // SYSTEM_ALERT_WINDOW 管制——那是一個由使用者在「設定」中授予的權限，不是 app 可以靠宣告就
    // 取得的東西。
    //
    // 回傳該請求是否生效，好讓 `supportedWindowLevels` 說實話，而不是讓 app 靠肉眼去發現。

    /// Whether the user has granted the overlay permission.
    ///
    /// Read once at start-up rather than at each call, and the answer decides
    /// whether `supportedWindowLevels` offers `.floating` at all. Revoking it
    /// while the app runs is not tracked: `setWindowFloating` returns false in
    /// that case and the backend logs it.
    ///
    /// 使用者是否已授予 overlay 權限。
    ///
    /// 在啟動時讀取一次，而非每次呼叫時讀取，而其答案決定 `supportedWindowLevels` 是否提供
    /// `.floating`。app 執行期間該權限被撤銷的情況不追蹤：那時 `setWindowFloating` 會回傳 false，
    /// 而 backend 會記錄下來。
    fun canFloat(activity: Activity): Boolean {
        return android.provider.Settings.canDrawOverlays(activity)
    }

    // Handing the content to `OverlayService`, which is what keeps it on
    // screen; that file records the three experiments that led here.
    //
    // 把內容交給 `OverlayService`——那才是讓它留在畫面上的東西；該檔記錄了走到這一步的三次實驗。
    fun setWindowFloating(activity: Activity, floating: Boolean): Boolean {
        if (!floating) {
            val returned = OverlayService.stop(activity) ?: return true
            (returned.parent as? android.view.ViewGroup)?.removeView(returned)
            activity.setContentView(returned)
            return true
        }

        val content =
            activity.findViewById<android.view.ViewGroup>(android.R.id.content) ?: return false
        val child = content.getChildAt(0) ?: return false
        return OverlayService.start(activity, child)
    }

    fun setWindowBackground(activity: Activity, dark: Boolean) {
        val resource = if (dark) R.color.background_dark else R.color.background_light
        activity.window?.decorView?.setBackgroundColor(activity.getColor(resource))
    }

    fun setHitTesting(view: android.view.View, allowsHitTesting: Boolean) {
        HitTesting.setHitTesting(view, allowsHitTesting)
    }

    fun launchFolderActivity(urlString: String?) {
        folderLauncher.launch(urlString?.let { Uri.parse(it) })
    }

    private var saveLauncher: ActivityResultLauncher<String>? = null

    // Registered separately from the other two so their signature does not
    // change; it has to happen at the same point, before the activity starts,
    // which is where AndroidBackend calls it.
    //
    // 與另外兩個分開註冊，以免改動它們的簽章；它必須在同一個時間點、activity 開始之前完成，而
    // AndroidBackend 正是在那裡呼叫它。
    fun registerSaveResult(activity: FragmentActivity, callback: FolderActivityCallback) {
        saveResult = callback
        saveLauncher =
            activity.registerForActivityResult(
                ActivityResultContracts.CreateDocument("*/*"),
                callback,
            )
    }

    fun launchSaveActivity(defaultName: String) {
        saveLauncher?.launch(defaultName)
    }

    private val saveMirrors = mutableListOf<FileObserver>()

    // A path a plain write can use, for a document the save dialog created.
    //
    // CREATE_DOCUMENT answers with a content:// URI, and a Swift caller writes
    // a destination with FileManager or Data.write(to:), which cannot open one.
    // So the caller gets a file in this app's cache, and every time that file
    // is closed after writing, its bytes are copied into the document through
    // the content resolver -- the one route the platform gives an app to a
    // document it did not create.
    //
    // Not /proc/self/fd/N for a descriptor opened on the URI, which was the
    // first version: measured on the API 36 emulator 2026-09-30 with P75, the
    // write failed with EACCES. Opening that link resolves back to the FUSE
    // path of a file DocumentsUI created, which this app may not open.
    //
    // 為存檔對話框建立的文件提供一個「一般寫入就能用」的路徑。CREATE_DOCUMENT 回傳的是 content://
    // URI，而 Swift 呼叫端用 FileManager 或 Data.write(to:) 寫入目的地，兩者都開不了它。因此呼叫端
    // 拿到的是本 app cache 中的一個檔案；每當該檔案在寫入後被關閉，它的位元組就經由 content resolver
    // 複製到該文件——那是平台給 app 通往「非自己建立的文件」的唯一途徑。第一版用的是「對該 URI 開啟的
    // descriptor 的 /proc/self/fd/N」：2026-09-30 以 P75 於 API 36 emulator 實測，寫入以 EACCES
    // 失敗。開啟那個連結會解析回 DocumentsUI 所建立之檔案的 FUSE 路徑，而本 app 不得開啟它。
    fun stagingPathForSave(activity: Activity, uriString: String, name: String): String? {
        val uri = Uri.parse(uriString)
        val folder = File(activity.cacheDir, "save-${System.nanoTime()}")
        if (!folder.mkdirs()) return null
        val file = File(folder, name.ifEmpty { "Untitled" })
        if (!file.createNewFile()) return null

        mirrorBack(activity, folder, file, uri)
        return file.absolutePath
    }

    // A path a plain read can use, for a document the open dialog returned.
    //
    // ACTION_OPEN_DOCUMENT answers with content:// URIs, and DocumentGroup reads
    // the chosen URL with Data(contentsOf:), which Foundation on Android cannot do
    // for one: measured on the API 36 emulator 2026-10-07 with P62, "could not open
    // document", NSURLErrorDomain -1002 "unsupported URL". So the document is
    // copied into a folder of its own in the cache, under its display name (so the
    // window title and the extension check read what the person chose), and the
    // same mirror as a save writes it back when the app saves over that file.
    // ACTION_OPEN_DOCUMENT grants write as well as read; the grants are made
    // persistable so the write-back still works after the picker's activity is
    // gone. A provider that grants read only still opens; its saves fail and log.
    //
    // 為開檔對話框回傳的文件提供一個「一般讀取就能用」的路徑。ACTION_OPEN_DOCUMENT 回傳 content:// URI,
    // 而 DocumentGroup 以 Data(contentsOf:) 讀取選到的 URL,Foundation 在 Android 上對它辦不到:2026-10-07
    // 以 P62 於 API 36 emulator 實測,「could not open document」,NSURLErrorDomain -1002「unsupported URL」。
    // 因此文件以其顯示名稱複製到 cache 中自己的資料夾(讓視窗標題與副檔名檢查讀到使用者選的名字),並由與存檔
    // 相同的鏡像在 app 存回那個檔案時寫回去。ACTION_OPEN_DOCUMENT 會同時授予讀與寫;這些授權被設為可持久，
    // 好讓選擇器的 activity 結束之後寫回仍然有效。只授予讀取的 provider 仍可開啟，其存檔會失敗並記錄。
    fun stagingPathForOpen(activity: Activity, uriString: String): String? {
        val uri = Uri.parse(uriString)
        val resolver = activity.contentResolver
        val name =
            resolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
                ?.takeIf { it.isNotEmpty() && !it.contains('/') }
                ?: (uri.lastPathSegment?.substringAfterLast('/')?.ifEmpty { null } ?: "Untitled")
        val folder = File(activity.cacheDir, "open-${System.nanoTime()}")
        if (!folder.mkdirs()) return null
        val file = File(folder, name)
        try {
            resolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { input.copyTo(it) }
            } ?: return null
        } catch (error: Exception) {
            android.util.Log.e("SwiftCrossUI", "could not read the opened document $uri", error)
            return null
        }

        val readWrite =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            resolver.takePersistableUriPermission(uri, readWrite)
        } catch (writeRefused: SecurityException) {
            try {
                resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (notPersistable: SecurityException) {
                // A provider without persistable grants still opened; the
                // session's grant covers a save made while the app runs.
                // 不支援可持久授權的 provider 仍已開啟;本次執行期間的授權涵蓋 app 執行中的存檔。
            }
        }

        // Read only when the document cannot be written: then the copy and its
        // folder are made read-only too, so a save fails in Swift (saveDocument
        // returns false and logs, as for a read-only file on a desktop) instead
        // of writing the copy, failing the write-back in logcat alone, and
        // reporting success.
        //
        // Probed by opening the document for append and closing it without a
        // byte written, not read from COLUMN_FLAGS. MediaDocumentsProvider
        // reported flags=4 (delete only, no FLAG_SUPPORTS_WRITE) for a text file
        // in Download, and a "wt" write-back to it succeeded all the same
        // (API 36 emulator, 2026-10-07) -- the flag would have made a writable
        // file read-only. "wa", because "w" may truncate on open.
        //
        // 文件無法寫入時以唯讀開啟：副本與其資料夾也設為唯讀，讓存檔在 Swift 端失敗(saveDocument 回傳 false
        // 並記錄，如同桌面上的唯讀檔),而不是寫進副本、回寫只在 logcat 失敗、卻回報成功。
        // 以「附加模式開啟、一個位元組都不寫就關閉」實際探測，而非讀 COLUMN_FLAGS。MediaDocumentsProvider 對
        // Download 中的文字檔回報 flags=4(只能刪除，沒有 FLAG_SUPPORTS_WRITE),而對它的 "wt" 回寫照樣成功
        // (API 36 emulator,2026-10-07)——依那個 flag 會把可寫的檔案變成唯讀。用 "wa",因為 "w" 可能在開啟時截斷。
        val writable =
            try {
                resolver.openFileDescriptor(uri, "wa")?.use { true } ?: false
            } catch (refused: Exception) {
                false
            }
        if (!writable) {
            file.setWritable(false, false)
            folder.setWritable(false, false)
            android.util.Log.i("SwiftCrossUI", "opened $uri read-only; saves to it will fail")
            return file.absolutePath
        }
        mirrorBack(activity, folder, file, uri)
        return file.absolutePath
    }

    // Copies `file` into the document at `uri` each time the app finishes writing it.
    //
    // 每當 app 寫完 `file`,就把它複製到 `uri` 所指的文件。
    private fun mirrorBack(activity: Activity, folder: File, file: File, uri: Uri) {
        val resolver = activity.contentResolver
        // The FOLDER is watched, for CLOSE_WRITE and MOVED_TO on this name: a
        // plain write closes the file, an atomic one (`Data.write(options:
        // .atomic)`, which DocumentGroup's saveDocument uses) renames a temporary
        // file over it, and a watch on the file alone would see only the first.
        // Measured 2026-10-07 on the API 36 emulator with P75 writing atomically:
        // the copy arrived either way, so Foundation did not rename there -- but
        // that is an implementation detail, and this covers both.
        // 監看的是**資料夾**,針對這個檔名的 CLOSE_WRITE 與 MOVED_TO:一般寫入會關閉檔案,atomic 寫入
        // (DocumentGroup 的 saveDocument 所用的 `Data.write(options: .atomic)`)會把暫存檔改名蓋過它，只監看
        // 檔案本身只會看到前者。2026-10-07 以 P75 在 API 36 emulator 上 atomic 寫入實測：兩種都複製成功，所以
        // Foundation 在那裡沒有改名——但那是實作細節，這裡兩者都涵蓋。
        val observer =
            object : FileObserver(folder, FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO) {
                override fun onEvent(event: Int, path: String?) {
                    if (path != file.name) return
                    try {
                        resolver.openOutputStream(uri, "wt")?.use { output ->
                            file.inputStream().use { it.copyTo(output) }
                        }
                    } catch (error: Exception) {
                        android.util.Log.e("SwiftCrossUI", "could not copy the save to $uri", error)
                    }
                }
            }
        observer.startWatching()
        saveMirrors.add(observer)
    }

    // Both return null on success and a sentence on failure, so the Swift side
    // can throw something a person can read instead of a bare `false`.
    //
    // 兩者成功時回傳 null，失敗時回傳一句話，讓 Swift 端能拋出人讀得懂的錯誤，而不是光禿禿的 `false`。

    fun openExternalUrl(activity: Activity, urlString: String): String? {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlString))
        return try {
            activity.startActivity(intent)
            null
        } catch (error: ActivityNotFoundException) {
            "no installed app handles $urlString"
        }
    }

    // Opens the system file manager (DocumentsUI) at the file's folder.
    //
    // DocumentsUI answers ACTION_VIEW on a directory document of the external
    // storage provider -- measured on the API 36 emulator 2026-09-30:
    // `am start -a android.intent.action.VIEW -t vnd.android.document/directory
    // -d content://com.android.externalstorage.documents/document/primary%3ADownload`
    // resumed com.android.documentsui.files.FilesActivity listing the file.
    //
    // A file in the app's private storage is refused with a reason, not
    // ignored: no system file manager can list it, because the platform's
    // sandbox keeps every other app -- DocumentsUI included -- out of it. The
    // same is true of Android/data since Android 11.
    //
    // 在檔案所在的資料夾開啟系統檔案管理員（DocumentsUI）。DocumentsUI 會回應 external storage
    // provider 上目錄文件的 ACTION_VIEW——2026-09-30 於 API 36 emulator 實測，上述指令使
    // FilesActivity 進入前景並列出該檔案。app 私有儲存區內的檔案會附上理由被拒絕，而不是被忽略：
    // 沒有任何系統檔案管理員能列出它，因為平台的沙箱把包括 DocumentsUI 在內的所有其他 app 擋在外面；
    // 自 Android 11 起 Android/data 亦同。
    fun revealFile(activity: Activity, path: String): String? {
        val file = File(path).absoluteFile
        val folder = (if (file.isDirectory) file else file.parentFile)
            ?: return "$path has no enclosing folder"
        val storageRoot = Environment.getExternalStorageDirectory().absolutePath
        val folderPath = folder.path.replaceFirst("/sdcard", storageRoot)
        val inShared =
            (folderPath == storageRoot || folderPath.startsWith("$storageRoot/")) &&
                !folderPath.startsWith("$storageRoot/Android/")
        if (!inShared) {
            return "$path is in storage private to an app, which no file manager can list; " +
                "reveal works for files under $storageRoot"
        }
        val relative = folderPath.removePrefix(storageRoot).trimStart('/')
        val uri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:$relative",
        )
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            activity.startActivity(intent)
            null
        } catch (error: ActivityNotFoundException) {
            "no file manager handles $uri"
        }
    }
}
