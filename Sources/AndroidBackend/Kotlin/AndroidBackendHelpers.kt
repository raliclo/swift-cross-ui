package dev.swiftcrossui.androidbackend

import android.R
import android.app.Activity
import android.content.res.Configuration
import android.icu.util.TimeZone
import android.net.Uri
import android.os.Build
import android.util.TypedValue
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

    fun registerActivityResults(
        activity: FragmentActivity,
        filesCallback: FilesActivityCallback,
        folderCallback: FolderActivityCallback,
    ) {
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
        val resource =
            if (dark) R.color.system_neutral1_700 else R.color.system_neutral1_100
        button.backgroundTintList =
            android.content.res.ColorStateList.valueOf(button.context.getColor(resource))
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
}
