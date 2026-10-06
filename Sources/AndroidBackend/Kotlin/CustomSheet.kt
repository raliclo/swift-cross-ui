package dev.swiftcrossui.androidbackend

import android.app.Dialog
import android.content.DialogInterface
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.bottomsheet.BottomSheetDragHandleView
import com.google.android.material.shape.CornerFamily
import com.google.android.material.shape.MaterialShapeDrawable
import com.google.android.material.shape.ShapeAppearanceModel

// A Material bottom sheet with SwiftCrossUI's presentation options.
//
// **Detents, corner radius and the drag indicator are implemented, 2026-10-06.**
// They were ignored before, with comments saying Material could not set a
// corner radius at run time and that the background broke when the sheet was
// taller than its contents. Neither holds: the sheet's background is a
// MaterialShapeDrawable that can be replaced with any corner size, and the
// background stopped short only because the bottom-sheet frame wrapped its
// content -- it is now as tall as the largest detent.
//
// Detents map onto BottomSheetBehavior's resting states, which are at most
// three: collapsed (peekHeight), half-expanded (halfExpandedRatio) and expanded
// (expandedOffset). Swift passes up to three heights in dp, smallest first; a
// negative one is absent. More than three cannot be resting states in Material;
// AndroidBackend+Sheets.swift picks the smallest, the largest and one between.
//
// 帶有 SwiftCrossUI 呈現選項的 Material bottom sheet。**detents、圓角與拖曳指示器已實作(2026-10-06)。**
// 之前它們被忽略，註解說 Material 無法在執行期設定圓角、sheet 比內容高時背景會壞掉。兩者都不成立：sheet 的
// 背景是可換成任何圓角的 MaterialShapeDrawable;背景會短一截，只是因為 bottom-sheet 框架包著內容——現在它和
// 最高的 detent 一樣高。detents 對應到 BottomSheetBehavior 的停靠狀態，最多三個：collapsed(peekHeight)、
// half-expanded(halfExpandedRatio)與 expanded(expandedOffset)。Swift 傳入最多三個 dp 高度，由小到大；
// 負值表示沒有。超過三個在 Material 裡無法成為停靠狀態；AndroidBackend+Sheets.swift 取最小、最大與中間一個。
class CustomSheet(var content: View?) : BottomSheetDialogFragment() {
    var onDismissListener: SwiftAction? = null

    private var backgroundColor = 0
    private var isDismissable = false
    private var cornerRadiusDp = -1f
    private var detentsDp = floatArrayOf()
    private var showsDragHandle = false

    private var root: ViewGroup? = null
    private var dragHandle: View? = null

    init {
        content?.layoutParams =
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER_HORIZONTAL }
    }

    fun update(
        isDismissable: Boolean,
        backgroundColor: Int,
        cornerRadiusDp: Float,
        detent0: Float,
        detent1: Float,
        detent2: Float,
        showsDragHandle: Boolean,
    ) {
        this.isDismissable = isDismissable
        this.backgroundColor = backgroundColor
        this.cornerRadiusDp = cornerRadiusDp
        this.detentsDp = floatArrayOf(detent0, detent1, detent2).filter { it >= 0 }.toFloatArray()
        this.showsDragHandle = showsDragHandle
        dialog?.setCancelable(isDismissable)
        apply()
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)

        content?.let {
            val column = LinearLayout(requireContext())
            column.orientation = LinearLayout.VERTICAL
            val handle = BottomSheetDragHandleView(requireContext())
            column.addView(
                handle,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            column.addView(it)
            dialog.setContentView(column)
            this.dragHandle = handle
            this.root = column.parent!! as ViewGroup
        }

        dialog.setCancelable(isDismissable)
        dialog.setOnShowListener { apply() }

        return dialog
    }

    private fun apply() {
        val root = root ?: return
        val dialog = dialog as? BottomSheetDialog ?: return
        val density = root.resources.displayMetrics.density

        // The background: one shape with the requested top corners, filled
        // with the colour, instead of a tint over Material's own shape.
        // 背景：一個帶有所要求上方圓角、以該顏色填滿的形狀，而不是在 Material 自己的形狀上加 tint。
        val shape = ShapeAppearanceModel.builder()
        if (cornerRadiusDp >= 0) {
            shape.setTopLeftCorner(CornerFamily.ROUNDED, cornerRadiusDp * density)
            shape.setTopRightCorner(CornerFamily.ROUNDED, cornerRadiusDp * density)
        } else {
            (root.background as? MaterialShapeDrawable)?.shapeAppearanceModel?.let {
                shape.setTopLeftCorner(it.topLeftCorner)
                shape.setTopLeftCornerSize(it.topLeftCornerSize)
                shape.setTopRightCorner(it.topRightCorner)
                shape.setTopRightCornerSize(it.topRightCornerSize)
            }
        }
        root.backgroundTintList = null
        root.background =
            MaterialShapeDrawable(shape.build()).apply {
                fillColor = ColorStateList.valueOf(backgroundColor)
            }

        dragHandle?.visibility = if (showsDragHandle) View.VISIBLE else View.GONE

        val behavior = dialog.behavior
        val detents = detentsDp.map { (it * density).toInt() }
        if (detents.isEmpty()) {
            // No detents: as tall as the content, Material's default.
            // 沒有 detent:與內容同高，即 Material 的預設。
            root.layoutParams = root.layoutParams.apply { height = ViewGroup.LayoutParams.WRAP_CONTENT }
            behavior.isFitToContents = true
            behavior.skipCollapsed = true
            behavior.state = BottomSheetBehavior.STATE_EXPANDED
            return
        }

        val parentHeight = (root.parent as? View)?.height?.takeIf { it > 0 }
            ?: root.resources.displayMetrics.heightPixels
        val largest = detents.last().coerceAtMost(parentHeight)
        // The frame is as tall as the largest detent, so the background reaches
        // the bottom at every detent rather than stopping under the content.
        // 框架與最高的 detent 等高，讓背景在每個 detent 都延伸到底，而不是停在內容下方。
        root.layoutParams = root.layoutParams.apply { height = largest }

        behavior.isFitToContents = false
        behavior.expandedOffset = parentHeight - largest
        behavior.peekHeight = detents.first().coerceAtMost(largest)
        behavior.skipCollapsed = detents.size == 1
        if (detents.size == 3) {
            behavior.halfExpandedRatio = (detents[1].toFloat() / parentHeight).coerceIn(0.01f, 0.99f)
        } else {
            // Two detents, or one: no half-expanded stop. A ratio equal to the
            // peek makes the half-expanded state coincide with collapsed.
            // 兩個或一個 detent:沒有半展開的停靠點。比例等於 peek 時，半展開與 collapsed 重合。
            behavior.halfExpandedRatio =
                (detents.first().toFloat() / parentHeight).coerceIn(0.01f, 0.99f)
        }
        // Opens at the smallest detent, as UIKit's sheet does.
        // 以最小的 detent 開啟，與 UIKit 的 sheet 相同。
        behavior.state =
            if (detents.size == 1) BottomSheetBehavior.STATE_EXPANDED
            else BottomSheetBehavior.STATE_COLLAPSED
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
        dragHandle = null
        super.onDestroyView()
    }
}
