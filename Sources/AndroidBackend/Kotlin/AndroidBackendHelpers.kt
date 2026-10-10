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
    // For the action file's `taplabel`: where the first shown TextView (a Button is
    // one) with exactly this text is, as the middle of it on screen. Empty when
    // nothing shows it. The view may be past the screen's edge; the caller scrolls.
    // 供動作檔的 `taplabel` 使用：第一個顯示中、文字完全相同的 TextView(Button 也是)在哪裡，以它在螢幕上的中心表示。
    // 沒有 view 顯示它時為空。該 view 可能在螢幕邊緣之外；由呼叫端負責捲動。
    fun centreOfLabel(activity: Activity, label: String): IntArray {
        fun find(view: View): View? {
            if (view.visibility != View.VISIBLE) return null
            if (view is android.widget.TextView && view.text?.toString() == label) return view
            if (view is android.view.ViewGroup) {
                for (i in 0 until view.childCount) {
                    find(view.getChildAt(i))?.let { return it }
                }
            }
            return null
        }
        val found = find(activity.window.decorView) ?: return IntArray(0)
        val origin = IntArray(2)
        found.getLocationOnScreen(origin)
        return intArrayOf(origin[0] + found.width / 2, origin[1] + found.height / 2)
    }

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
        filled.cornerRadius = 6 * density
        filled.setColor(primary)
        val background = android.graphics.drawable.StateListDrawable()
        background.addState(intArrayOf(android.R.attr.state_checked), filled)
        background.addState(intArrayOf(), android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
        button.background = background
        button.backgroundTintList = null
        button.stateListAnimator = null
        button.elevation = 0f
        // No inset at the sides and 6 dp above and below, as UIButton(type: .system),
        // which ToggleWidget is: P21's "Enabled" sat 8 dp right of iOS's.
        // 左右不內縮、上下 6 dp,與 ToggleWidget 所用的 UIButton(type: .system) 相同:P21 的 "Enabled" 比 iOS 的右移了 8 dp。
        val pad = (6 * density).toInt()
        button.setPadding(0, pad, 0, pad)
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
        val density = switchView.context.resources.displayMetrics.density
        fun alpha(c: Int, a: Int) = (c and 0x00FFFFFF) or (a shl 24)
        val fade = if (enabled) 1f else 0.38f
        fun f(c: Int) = alpha(c, (((c ushr 24) and 0xFF) * fade).toInt())
        val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
        // UISwitch as iOS 26 draws it, measured on P21 (2026-10-10): a 63 x 28
        // track, systemGreen when on (#34C759, #30D158 dark) and (120,120,128)
        // at 44% when off -- 197 on white, about 52 on black -- with a 37 x 24
        // white capsule 2 pt inside either end. Until then this drew the older
        // 52 x 32 pill with a round thumb in colorPrimary.
        // iOS 26 所畫的 UISwitch,於 P21 量測(2026-10-10):63 x 28 的軌道，開啟時為 systemGreen(#34C759,深色
        // #30D158),關閉時為 44% 的 (120,120,128)——白底上 197、黑底上約 52——上面一個 37 x 24 的白色膠囊，距兩端各 2 pt。
        // 在此之前畫的是舊版 52 x 32、colorPrimary 的膠囊與圓形滑塊。
        val dark = android.graphics.Color.luminance(foreground) > 0.5f
        val green = if (dark) 0xFF30D158.toInt() else 0xFF34C759.toInt()
        val trackWidth = 63 * density
        val trackHeight = 28 * density
        val track = android.graphics.drawable.GradientDrawable()
        track.cornerRadius = trackHeight / 2
        track.setSize(trackWidth.toInt(), trackHeight.toInt())
        track.color = android.content.res.ColorStateList(
            states, intArrayOf(f(green), f(alpha(0xFF78787F.toInt(), 0x70)))
        )
        switchView.thumbTintList = null
        switchView.trackTintList = null
        switchView.thumbDrawable = SwitchCapsule(trackWidth, trackHeight, density, f(android.graphics.Color.WHITE))
        switchView.trackDrawable = track
        switchView.switchMinWidth = trackWidth.toInt()
        switchView.switchPadding = 0
    }

    // The thumb. A Switch is as wide as two thumbs, so this one claims half the
    // track -- keeping the switch 63 wide -- and draws the 37-wide capsule where
    // iOS has it for the position it is at: 2 pt in from the left when off, 2 pt
    // in from the right when on, and in proportion while it slides.
    // 滑塊。Switch 的寬度是兩個滑塊寬，所以這個滑塊只佔軌道的一半——讓開關維持 63 寬——並依所在位置把 37 寬的膠囊畫在
    // iOS 畫的地方：關閉時距左端 2 pt、開啟時距右端 2 pt,滑動途中按比例。
    private class SwitchCapsule(
        private val trackWidth: Float,
        private val trackHeight: Float,
        private val density: Float,
        color: Int,
    ) : android.graphics.drawable.Drawable() {
        private val fill = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
        }
        // A faint ring, so the white capsule still has an edge on a white page;
        // iOS gives it a shadow for the same reason. 一圈很淡的邊，讓白色膠囊在白色頁面上仍看得出邊緣;iOS 為同樣理由給它陰影。
        private val ring = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = 0x22000000
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 0.5f * density
        }

        override fun draw(canvas: android.graphics.Canvas) {
            val b = bounds
            val travel = trackWidth - b.width()
            val fraction = if (travel > 0) (b.left / travel).coerceIn(0f, 1f) else 0f
            val inset = 2 * density
            val width = 37 * density
            val height = 24 * density
            val left = inset + fraction * (trackWidth - 2 * inset - width)
            val top = b.exactCenterY() - height / 2
            val rect = android.graphics.RectF(left, top, left + width, top + height)
            canvas.drawRoundRect(rect, height / 2, height / 2, fill)
            canvas.drawRoundRect(rect, height / 2, height / 2, ring)
        }

        override fun getIntrinsicWidth() = (trackWidth / 2).toInt()

        override fun getIntrinsicHeight() = trackHeight.toInt()

        override fun setAlpha(alpha: Int) {
            fill.alpha = alpha
        }

        override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
            fill.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    private val switchStyles = java.util.WeakHashMap<android.view.View, String>()

    // `.checkbox` drawn as UIKitBackend's UIButtonCheckbox: a 30 pt square with
    // 10 pt corners, secondarySystemFill ((120,120,128) at 16%) when off and
    // systemBlue (#0088FF, #0091FF dark) with a checkmark in the foreground
    // colour when on, the whole control at 40% when disabled. The framework
    // CheckBox was Material's outlined box (P21, 2026-10-10).
    // `.checkbox` 畫成 UIKitBackend 的 UIButtonCheckbox:30 pt 見方、圓角 10 pt,關閉時為 secondarySystemFill(16% 的
    // (120,120,128)),開啟時為 systemBlue(#0088FF,深色 #0091FF)加上前景色的勾號，停用時整個控制項 40%。框架的
    // CheckBox 是 Material 的外框方塊(P21,2026-10-10)。
    fun styleCheckbox(checkBox: android.widget.CompoundButton, foreground: Int, enabled: Boolean) {
        checkBox.alpha = if (enabled) 1f else 0.4f
        val key = "$foreground"
        if (checkboxStyles[checkBox] == key) return
        checkboxStyles[checkBox] = key
        val density = checkBox.context.resources.displayMetrics.density
        val dark = android.graphics.Color.luminance(foreground) > 0.5f
        val blue = if (dark) 0xFF0091FF.toInt() else 0xFF0088FF.toInt()
        val faces = android.graphics.drawable.StateListDrawable()
        faces.addState(intArrayOf(android.R.attr.state_checked), CheckboxFace(blue, foreground, density))
        faces.addState(intArrayOf(), CheckboxFace(0x2978787F, 0, density))
        checkBox.buttonTintList = null
        checkBox.buttonDrawable = faces
        checkBox.background = null
        checkBox.setPadding(0, 0, 0, 0)
        // 30 pt tall, the square's height: setButtonDrawable sets the minimum
        // height from the drawable, and a 0 here left the view 20 dp with the
        // square overhanging it. 高 30 pt,即方塊的高度:setButtonDrawable 會依圖示設定最小高度，此處設 0
        // 讓 view 只有 20 dp,方塊超出它。
        checkBox.minHeight = (30 * density).toInt()
        checkBox.minimumHeight = (30 * density).toInt()
        checkBox.minWidth = 0
        checkBox.minimumWidth = 0
    }

    private val checkboxStyles = java.util.WeakHashMap<android.view.View, String>()

    // A progress bar drawn as UIKitBackend's: UIProgressView's .bar style, 3 pt
    // of the tint over a clear track, and without a value a third-width
    // segment of the tint sliding back and forth (user, 2026-10-10). The
    // framework's Widget.ProgressBar.Horizontal was a thick yellow bar and a
    // grey barber-pole (P29).
    // 進度條畫成 UIKitBackend 的樣子:UIProgressView 的 .bar 樣式，透明軌道上 3 pt 的 tint 色;沒有數值時，一段寬三分之一的
    // tint 色段來回滑動(使用者,2026-10-10)。框架的 Widget.ProgressBar.Horizontal 是粗的黃色條與灰色斜紋(P29)。
    fun styleProgressBar(bar: android.widget.ProgressBar) {
        val density = bar.context.resources.displayMetrics.density
        val tint = themeColorOf(bar.context, android.R.attr.colorPrimary)
        val fill = android.graphics.drawable.ClipDrawable(
            android.graphics.drawable.ColorDrawable(tint),
            android.view.Gravity.START,
            android.graphics.drawable.ClipDrawable.HORIZONTAL
        )
        val layers = android.graphics.drawable.LayerDrawable(
            arrayOf(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT), fill)
        )
        layers.setId(0, android.R.id.background)
        layers.setId(1, android.R.id.progress)
        bar.progressTintList = null
        bar.progressBackgroundTintList = null
        bar.indeterminateTintList = null
        bar.progressDrawable = layers
        bar.indeterminateDrawable = SlidingSegment(tint)
        val height = (3 * density).toInt()
        bar.minHeight = height
        bar.maxHeight = height
        bar.minimumHeight = height
    }

    // The indeterminate segment. ProgressBar starts an Animatable indeterminate
    // drawable while the bar is visible and stops it when it is not.
    // 不確定狀態的色段。ProgressBar 會在進度條可見時啟動 Animatable 的不確定 drawable,不可見時停止。
    private class SlidingSegment(color: Int) :
        android.graphics.drawable.Drawable(), android.graphics.drawable.Animatable {
        private val paint = android.graphics.Paint().apply { this.color = color }
        private var fraction = 0f
        private val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1200
            repeatCount = android.animation.ValueAnimator.INFINITE
            repeatMode = android.animation.ValueAnimator.REVERSE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener {
                fraction = it.animatedValue as Float
                invalidateSelf()
            }
        }

        override fun draw(canvas: android.graphics.Canvas) {
            val b = bounds
            val width = b.width() / 3f
            val left = b.left + fraction * (b.width() - width)
            canvas.drawRect(left, b.top.toFloat(), left + width, b.bottom.toFloat(), paint)
        }

        override fun start() = animator.start()

        override fun stop() = animator.cancel()

        override fun isRunning() = animator.isRunning

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    // One state of the checkbox: the rounded square, and SF Symbols' checkmark
    // when `mark` is not 0. 核取方塊的一種狀態：圓角方塊,`mark` 不為 0 時再加上 SF Symbols 的勾號。
    private class CheckboxFace(fill: Int, mark: Int, private val density: Float) :
        android.graphics.drawable.Drawable() {
        private val size = (30 * density).toInt()
        private val fillPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = fill
        }
        private val markPaint = if (mark == 0) null else
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = mark
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = 2.2f * density
                strokeCap = android.graphics.Paint.Cap.ROUND
                strokeJoin = android.graphics.Paint.Join.ROUND
            }

        override fun draw(canvas: android.graphics.Canvas) {
            val b = android.graphics.RectF(bounds)
            canvas.drawRoundRect(b, 10 * density, 10 * density, fillPaint)
            val paint = markPaint ?: return
            val path = android.graphics.Path()
            path.moveTo(b.left + b.width() * 0.29f, b.top + b.height() * 0.52f)
            path.lineTo(b.left + b.width() * 0.43f, b.top + b.height() * 0.66f)
            path.lineTo(b.left + b.width() * 0.71f, b.top + b.height() * 0.35f)
            canvas.drawPath(path, paint)
        }

        override fun getIntrinsicWidth() = size

        override fun getIntrinsicHeight() = size

        override fun setAlpha(alpha: Int) {
            fillPaint.alpha = alpha
            markPaint?.alpha = alpha
        }

        override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
            fillPaint.colorFilter = colorFilter
            markPaint?.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
    }

    private fun themeColorOf(context: android.content.Context, attr: Int): Int {
        val value = TypedValue()
        if (!context.theme.resolveAttribute(attr, value, true)) return 0
        return if (value.resourceId != 0) context.getColor(value.resourceId) else value.data
    }

    // .listStyle(.sidebar) on a ListView, drawn as a Material navigation drawer:
    // iOS's grouped background for the window's scheme, no dividers, and a pill-shaped
    // selection inset from the edges, tinted with colorControlHighlight. Off
    // restores what createSelectableListView set: no background, the theme's
    // listDivider, the flat grey selector.
    // ListView 上的 .listStyle(.sidebar),畫成 Material 的 navigation drawer:依視窗配色的 iOS grouped 背景、沒有分隔線、
    // 內縮的膠囊形選取(colorControlHighlight)。關閉時還原 createSelectableListView 所設的樣子。
    fun setListSidebar(listView: android.widget.ListView, sidebar: Boolean, dark: Boolean) {
        val context = listView.context
        fun themeColor(attr: Int): Int {
            val value = TypedValue()
            if (!context.theme.resolveAttribute(attr, value, true)) return 0
            return if (value.resourceId != 0) context.getColor(value.resourceId) else value.data
        }
        if (sidebar) {
            val density = context.resources.displayMetrics.density
            // UIKit's systemGroupedBackground, which UIKitBackend gives a sidebar
            // list: #F2F2F7 light, black dark, chosen by the window's scheme. The
            // theme's floating surface with the highlight over it was a Material
            // drawer, a darker grey than iOS's panel (P16, 2026-10-10).
            // UIKit 的 systemGroupedBackground,即 UIKitBackend 給側邊欄清單的背景：淺色 #F2F2F7、深色黑色，依視窗配色
            // 選擇。原本用主題的浮動表面再疊 highlight,是 Material 的抽屜，比 iOS 的面板更深(P16,2026-10-10)。
            listView.background = android.graphics.drawable.ColorDrawable(
                if (dark) 0xFF000000.toInt() else 0xFFF2F2F7.toInt()
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
    // A Menu's button, drawn as UIKitBackend's: a plain UIButton, the label in
    // the tint and nothing around it. The framework Button is a filled grey box
    // with a 48 dp minimum height (P19, 2026-10-10: "Open the menu" in black on
    // grey where iOS shows blue text). The label colour comes from the Swift side,
    // as a borderless button's does; the ripple is the borderless one, so a press
    // still shows.
    //
    // This replaces setButtonColorScheme, which tinted the grey box for a dark
    // scheme: with no box there is nothing to tint.
    //
    // Menu 的按鈕，畫成 UIKitBackend 的樣子：單純的 UIButton,標籤用 tint 色，周圍什麼都沒有。框架的 Button
    // 是填滿的灰色方塊，最小高度 48 dp(P19,2026-10-10:"Open the menu" 是灰底黑字，iOS 是藍字)。標籤色與無框
    // 按鈕一樣由 Swift 端決定;漣漪用無框的那一種，所以按下時仍有回饋。
    //
    // 這取代了 setButtonColorScheme——它為深色配色替灰色方塊上 tint;沒有方塊，就沒有東西要 tint。
    fun styleSimpleButton(button: android.widget.Button) {
        val value = TypedValue()
        button.background =
            if (button.context.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, value, true)) {
                button.context.getDrawable(value.resourceId)
            } else {
                null
            }
        button.stateListAnimator = null
        // 6 dp above and below: a plain UIButton with a 17 pt title is 34 pt
        // tall, its 22 pt line plus 6 either side (P19). 上下各 6 dp:17 pt 標題的單純 UIButton
        // 高 34 pt,即 22 pt 的行再加上下各 6(P19)。
        val inset = (6 * button.resources.displayMetrics.density).toInt()
        button.setPadding(0, inset, 0, inset)
        button.minHeight = 0
        button.minimumHeight = 0
        button.minWidth = 0
        button.minimumWidth = 0
        button.includeFontPadding = false
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
