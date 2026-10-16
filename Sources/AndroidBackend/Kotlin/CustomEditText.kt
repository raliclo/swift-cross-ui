package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.SystemClock
import android.text.Selection
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import kotlin.math.hypot

open class CustomEditText(activity: Activity) : EditText(activity) {
    var onChange: SwiftAction? = null

    private var onSubmit: SwiftAction? = null

    // The chrome the theme gave this EditText, captured before anything has had
    // a chance to replace it, so that TextFieldStyle.automatic can put it back.
    //
    // Captured here rather than read back on demand because it is destroyed by
    // the first non-automatic style: `background = null` for .plain, or a
    // GradientDrawable for the bordered shapes. A widget is re-committed on
    // every update and may have been .plain a moment ago, so without a saved
    // copy .plain would be a one-way door -- an application could set it but
    // never leave it.
    //
    // The padding goes with the background and not separately. On Android a
    // background Drawable supplies the view's padding, so replacing the
    // background silently changes the text inset too; restoring one without the
    // other leaves the field the right shape and the wrong size.
    //
    // 主題給這個 EditText 的外框裝飾，在任何東西有機會替換它之前擷取下來，好讓
    // TextFieldStyle.automatic 能把它放回去。
    //
    // 之所以在此擷取而非到時候再讀回，是因為它會被第一個非 automatic 的樣式摧毀：.plain 會將
    // `background` 設為 null，而帶邊框的外形則會換成 GradientDrawable。widget 在每次更新時都會被
    // 重新 commit，而它上一刻可能是 .plain；因此若沒有存下一份副本，.plain 就會是一扇單向門
    // ——應用程式設得進去，卻永遠出不來。
    //
    // padding 與 background 一併處理，而非分開。在 Android 上，背景 Drawable 會提供該 view 的
    // padding，因此替換背景也會悄悄改變文字的內縮；只還原其中一者，會得到一個外形正確、尺寸錯誤的
    // 欄位。
    private val defaultBackground: Drawable? = background

    private val defaultPadding =
        intArrayOf(paddingLeft, paddingTop, paddingRight, paddingBottom)

    /** Restores the background and padding this EditText was constructed with. */
    fun restoreDefaultChrome() {
        background = defaultBackground
        setPadding(defaultPadding[0], defaultPadding[1], defaultPadding[2], defaultPadding[3])
    }

    // EditText calls onTextChanged with empty string multiple times before the initial render.
    // Because it's multiple times, we can't just use a one-time flag that's cleared in
    // onTextChanged. However, they all seem to happen before the first onDraw, so we can clear it
    // there.
    private var hasBeenRendered = false

    private var isSettingText = false

    private fun isSubmitAction(action: Int) =
        action == EditorInfo.IME_ACTION_SEND ||
            action == EditorInfo.IME_ACTION_GO ||
            action == EditorInfo.IME_ACTION_SEARCH

    init {
        setOnEditorActionListener { v, actionId, event ->
            val action =
                if (actionId == EditorInfo.IME_NULL) v.imeOptions and EditorInfo.IME_MASK_ACTION
                else actionId

            if (isSubmitAction(action)) {
                onSubmit?.call()
                onSubmit != null
            } else {
                false
            }
        }
    }

    fun setOnSubmit(value: SwiftAction?) {
        onSubmit = value
        if (value != null) {
            val currentOptions = imeOptions
            if (!isSubmitAction(currentOptions and EditorInfo.IME_MASK_ACTION)) {
                imeOptions =
                    (currentOptions and EditorInfo.IME_MASK_ACTION.inv()) or
                        EditorInfo.IME_ACTION_GO
            }
        }
    }

    fun setTextFromSwift(text: String) {
        isSettingText = true
        try {
            setText(text as CharSequence)
        } finally {
            isSettingText = false
        }
    }

