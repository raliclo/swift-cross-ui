package dev.swiftcrossui.androidbackend

import android.view.View
import java.util.WeakHashMap

/**
 * Content shapes: where a view can be touched, set by `contentShape(_:eoFill:)`.
 *
 * Android has no per-view hit shape; a ViewGroup hands a touch to any visible child whose rectangle
 * contains it. So the check is made by `CustomContainer.dispatchTouchEvent`, which owns the dispatch:
 * on ACTION_DOWN, a child whose rectangle contains the point but whose shape does not is passed over
 * and the next child underneath is offered the touch, which is what passing through means. A
 * `CustomContainer` also refuses a down outside its own shape, for one that is not inside another.
 *
 * The region arrives already flattened to polygons and scaled to pixels by Swift (`HitRegion`), and
 * the containment rule below is the same one `HitRegion.contains` runs, so every backend agrees.
 *
 * Content shape:由 `contentShape(_:eoFill:)` 設定的、view 可被觸控的範圍。
 *
 * Android 沒有逐 view 的命中形狀；ViewGroup 會把觸控交給矩形包含該點的任何可見子元件。因此檢查由掌管分派的
 * `CustomContainer.dispatchTouchEvent` 進行：在 ACTION_DOWN 時，矩形包含該點、形狀卻不包含的子元件會被略過，
 * 改把觸控交給下方的下一個子元件，那就是「穿透」的意思。`CustomContainer` 也會拒收落在自己形狀外的 down，
 * 供不在其他容器之內的情況使用。
 *
 * 區域由 Swift(`HitRegion`)先展平成多邊形並換算為像素，下方的包含規則與 `HitRegion.contains` 相同，
 * 因此每個 backend 的答案一致。
 */
object ContentShapes {
    private class Region(val points: FloatArray, val counts: IntArray, val evenOdd: Boolean)

    private val regions = WeakHashMap<View, Region>()

    @JvmStatic
    fun set(view: View, points: FloatArray, counts: IntArray, evenOdd: Boolean, clear: Boolean) {
        if (clear) {
            regions.remove(view)
        } else {
            regions[view] = Region(points, counts, evenOdd)
        }
    }

    @JvmStatic fun isEmpty(): Boolean = regions.isEmpty()

    @JvmStatic fun hasShape(view: View): Boolean = regions.containsKey(view)

    /** Whether (x, y), in the view's own pixels, is inside its shape; true without one. */
    @JvmStatic
    fun contains(view: View, x: Float, y: Float): Boolean {
        val region = regions[view] ?: return true
        var winding = 0
        var crossings = 0
        var start = 0
        for (count in region.counts) {
            if (count >= 3) {
                var px = region.points[2 * (start + count - 1)]
                var py = region.points[2 * (start + count - 1) + 1]
                for (i in 0 until count) {
                    val cx = region.points[2 * (start + i)]
                    val cy = region.points[2 * (start + i) + 1]
                    if ((py <= y) != (cy <= y)) {
                        val t = (y - py) / (cy - py)
                        if (px + t * (cx - px) > x) {
                            crossings++
                            winding += if (cy > py) 1 else -1
                        }
                    }
                    px = cx
                    py = cy
                }
            }
            start += count
        }
        return if (region.evenOdd) crossings % 2 == 1 else winding != 0
    }
}
