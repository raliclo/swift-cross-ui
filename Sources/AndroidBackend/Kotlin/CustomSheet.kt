package dev.swiftcrossui.androidbackend

import android.app.Dialog
import android.content.DialogInterface
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

class CustomSheet(var content: View?) : BottomSheetDialogFragment() {
    var onDismissListener: SwiftAction? = null

    private var backgroundColor = 0
    private var isDismissable = false

    private var root: ViewGroup? = null

    init {
        content?.layoutParams =
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL or Gravity.FILL_VERTICAL,
            )
    }

    fun update(isDismissable: Boolean, backgroundColor: Int) {
        this.isDismissable = isDismissable
        dialog?.setCancelable(isDismissable)

        this.backgroundColor = backgroundColor
        root?.backgroundTintList =
            ColorStateList(arrayOf(intArrayOf()), intArrayOf(backgroundColor))
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)

        content?.let {
            dialog.setContentView(it)
            val root = it.parent!! as ViewGroup
            root.backgroundTintList =
                ColorStateList(arrayOf(intArrayOf()), intArrayOf(backgroundColor))
            this.root = root
        }

        dialog.setCancelable(isDismissable)

        return dialog
    }

    // Registered while shown, so the synthesiser can reach the sheet -- see
    // FrontWindows.
    // 顯示期間登記，好讓 synthesiser 碰得到 sheet——見 FrontWindows。
    override fun onStart() {
        super.onStart()
        dialog?.window?.decorView?.let { FrontWindows.add(it) }
    }

    override fun onStop() {
        dialog?.window?.decorView?.let { FrontWindows.remove(it) }
        super.onStop()
    }

    override fun onCancel(dialog: DialogInterface) {
        onDismissListener?.call()
        super.onCancel(dialog)
    }

    override fun onDestroyView() {
        content = null
        root = null
        super.onDestroyView()
    }
}
