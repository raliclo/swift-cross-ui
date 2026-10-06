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

        val resolver = activity.contentResolver
        val observer =
            object : FileObserver(file, FileObserver.CLOSE_WRITE) {
                override fun onEvent(event: Int, path: String?) {
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
        return file.absolutePath
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
