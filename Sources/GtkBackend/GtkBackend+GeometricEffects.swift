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

        #if os(Windows)
            #if SCUI_DEBUG
                // A probe for the acceptance test in bugs/Gtk4-bugs.md: it applies
                // the transform as CSS whatever the renderer, so the hotpink
                // failure can be reproduced and counted. Without it zero hotpink
                // would be guaranteed whatever GTK does, and the test would report
                // a fix having measured nothing. On GTK 4.22.4 with the software
                // renderer it still reproduces: 76,285 pixels of exact
                // rgb(255,105,180), against 0 for the same app without the probe
                // (2026-09-05). See bugs/Gtk4-bugs.md for the renderer findings.
                //
                // Not a correct implementation: the matrix convention is
                // unchecked, because any non-identity transform answers "does GTK
                // draw a transformed widget at all". Compiled out of release
                // builds and off unless asked for:
                //
                //   SCUI_PROBE_GTK_TRANSFORM=1 ./P40.exe
                //
                // bugs/Gtk4-bugs.md 驗收測試用的探針：不論 renderer 為何都以 CSS 套用變換，好讓 hotpink 失敗
                // 可以被重現並計數。少了它，無論 GTK 如何表現都必然是零個 hotpink,而該測試會在什麼都沒量到的
                // 情況下回報「已修復」。在 GTK 4.22.4 的軟體 renderer 上它依然可重現：76,285 個精確為
                // rgb(255,105,180) 的像素，對照組(同一支 app 未開探針)為 0(2026-09-05)。renderer 方面的發現見
                // bugs/Gtk4-bugs.md。
                //
                // 這不是正確的實作：矩陣慣例並未查證，因為任何非 identity 的變換都足以回答「GTK 到底畫不畫得出
                // 被變換的 widget」。它會被排除在 release 建置之外，且非經指定不會啟用。
                if ProcessInfo.processInfo.environment["SCUI_PROBE_GTK_TRANSFORM"] == "1" {
                    let m = transform.linearTransform
                    let t = transform.translation
                    widget.css.set(
                        property: CSSProperty(
                            key: "transform",
                            // Unitless. CSS `matrix()` takes <number> for tx and ty,
                            // so writing `px` makes the whole declaration invalid
                            // and GTK drops it silently -- which cost a run that
                            // reported zero hotpink and looked like a fixed bug.
                            // 不帶單位。CSS `matrix()` 的 tx 與 ty 收的是 <number>，寫成 `px` 會
                            // 讓整條宣告無效而被 GTK 靜默丟棄——這曾害一次執行回報零個 hotpink，
                            // 看起來就像錯誤已經修好。
                            value: "matrix(\(m.x), \(m.z), \(m.y), \(m.w), \(t.x), \(t.y))"
                        )
                    )
                    return
                }
            #endif

            // Applied only with Direct Composition, which is on by default: GTK
            // then realises GskGLRenderer and draws every transform correctly
            // (P40 on Win-gtk4, as on WSL-gtk4 and Win-WinUI, 2026-09-05).
            //
            // Three things leave it off: `-GPU 0`, an explicit `GDK_DISABLE=gl`,
            // and a machine with no hardware display adapter. GTK then stays on
            // GskCairoRenderer, which applies the transform and paints the whole
            // transformed subtree as one flat rectangle of hotpink,
            // rgb(255, 105, 180) -- GSK's fallback for a node it declined to
            // render -- with nothing logged (P40, 2026-08-27). Declining beats
            // applying it there: an untransformed view is legible and clickable;
            // a hotpink rectangle is neither.
            //
            // Ruled out as causes of the hotpink: the mechanism (CSS
            // `transform: matrix(...)` and `gtk_fixed_set_child_transform` with a
            // GskTransform fail identically), this backend's code (a control that
            // skipped only the transform call rendered all seven P40 tiles), and
            // the content (a bare `Text` goes hotpink too).
            //
            // 只在 Direct Composition 開啟時套用，而它預設開啟:GTK 此時會實作 GskGLRenderer,並正確繪出每一個
            // 變換(Win-gtk4 上的 P40,與 WSL-gtk4、Win-WinUI 相同,2026-09-05)。
            //
            // 有三種情況會讓它關閉:`-GPU 0`、明確設定的 `GDK_DISABLE=gl`,以及沒有硬體顯示介面卡的機器。
            // GTK 此時留在 GskCairoRenderer 上，它會套用變換，然後把整棵被變換的子樹畫成一個平面的 hotpink
            // 矩形 rgb(255, 105, 180)——那是 GSK 對它拒絕繪製之節點的退路——而且沒有任何 log(P40,2026-08-27)。
            // 在那裡，拒絕勝過套用：未經變換的 view 仍可閱讀、仍可點擊，而一片 hotpink 兩者皆非。
            //
            // 已排除的 hotpink 成因：機制(CSS `transform: matrix(...)` 與帶 GskTransform 的
            // `gtk_fixed_set_child_transform` 以相同方式失敗)、本 backend 的程式碼(只略過變換呼叫的對照組
            // 完整畫出 P40 的七個方塊)、以及內容(單純一個 `Text` 也會變成 hotpink)。
            guard GtkBackend.directCompositionEnabled else {
                debugLogOnce(
                    """
                    GtkBackend is on GTK's software renderer, so geometric effects are \
                    not applied: GskCairoRenderer draws a transformed widget as a flat \
                    hotpink rectangle, losing its content. offset, rotationEffect, \
                    scaleEffect and transformEffect draw untransformed. Direct \
                    Composition is on by default; this means -GPU 0, GDK_DISABLE=gl, or \
                    no hardware display adapter.
                    """
                )
                return
            }

            applyTransformCSS(transform, to: widget)
        #else
            applyTransformCSS(transform, to: widget)
        #endif
    }

    /// Writes the transform as a GtkFixed child transform or a CSS `matrix()`,
    /// on every platform.
    ///
    /// The one place the matrix convention is written. A wrong argument order
    /// is not a crash -- it is a shear where a rotation was asked for -- so a
    /// second copy would be a second chance to get it wrong.
    ///
    /// 把變換寫成 GtkFixed 的 child transform 或 CSS 的 `matrix()`,所有平台皆然。
    ///
    /// 矩陣慣例只寫在這一處。引數順序寫錯不會當機——它會在要求旋轉的地方給出一個錯切——所以第二份副本
    /// 就是第二次寫錯的機會。
    private func applyTransformCSS(
        _ transform: SwiftCrossUI.AffineTransform,
        to widget: Widget
    ) {
        let m = transform.linearTransform
        let t = transform.translation
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
            parent.setChildMatrix(widget, [m.x, m.z, m.y, m.w, t.x, t.y])
            return
        }
        widget.css.set(
            property: CSSProperty(
                key: "transform",
                // CSS matrix order is (a, b, c, d, tx, ty), where
                // x' = a*x + c*y + tx and y' = b*x + d*y + ty.
                // SwiftCrossUI stores [x y; z w], so b and c are z and y.
                //
                // Unitless. CSS `matrix()` takes <number> for tx and ty, so
                // writing `px` makes the whole declaration invalid and GTK drops
                // it silently -- which once cost a run that reported zero hotpink
                // and looked like a fixed bug.
                //
                // 不帶單位。CSS `matrix()` 的 tx 與 ty 收的是 <number>，寫成 `px` 會讓整條宣告
                // 無效而被 GTK 靜默丟棄——這曾害一次執行回報零個 hotpink，看起來就像錯誤已修好。
                value: "matrix(\(m.x), \(m.z), \(m.y), \(m.w), \(t.x), \(t.y))"
            )
        )
    }
}
