import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// `.popover` for GTK4, built on `GtkPopover`.
///
/// `GtkPopover` is the same primitive the backend's menus already use --
/// `GtkPopoverMenu` is a subclass of it -- but that is where the overlap ends.
/// `PopoverMenus` hands GTK a `GMenuModel`, and a menu model has no way to
/// express a `Slider`. This attaches an ordinary widget instead, via
/// `gtk_popover_set_child`, which is what `GtkPopover` was designed for and what
/// its own documentation recommends over `GtkPopoverMenu` for "dialog-like
/// behavior".
///
/// 為 GTK4 實作的 `.popover`，建構於 `GtkPopover` 之上。
///
/// `GtkPopover` 正是本 backend 的選單所使用的同一個基本元件——`GtkPopoverMenu` 是它的子類別
/// ——但兩者的共通點僅止於此。`PopoverMenus` 交給 GTK 的是 `GMenuModel`，而 menu model 無從表達
/// 一個 `Slider`。此處改為透過 `gtk_popover_set_child` 附上一個普通的 widget，那正是 `GtkPopover`
/// 被設計來承擔的用途，也正是它自己的文件在談到「dialog-like behavior」時所建議者。
extension GtkBackend {
    /// A `GtkPopover` plus the bookkeeping GTK does not do for us.
    ///
    /// Two things live here rather than on the `GtkPopover`:
    ///
    /// - **A strong reference to the content widget.** `setChild` says so in as
    ///   many words: GTK owns the GObject, but the Swift wrapper owns the
    ///   child's signal handlers, and those die with it. Without this field a
    ///   popover's buttons stop responding as soon as ARC gets to the wrapper.
    /// - **Whether the popover is still parented.** `removeFromAnchor` must run
    ///   exactly once, and there are two paths to a closed popover -- the user
    ///   clicking away, and `dismissPopover` -- which can both fire for a single
    ///   opening.
    ///
    /// A third field used to live here -- `isProgrammaticDismissal`, recording
    /// WHICH of those two paths a `closed` signal came from, so that
    /// `dismissPopover` could suppress the caller's `onDismiss:`. It is gone.
    /// SwiftUI runs `onDismiss:` when the presentation ends however it ended,
    /// AppKitBackend already did that (`NSPopover.performClose` runs
    /// `popoverDidClose`), and keeping the flag left three shipped backends
    /// disagreeing about one callback. Distinguishing the paths is no longer
    /// something this type needs to do.
    ///
    /// 一個 `GtkPopover`，外加 GTK 不會替我們做的記帳工作。
    ///
    /// 有兩樣東西放在此處而非放在 `GtkPopover` 上：
    ///
    /// - **對內容 widget 的強參考。** `setChild` 已經把話說得很清楚：GObject 歸 GTK 所有，但子元件
    ///   的 signal handler 歸 Swift wrapper 所有，而後者會隨 wrapper 一同消失。少了這個欄位，
    ///   popover 裡的按鈕會在 ARC 回收 wrapper 的那一刻起停止回應。
    /// - **popover 是否仍被 parent 著。** `removeFromAnchor` 必須恰好執行一次，而通往「已關閉的
    ///   popover」有兩條路——使用者點擊外部，以及 `dismissPopover`——兩者可能在同一次開啟中都觸發。
    ///
    /// 此處原本還有第三個欄位——`isProgrammaticDismissal`，用來記錄某次 `closed` 是從上述兩條路的
    /// 哪一條來的，好讓 `dismissPopover` 能壓住呼叫端的 `onDismiss:`。它已經被移除。SwiftUI 是
    /// 「無論 presentation 以何種方式結束，`onDismiss:` 都會執行」，AppKitBackend 本來就是這樣做的
    /// （`NSPopover.performClose` 會執行 `popoverDidClose`），而保留該旗標的結果，是三個已發布的
    /// backend 對同一個回呼各說各話。區分那兩條路已不再是本型別需要做的事。
    @MainActor
    public final class Popover {
        let popover: Gtk.Popover
        /// Held for its signal handlers. See the type's documentation.
        /// 為其 signal handler 而持有。見本型別的文件。
        let content: Gtk.Widget
        var onDismiss: (() -> Void)?
        var isAnchored = false

        init(content: Gtk.Widget) {
            self.popover = Gtk.Popover()
            self.content = content
            popover.setChild(content)
            // Light dismiss. A popover is not modal; clicking elsewhere closes
            // it, and that click is the `onDismiss` the modifier is waiting for.
            // 點擊外部即關閉。popover 並非模態；在別處點擊會關閉它，而那一次點擊正是該 modifier
            // 所等待的 `onDismiss`。
            popover.autohide = true
            popover.hasArrow = true
            // `onDismiss` fires on BOTH paths to a closed popover -- the user
            // clicking away, and `dismissPopover`. That matches SwiftUI, where
            // `onDismiss:` runs when the presentation ends however it ended,
            // and it is what AppKitBackend already did, since `NSPopover`'s
            // `performClose` runs `popoverDidClose`. This backend used to
            // suppress the programmatic case behind an `isProgrammaticDismissal`
            // flag, which made three shipped backends disagree about the same
            // callback.
            //
            // Firing on both paths does not loop, and the reason is in
            // `PopoverModifier`: the programmatic branch (`:164`) nils
            // `children.popover` immediately after calling `dismissPopover`, and
            // it is only entered when `isPresented` is ALREADY false. So the
            // `handleDismiss` this closure reaches runs the caller's closure
            // once, clears three fields that are already nil, and writes `false`
            // over a `false` -- no state change, so no further update.
            //
            // `onDismiss` 在通往「已關閉的 popover」的**兩條**路上都會觸發——使用者點擊外部，以及
            // `dismissPopover`。這與 SwiftUI 一致：無論presentation 以何種方式結束，`onDismiss:`
            // 都會執行；這也正是 AppKitBackend 原本的行為，因為 `NSPopover` 的 `performClose`
            // 會執行 `popoverDidClose`。本 backend 過去以 `isProgrammaticDismissal` 旗標壓住
            // 程式化的那一條路，導致三個已發布的 backend 對同一個回呼各說各話。
            //
            // 兩條路都觸發不會造成迴圈，理由在 `PopoverModifier` 裡：程式化分支（`:164`）在呼叫
            // `dismissPopover` 之後立刻把 `children.popover` 設為 nil，而且該分支只有在
            // `isPresented` **已經**為 false 時才會進入。因此本 closure 所抵達的 `handleDismiss`
            // 會執行呼叫端的 closure 一次、把三個已是 nil 的欄位再清一次，並在一個 `false` 上寫入
            // `false`——沒有狀態改變，也就不會再引發下一輪 update。
            popover.closed = { [weak self] _ in
                guard let self else { return }
                self.detach()
                self.onDismiss?()
            }
        }

