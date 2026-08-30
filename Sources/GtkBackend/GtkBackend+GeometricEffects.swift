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
            return
        }

        #if os(Windows)
            #if SCUI_DEBUG
                // The only code left that can trigger the GTK bug, and it exists so
                // that the acceptance test in bugs/Gtk4-bugs.md can fire at all.
                //
                // That test says to count hotpink pixels and treat zero as "the bug
                // is gone". With the application removed, zero is guaranteed no
                // matter what GTK does, so the test would report a fix having
                // measured nothing. Verified 2026-08-29: P40 on GTK 4.22.4 gives
                // zero hotpink and seven tiles all exactly 90x57, i.e. nothing was
                // transformed and nothing was broken.
                //
                // Not a correct implementation and not a step towards one. The
                // matrix convention is unchecked, because the question this answers
                // is "does GTK draw a transformed widget at all", and any
                // non-identity transform settles that. Compiled out of release
                // builds and off unless asked for, since switching it on
                // deliberately reproduces a total rendering failure.
                //
                //   SCUI_PROBE_GTK_TRANSFORM=1 ./P40.exe
                //
                // 這是唯一還能觸發該 GTK 錯誤的程式碼，它存在的目的，是讓 bugs/Gtk4-bugs.md 中的
                // 驗收測試「有可能成立」。
                //
                // 該測試說要數 hotpink 像素，並把「零」視為「錯誤已修好」。但在移除了套用邏輯之後，
                // 無論 GTK 如何表現，結果都必然是零——於是該測試會在什麼都沒量到的情況下回報「已修
                // 復」。2026-08-29 實測：P40 於 GTK 4.22.4 得到零個 hotpink，七個方塊皆為 90x57，
                // 亦即什麼都沒被變換，也什麼都沒壞。
                //
                // 這不是正確的實作，也不是邁向實作的一步。矩陣慣例並未查證，因為它要回答的問題是
                // 「GTK 到底畫不畫得出被變換的 widget」，而任何非 identity 的變換都足以定案。它會
                // 被排除在 release 建置之外，且非經指定不會啟用——因為打開它就是刻意重現一次全面性
                // 的繪製失敗。
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

            // GTK 4 on Windows cannot render a transformed widget at all, so this
            // conforms and declines rather than producing something unreadable.
            //
            // Measured 2026-08-27 with P40, and the failure is total: the transform
            // is applied -- tiles measurably move and resize -- and then the entire
            // transformed subtree is painted as one flat rectangle of hotpink,
            // rgb(255, 105, 180), sampled from the capture. That is GSK's fallback
            // for a node it declined to render. Nothing is logged and nothing warns.
            //
            // Four things were ruled out before concluding it is the platform:
            //
            //   * the mechanism -- CSS `transform: matrix(...)` and
            //     `gtk_fixed_set_child_transform` with a GskTransform fail
            //     identically, and they are unrelated code paths
            //   * the renderer -- GSK_RENDERER=cairo and the default GL renderer
            //     produce the same hotpink
            //   * this backend's code -- a no-op control that built the container
            //     and skipped only the transform call rendered all seven P40 tiles
            //     perfectly, so the container, the modifier and the layout are not
            //     involved
            //   * the content -- a bare `Text` with no nested containers and no
            //     `Color` views inside the transformed subtree goes hotpink too
            //
            // Declining is better than applying it. An untransformed view is still
            // legible and still clickable; a hotpink rectangle has lost its content
            // entirely. This is the one case where "apply what you can" comes out
            // behind "apply nothing and say so".
            //
            // WinUIBackend implements this same protocol and does render it:
            // rotation, scale and offset all show correctly in P40 there. So the
            // protocol is sound and this is a GTK-on-Windows gap, not a design problem.
            //
            // GTK 4 在 Windows 上完全無法繪製被變換過的 widget，因此此處選擇「宣告 conformance 但拒絕
            // 執行」，而非產出無法閱讀的畫面。
            //
            // WinUIBackend 實作了同一個 protocol 且確實能繪製：旋轉、縮放與位移在該處的 P40 中都正確
            // 顯示。因此 protocol 本身是健全的，這是 GTK on Windows 這一側的缺口，而非設計問題。
            debugLogOnce(
                """
                GtkBackend on Windows does not apply geometric effects: GTK 4 renders \
                a transformed widget as a flat hotpink rectangle, losing its content. \
                offset, rotationEffect, scaleEffect and transformEffect draw untransformed.
                """
            )
        #else
            let m = transform.linearTransform
            let t = transform.translation
            widget.css.set(
                property: CSSProperty(
                    key: "transform",
                    // CSS matrix order is (a, b, c, d, tx, ty), where
                    // x' = a*x + c*y + tx and y' = b*x + d*y + ty.
                    // SwiftCrossUI stores [x y; z w], so b and c are z and y.
                    value: "matrix(\(m.x), \(m.z), \(m.y), \(m.w), \(t.x), \(t.y))"
                )
            )
        #endif
    }
}
