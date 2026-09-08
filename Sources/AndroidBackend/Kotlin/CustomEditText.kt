package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.view.inputmethod.EditorInfo
import android.widget.EditText

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