        func detach() {
            guard isAnchored else { return }
            isAnchored = false
            popover.removeFromAnchor()
        }
    }

    public func createPopover(content: Widget) -> Popover {
        Popover(content: content)
    }

    public func updatePopover(
        _ popover: Popover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss

        popover.content.setSizeRequest(width: size.x, height: size.y)

        // The background is left to the theme, and nothing here overrides it. A
        // GTK popover draws its own background, border, shadow and arrow, all of
        // them themed, and a flat colour painted over the top replaces every one
        // of them with a rectangle. That is the mistake `updatePopoverMenu` was
        // measured making on P20 (see GtkBackend.swift), where the backend's own
        // rgb(44,44,44) stood in for whatever the user's theme had chosen.
        // 背景交給主題，此處不覆寫它。GTK 的 popover 會自行繪製背景、邊框、陰影與尖角，而且全部
        // 都是有主題的；在上頭塗一塊扁平顏色，會把這其中的每一項都換成一個矩形。那正是
        // `updatePopoverMenu` 曾在 P20 上被實測到犯下的錯誤（見 GtkBackend.swift），當時
        // backend 自己的 rgb(44,44,44) 取代了使用者主題所選定的顏色。
    }

    public func presentPopover(_ popover: Popover, relativeTo anchor: Widget, window: Window) {
        popover.isAnchored = true
        // `position` is deliberately not set, so GTK keeps its own default of
        // `.bottom` -- below the anchor, where a popover opened from a button
        // belongs, and the side AppKit asks for with `.maxY`. GTK flips to
        // another side when the requested one would leave the monitor, and that
        // flip is precisely why the side is left to GTK: an edge pinned by this
        // backend would be honoured off the edge of the screen, and a popover
        // nobody can see has shown nothing.
        // 此處刻意不設定 `position`，讓 GTK 保有它自己的預設值 `.bottom`——位於錨點下方，也就是由
        // 按鈕開啟的 popover 該在的位置，與 AppKit 以 `.maxY` 所請求的那一側相同。當所請求的一側
        // 會超出螢幕時，GTK 會把它翻到另一側，而那個翻轉正是「把該選哪一側交給 GTK」的理由：由本
        // backend 釘死的一側會被忠實地遵守到螢幕之外，而一個沒人看得見的 popover 等於什麼都沒顯示。
        popover.popover.popUp(anchoredTo: anchor)
    }

    public func dismissPopover(_ popover: Popover, window: Window) {
        popover.popover.popDown()
        // `popDown` animates, and `closed` arrives at the end of it, so the
        // detach happens in the handler rather than here.
        // `popDown` 有動畫，而 `closed` 在動畫結束時才送達，因此卸下的動作在 handler 中進行，
        // 不在此處。
    }

    public func size(ofPopover popover: Popover) -> SIMD2<Int> {
        // The size request `updatePopover` set, read back with
        // `gtk_widget_get_size_request`. That call returns what was *requested*,
        // not what was allocated, so it answers for a popover that has never
        // been shown -- which an allocation (`gtk_widget_get_allocated_width`)
        // could not, since an unmapped GTK widget has no allocation.
        //
        // GTK returns `-1` on an axis nothing has requested yet, which is the
        // state between `createPopover` and the first `updatePopover`. GTK's own
        // preferred size answers there, rather than letting a negative number
        // reach the caller as if it were a measurement.
        //
        // 由 `updatePopover` 設定的 size request，以 `gtk_widget_get_size_request` 讀回。該呼叫
        // 回傳的是被**請求**的值，而非被配置的值，因此對一個從未顯示過的 popover 它仍答得出來
        // ——而配置（`gtk_widget_get_allocated_width`）做不到，因為尚未 map 的 GTK widget 根本
        // 沒有配置。
        //
        // 在尚無任何請求的軸上，GTK 會回傳 `-1`，那正是 `createPopover` 與第一次 `updatePopover`
        // 之間的狀態。此時改由 GTK 自己的偏好尺寸作答，而不是讓一個負數以「量測結果」的身分傳到
        // 呼叫端手上。
        let requested = popover.content.getSizeRequest()
        guard requested.width >= 0, requested.height >= 0 else {
            let natural = popover.content.getNaturalSize()
            return SIMD2(natural.width, natural.height)
        }
        return SIMD2(requested.width, requested.height)
    }
}
