import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.GeometricEffects {
    public func createGeometricEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        return container
    }

    /// Deliberately does not transform. See the note below.
    ///
    /// 刻意不套用變換，理由見下方說明。
    // `SwiftCrossUI.AffineTransform` in full where it appears below: Foundation
    // exports a type of the same name.
    public func setGeometricEffect(
        _ transform: SwiftCrossUI.AffineTransform,
        ofWidget widget: Widget
    ) {
        guard transform != .identity else { return }

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
        // Upgrading is not the answer, which was checked rather than assumed:
        // this is GTK 4.22.4, the current stable release, and the Windows and
        // WSL installs are on the same version. GTK's own documentation says a
        // node it cannot render is drawn pink, so the hotpink is GSK reporting
        // the failure in the only way it has -- the finding is what GTK intends
        // to communicate, not a mystery.
        //
        // WinUIBackend implements this same protocol and does render it:
        // rotation, scale and offset all show correctly in P40 there. So the
        // protocol is sound and this is a GTK-side gap, not a design problem.
        //
        // Not separately confirmed under Linux GTK. Same version, so the same
        // result is likely, but it is untested and should be checked before
        // anyone concludes the refusal is needed on both. The gap is recorded in
        // testapp/gtk-silent-noops.md.
        //
        // 升級並非解方，此點經查證而非臆測：這是 GTK 4.22.4，即當前的穩定版，且 Windows 與 WSL 兩邊
        // 安裝的是同一版本。GTK 官方文件載明「無法繪製的節點會被畫成粉紅色」，因此這片 hotpink 正是
        // GSK 以它僅有的方式回報失敗——這個現象是 GTK 有意傳達的訊息，而非什麼謎團。
        //
        // WinUIBackend 實作了同一個 protocol 且確實能繪製：旋轉、縮放與位移在該處的 P40 中都正確
        // 顯示。因此 protocol 本身是健全的，這是 GTK 這一側的缺口，而非設計問題。
        //
        // 尚未在 Linux GTK 上另行確認。版本相同，結果很可能一致，但畢竟未經測試；在有人下結論說
        // 「兩邊都需要這個拒絕」之前，應先實測。
        //
        // GTK 4 在 Windows 上完全無法繪製被變換過的 widget，因此此處選擇「宣告 conformance 但拒絕
        // 執行」，而非產出無法閱讀的畫面。
        //
        // 2026-08-27 以 P40 實測，其失敗是全面性的：變換確實被套用了——方塊有可量測的位移與尺寸
        // 變化——然後整個被變換的子樹被畫成一整塊純色的 hotpink，rgb(255, 105, 180)，該值取樣自
        // 截圖。那是 GSK 對「它拒絕繪製的節點」所用的後備顏色。過程中沒有任何紀錄、也沒有任何警告。
        //
        // 在判定為平台問題之前，已排除四項：機制（CSS `transform: matrix(...)` 與
        // `gtk_fixed_set_child_transform` 兩條互不相干的路徑失敗方式完全相同）、繪製器
        //（GSK_RENDERER=cairo 與預設的 GL 繪製器結果同樣是 hotpink）、本 backend 自身的程式碼
        //（一組「建立容器但只略過變換呼叫」的對照組，七個 P40 方塊全部正常繪製，故容器、modifier
        // 與版面皆無涉）、以及內容（被變換的子樹中僅有一段純 `Text`、無巢狀容器亦無 Color view，
        // 同樣變成 hotpink）。
        //
        // 拒絕執行優於強行套用：未經變換的 view 仍然可讀、仍然可點擊；而一塊 hotpink 矩形已經完全
        // 失去其內容。這是少數「盡力套用」反而不如「什麼都不做但明白告知」的情況。
        //
        // 尚未在 Linux 上驗證。它在該處很可能是正常的——此處是 Windows 的 GTK build——若確實如此，
        // 這裡應改為依平台區分的實作而非一律拒絕。此缺口記錄於 testapp/gtk-silent-noops.md。
        debugLogOnce(
            """
            GtkBackend does not apply geometric effects: GTK 4 on Windows renders \
            a transformed widget as a flat hotpink rectangle, losing its content. \
            offset, rotationEffect, scaleEffect and transformEffect draw untransformed.
            """
        )
    }
}
