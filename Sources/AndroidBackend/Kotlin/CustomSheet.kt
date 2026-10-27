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

// A Material bottom sheet with SwiftCrossUI's presentation options: detents,
// corner radius and the drag indicator.
//
// Material can set a corner radius at run time: the sheet's background is a
// MaterialShapeDrawable that can be replaced with any corner size. The
// bottom-sheet frame is as tall as the largest detent, so the background does
// not stop short when the sheet is taller than its contents.
//
// Detents map onto BottomSheetBehavior's resting states, which are at most
// three: collapsed (peekHeight), half-expanded (halfExpandedRatio) and expanded
// (expandedOffset). Swift passes up to three heights in dp, smallest first; a
// negative one is absent. More than three cannot be resting states in Material;
// AndroidBackend+Sheets.swift picks the smallest, the largest and one between.
//
// 帶有 SwiftCrossUI 呈現選項(detents、圓角與拖曳指示器)的 Material bottom sheet。
// Material 可以在執行期設定圓角:sheet 的背景是可換成任何圓角的 MaterialShapeDrawable。bottom-sheet 框架與
// 最高的 detent 一樣高，因此 sheet 比內容高時背景不會短一截。
// detents 對應到 BottomSheetBehavior 的停靠狀態，最多三個：collapsed(peekHeight)、
// half-expanded(halfExpandedRatio)與 expanded(expandedOffset)。Swift 傳入最多三個 dp 高度，由小到大；
// 負值表示沒有。超過三個在 Material 裡無法成為停靠狀態；AndroidBackend+Sheets.swift 取最小、最大與中間一個。
class CustomSheet(var content: View?) : BottomSheetDialogFragment() {
    var onDismissListener: SwiftAction? = null

    private var backgroundColor = 0
    private var isDismissable = false
    private var cornerRadiusDp = -1f
    private var detentsDp = floatArrayOf()
    private var showsDragHandle = false
    private var fillsWindow = false
    // Material's own cap, read once before it is lifted, so a sheet that stops
    // filling gets it back (640 dp on swift-cross-ui-tablet36).
    // Material 自己的上限，在拿掉之前讀一次，讓不再填滿的 sheet 能拿回它(swift-cross-ui-tablet36 上是 640 dp)。
    private var materialMaxWidth: Int? = null

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

    /// fullScreenCover: the sheet spans the window's width, past Material's
    /// tablet cap (P49 on swift-cross-ui-tablet36 drew its cover 640 dp wide in the
    /// middle of a 1280 dp window, 2026-10-20). Its height comes from the detent.
    /// fullScreenCover:sheet 橫跨整個視窗寬度，越過 Material 在平板上的上限(2026-10-20,swift-cross-ui-tablet36 上 P49 的
    /// cover 在 1280 dp 的視窗中間只畫了 640 dp 寬)。高度來自 detent。
    fun setFillsWindow(fillsWindow: Boolean) {
        this.fillsWindow = fillsWindow
        apply()
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
        if (materialMaxWidth == null) materialMaxWidth = behavior.maxWidth
        val maxWidth = if (fillsWindow) ViewGroup.LayoutParams.MATCH_PARENT else materialMaxWidth!!
        if (behavior.maxWidth != maxWidth) {
            behavior.maxWidth = maxWidth
            root.requestLayout()
        }
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

    /// Set once the listener has run, so a dismissal is reported once.
    /// 監聽器執行過後設定，讓一次關閉只回報一次。
    private var dismissReported = false

    // onDismiss, not onCancel: a cancel (back, a tap outside, a swipe) ends in
    // onDismiss too, and so does dismiss() -- the programmatic path
    // (`isPresented = false`), which onCancel never saw, so SwiftUI's
    // `sheet(onDismiss:)` did not run for it (todo.md, "Six divergences",
    // item 1; 2026-10-20). A configuration change dismisses the dialog to
    // rebuild it; that is not the sheet ending.
    // 用 onDismiss 而非 onCancel:取消(返回、點外面、滑掉)最後也會走到 onDismiss,dismiss()——程式關閉
    // (`isPresented = false`)——也是;onCancel 從來看不到後者，所以 SwiftUI 的 `sheet(onDismiss:)` 沒有為它執行
    // (todo.md「六項分歧」第 1 項;2026-10-20)。設定變更會為了重建而關閉 dialog,那不是 sheet 結束。
    override fun onDismiss(dialog: DialogInterface) {
        super.onDismiss(dialog)
        if (activity?.isChangingConfigurations == true || dismissReported) return
        dismissReported = true
        onDismissListener?.call()
    }

    override fun onDestroyView() {
        content = null
        root = null
        dragHandle = null
        super.onDestroyView()
    }
}
