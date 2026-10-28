import CGtk
import Foundation
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        return container
    }

    // `SwiftCrossUI.AffineTransform` in full where it appears below: Foundation
    // exports a type of the same name.
    //
    // Applied on every renderer. GTK's software renderer, GskCairoRenderer --
    // which Windows uses with `-GPU 0`, an explicit `GDK_DISABLE=gl` or no
    // hardware display adapter, and any platform uses with
    // `GSK_RENDERER=cairo` -- draws 2D transforms through a cairo matrix, but
    // only when GSK files the transform as 2D or better. The transform is
    // therefore written as translate, rotate and scale steps rather than as a
    // matrix; a matrix is filed as UNKNOWN and painted as a flat
    // rgb(255, 105, 180) rectangle. See AffineTransform2D in the Gtk module.
    //
    // 在每一種 renderer 上都套用。GTK 的軟體 renderer GskCairoRenderer——Windows 在 `-GPU 0`、明確設定的
    // `GDK_DISABLE=gl` 或沒有硬體顯示介面卡時使用它，任何平台設定 `GSK_RENDERER=cairo` 時也會用它——以 cairo
    // 矩陣繪製 2D 變換，但只限 GSK 將該變換歸為 2D 或更好的類別時。因此變換寫成平移、旋轉與縮放步驟，而不是
    // 矩陣；矩陣會被歸為 UNKNOWN,並被畫成一片平面的 rgb(255, 105, 180) 矩形。見 Gtk 模組中的
    // AffineTransform2D。
    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        widget.css.set(property: CSSProperty(key: "transform-origin", value: "0px 0px"))
        guard transform != .identity else {
            widget.css.set(property: CSSProperty(key: "transform", value: "none"))
            (widget.parentWidget as? Fixed)?.setChildMatrix(widget, nil)
            return
        }
        applyTransform(transform, to: widget)
    }

    /// Writes the transform as a GtkFixed child transform or a CSS `transform`,
    /// on every platform.
    ///
    /// The one place the matrix convention is written. A wrong argument order
    /// is not a crash -- it is a shear where a rotation was asked for -- so a
    /// second copy would be a second chance to get it wrong.
    ///
    /// 把變換寫成 GtkFixed 的 child transform 或 CSS 的 `transform`,所有平台皆然。
    ///
    /// 矩陣慣例只寫在這一處。引數順序寫錯不會當機——它會在要求旋轉的地方給出一個錯切——所以第二份副本
    /// 就是第二次寫錯的機會。
    private func applyTransform(
        _ transform: SwiftCrossUI.AffineTransform,
        to widget: Widget
    ) {
        // CSS matrix order is (a, b, c, d, tx, ty), where
        // x' = a*x + c*y + tx and y' = b*x + d*y + ty.
        // SwiftCrossUI stores [x y; z w], so b and c are z and y.
        // CSS 矩陣順序為 (a, b, c, d, tx, ty),其中 x' = a*x + c*y + tx、y' = b*x + d*y + ty。
        // SwiftCrossUI 儲存的是 [x y; z w],所以 b 與 c 是 z 與 y。
        let m = transform.linearTransform
        let t = transform.translation
        let matrix = [m.x, m.z, m.y, m.w, t.x, t.y]
        // Inside a GtkFixed -- every SwiftCrossUI container is one -- the matrix
        // goes on the parent's child transform: hit testing follows it as it does a
        // CSS transform, and there is no style recalculation, which made CSS the
        // larger part of each frame when the direct path animates many offsets
        // (P96, 2026-10-17). See Fixed.setChildMatrix.
        // 在 GtkFixed 之內(每個 SwiftCrossUI 容器都是)時，矩陣放在父容器的 child transform 上:hit testing
        // 與 CSS transform 一樣跟著它，而且沒有樣式重算——直接路徑同時動很多 offset 時，CSS 曾是每幀的大半
        // (P96,2026-10-17)。見 Fixed.setChildMatrix。
        if let parent = widget.parentWidget as? Fixed {
            widget.css.set(property: CSSProperty(key: "transform", value: "none"))
            parent.setChildMatrix(widget, matrix)
            return
        }
        let steps = AffineTransform2D(
            a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5]
        )
        widget.css.set(property: CSSProperty(key: "transform", value: steps.cssValue))
    }
}