    // Long-press drag selection (SwiftCrossUI's longPressTextSelection()). The
    // same rules as LongPressSelectionTracker in Swift, here because touch
    // events never cross into Swift: the platform's long-press timeout and
    // touch slop decide; until the timeout the press is EditText's (a tap still
    // places the caret and focuses); a move past the slop first leaves it all to
    // EditText and its parents (a scroll stays a scroll). When the timeout
    // fires with the finger still near, the press is taken away: EditText gets
    // ACTION_CANCEL, every parent is told requestDisallowInterceptTouchEvent,
    // and from then on the moves set the selection from the anchor with
    // getOffsetForPosition -- Selection.setSelection keeps a backward one
    // backward -- and are not passed on, so nothing scrolls. The release keeps
    // the selection and shows no menu. Long-clickable is off meanwhile, which
    // is what stops EditText's own long press (word selection and its action
    // mode) from firing at the same timeout.
    //
    // 長按拖曳選取(SwiftCrossUI 的 longPressTextSelection())。規則與 Swift 的 LongPressSelectionTracker
    // 相同，放在這裡是因為觸控事件從不進入 Swift:由平台的長按逾時與 touch slop 決定;逾時之前按壓屬於
    // EditText(點擊照樣放插入點並取得焦點);先移動超過 slop 就全部交給 EditText 與它的父層(捲動仍是捲動)。
    // 逾時觸發時手指仍在附近，就把按壓拿走:EditText 收到 ACTION_CANCEL,每個父層都被
    // requestDisallowInterceptTouchEvent,之後每次移動以 getOffsetForPosition 從錨點設定選取——
    // Selection.setSelection 讓反向選取保持反向——且不往下傳，所以不會捲動。放開後保留選取、不顯示選單。
    // 期間關閉 long-clickable,正是它讓 EditText 自己的長按(選字與 action mode)不會在同一個逾時觸發。
    private var longPressSelection: SwiftAction? = null
    private var longPressWasLongClickable = true
    private var longPressState = 0 // 0 idle, 1 pending, 2 selecting, 3 passed through
    private var longPressDownX = 0f
    private var longPressDownY = 0f
    private var longPressLastX = 0f
    private var longPressLastY = 0f
    private var longPressDownTime = 0L
    private var longPressAnchor = 0
    private var longPressPhase = 0 // 0 began, 1 changed, 2 ended
    private val longPressSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val longPressFire = Runnable { beginLongPressSelection() }

    /** Turns long-press drag selection on (a handler) or off (null). */
    fun setLongPressSelection(action: SwiftAction?) {
        val wasEnabled = longPressSelection != null
        longPressSelection = action
        if (action != null && !wasEnabled) {
            longPressWasLongClickable = isLongClickable
            isLongClickable = false
        } else if (action == null && wasEnabled) {
            isLongClickable = longPressWasLongClickable
            removeCallbacks(longPressFire)
            longPressState = 0
        }
    }

    /** What the last call to the handler reported: 0 began, 1 changed, 2 ended. */
    fun longPressSelectionPhase(): Int = longPressPhase

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (longPressSelection == null) return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                longPressDownX = event.x
                longPressDownY = event.y
                longPressLastX = event.x
                longPressLastY = event.y
                longPressDownTime = event.downTime
                longPressState = 1
                removeCallbacks(longPressFire)
                postDelayed(longPressFire, ViewConfiguration.getLongPressTimeout().toLong())
            }
            MotionEvent.ACTION_MOVE -> {
                longPressLastX = event.x
                longPressLastY = event.y
                if (longPressState == 2) {
                    extendLongPressSelection(event.x, event.y, 1)
                    return true
                }
                if (longPressState == 1 &&
                    hypot(event.x - longPressDownX, event.y - longPressDownY) > longPressSlop
                ) {
                    longPressState = 3
                    removeCallbacks(longPressFire)
                }
            }
            MotionEvent.ACTION_UP -> {
                removeCallbacks(longPressFire)
                if (longPressState == 2) {
                    longPressState = 0
                    extendLongPressSelection(event.x, event.y, 2)
                    return true
                }
                longPressState = 0
            }
            MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(longPressFire)
                if (longPressState == 2) {
                    longPressState = 0
                    extendLongPressSelection(longPressLastX, longPressLastY, 2)
                    return true
                }
                longPressState = 0
            }
        }
        return super.onTouchEvent(event)
    }

    private fun beginLongPressSelection() {
        if (longPressState != 1 || longPressSelection == null) return
        longPressState = 2
        val now = SystemClock.uptimeMillis()
        val cancel = MotionEvent.obtain(
            longPressDownTime, now, MotionEvent.ACTION_CANCEL, longPressLastX, longPressLastY, 0
        )
        super.onTouchEvent(cancel)
        cancel.recycle()
        parent?.requestDisallowInterceptTouchEvent(true)
        if (!hasFocus()) requestFocus()
        longPressAnchor = getOffsetForPosition(longPressDownX, longPressDownY)
        extendLongPressSelection(longPressLastX, longPressLastY, 0)
    }

    private fun extendLongPressSelection(x: Float, y: Float, phase: Int) {
        val text = editableText ?: return
        val length = text.length
        val anchor = longPressAnchor.coerceIn(0, length)
        val extent = getOffsetForPosition(x, y).coerceIn(0, length)
        Selection.setSelection(text, anchor, extent)
        longPressPhase = phase
        longPressSelection?.call()
    }

    protected override fun onDraw(canvas: Canvas) {
        hasBeenRendered = true
        super.onDraw(canvas)
    }

    protected override fun onTextChanged(
        text: CharSequence,
        start: Int,
        lengthBefore: Int,
        lengthAfter: Int,
    ) {
        if (!isSettingText && hasBeenRendered) {
            onChange?.call()
        }
    }
}
