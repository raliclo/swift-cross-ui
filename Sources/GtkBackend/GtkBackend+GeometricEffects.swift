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
                // RE-MEASURED 2026-09-05, same GTK 4.22.4, and the probe still
                // reproduces: 76,285 pixels of exact rgb(255,105,180), every cell
                // but the identity control a flat rectangle with its content gone.
                // The control is the same app without the probe: 0. So the failure
                // this branch exists to demonstrate has not gone away on its own.
                //
                // WHAT HAS CHANGED IS THE RENDERER, and that is recorded in
                // bugs/Gtk4-bugs.md rather than here: under `GDK_DEBUG=dcomp` GTK
                // realises GskGLRenderer instead of GskCairoRenderer and draws
                // every transform correctly with zero hotpink. `SCUI_GTK_DCOMP=1`
                // makes GtkBackend ask for that itself. So the decline below is a
                // workaround for a renderer choice, NOT for a platform that cannot
                // do it -- whether to make dcomp the default is task #73.
                //
                // 2026-09-05 於同一個 GTK 4.22.4 重新量測，探針依然可重現：76,285 個精確為
                // rgb(255,105,180) 的像素，除 identity 對照格外每一格都是內容盡失的平面矩形；
                // 對照組（同一支 app 未開探針）為 0。因此這個分支所要展示的失敗並未自行消失。
                //
                // 真正改變的是 renderer，該事實記於 bugs/Gtk4-bugs.md 而非此處：在
                // `GDK_DEBUG=dcomp` 之下，GTK 會實作 GskGLRenderer 而非 GskCairoRenderer，
                // 並正確繪出每一個變換、零個 hotpink。`SCUI_GTK_DCOMP=1` 即是讓 GtkBackend 自行
                // 要求該設定的開關。因此下方的「拒絕」是對某個 renderer 選擇的權宜之計，**而非**
                // 對一個做不到此事的平台——是否讓 dcomp 成為預設，是任務 #73。
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
            // BOTH HALVES RE-MEASURED 2026-09-05, because that sentence was more
            // than a week old and had no capture behind it on this machine. All
            // three of the Windows track's targets were run:
            //
            //   Win-WinUI   every transform correct   p40-winui-20260905-105537.png
            //   WSL-gtk4    every transform correct   p40-wsl.png
            //   Win-gtk4    nothing transformed       p40-win-20260905-105055.png
            //
            // The Win-gtk4 figure is not a judgement by eye: each of the seven
            // tiles was diffed against the control cell and came back at ZERO
            // differing pixels, with the diff itself controlled -- the same crop
            // shifted five pixels reports 1246, and against blank background
            // 6443. So the decline below is working exactly as written, and the
            // other two targets show the protocol is fine.
            //
            // 兩半皆於 2026-09-05 重新量測，因為上面那句話已超過一週，且在本機沒有任何擷圖佐證。
            // Windows 軌的三個目標全部執行：
            //
            //   Win-WinUI   每個變換皆正確
            //   WSL-gtk4    每個變換皆正確
            //   Win-gtk4    什麼都沒被變換
            //
            // Win-gtk4 那一項不是肉眼判斷：七個方塊逐一與對照格做像素差異比對，結果皆為**零**個
            // 相異像素，而該比對本身有對照——同一裁切區平移五像素得到 1246，對空白背景得到 6443。
            // 因此下方的「拒絕」正如其所寫地運作著，而另外兩個目標證明 protocol 本身沒有問題。
            //
            // GTK 4 在 Windows 上完全無法繪製被變換過的 widget，因此此處選擇「宣告 conformance 但拒絕
            // 執行」，而非產出無法閱讀的畫面。
            //
            // WinUIBackend 實作了同一個 protocol 且確實能繪製：旋轉、縮放與位移在該處的 P40 中都正確
            // 顯示。因此 protocol 本身是健全的，這是 GTK on Windows 這一側的缺口，而非設計問題。
            // SINCE 2026-09-05 THIS DECLINE IS THE EXCEPTION, NOT THE RULE.
            // Direct Composition is on by default, GTK realises GskGLRenderer,
            // and the transform is applied through the same CSS path Linux uses
            // -- see below. What remains here is the software fallback, which is
            // a different renderer with a different capability, not a platform
            // that cannot do it.
            //
            // Three things land here: `-GPU 0`, an explicit `GDK_DISABLE=gl`,
            // and a machine with no hardware display adapter. Each leaves GTK on
            // GskCairoRenderer, which paints a transformed subtree as flat
            // hotpink and loses its content entirely. Declining still beats
            // applying it there: an untransformed view is legible and clickable;
            // a hotpink rectangle is neither.
            //
            // 自 2026-09-05 起，此處的拒絕是**例外而非常態**。Direct Composition 已預設開啟，
            // GTK 會實作 GskGLRenderer，而變換則透過與 Linux 相同的 CSS 路徑套用——見下方。
            // 留在此處的是軟體退路，那是「另一個能力不同的繪製器」，而不是「一個做不到此事的平台」。
            //
            // 有三種情況會走到這裡：`-GPU 0`、明確設定的 `GDK_DISABLE=gl`，以及沒有硬體顯示
            // 介面卡的機器。每一種都會讓 GTK 留在 GskCairoRenderer 上，而它會把被變換的子樹畫成
            // 平面 hotpink 並完全失去其內容。在那裡，拒絕仍然勝過套用：未經變換的 view 仍可閱讀、
            // 仍可點擊，而一片 hotpink 兩者皆非。
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

    /// Writes the transform as a CSS `matrix()`, which is how both platforms
    /// apply it now.
    ///
    /// Extracted 2026-09-05 when Windows stopped declining by default. It was
    /// duplicated for a while: the Windows copy lived inside the probe that
    /// existed only to make the acceptance test in bugs/Gtk4-bugs.md able to
    /// fire, and the Linux copy was the real implementation. Two copies of a
    /// matrix convention is two chances to get the argument order wrong in one
    /// of them, and the wrong order is not a crash -- it is a shear where a
    /// rotation was asked for.
    ///
    /// 把變換寫成 CSS 的 `matrix()`，這是現在兩個平台共同的套用方式。
    ///
    /// 於 2026-09-05、Windows 不再預設拒絕時抽出。它曾經重複過一段時間：Windows 那份存在於
    /// 「只為了讓 bugs/Gtk4-bugs.md 的驗收測試能夠成立」的探針之內，Linux 那份才是真正的實作。
    /// 同一套矩陣慣例存在兩份，就是兩次「其中一份把引數順序寫錯」的機會，而順序寫錯不會當機
    /// ——它會在你要求旋轉的地方給你一個錯切。
    private func applyTransformCSS(
        _ transform: SwiftCrossUI.AffineTransform,
        to widget: Widget
    ) {
        let m = transform.linearTransform
        let t = transform.translation
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
