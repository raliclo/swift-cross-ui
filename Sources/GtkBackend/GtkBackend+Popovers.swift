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
extension GtkBackend: BackendFeatures.Popovers {
    /// A `GtkPopover` plus the bookkeeping GTK does not do for us.
    ///
    /// Three things live here rather than on the `GtkPopover`:
    ///
    /// - **A strong reference to the content widget.** `setChild` says so in as
    ///   many words: GTK owns the GObject, but the Swift wrapper owns the
    ///   child's signal handlers, and those die with it. Without this field a
    ///   popover's buttons stop responding as soon as ARC gets to the wrapper.
    /// - **Whether the popover is still parented.** `removeFromAnchor` must run
    ///   exactly once, and there are two paths to a closed popover -- the user
    ///   clicking away, and `dismissPopover` -- which can both fire for a single
    ///   opening.
    /// - **Which of those two paths this is.** `closed` fires either way, and
    ///   the contract on `dismissPopover` is that it must *not* call `onDismiss`.
    ///
    /// 一個 `GtkPopover`，外加 GTK 不會替我們做的記帳工作。
    ///
    /// 有三樣東西放在此處而非放在 `GtkPopover` 上：
    ///
    /// - **對內容 widget 的強參考。** `setChild` 已經把話說得很清楚：GObject 歸 GTK 所有，但子元件
    ///   的 signal handler 歸 Swift wrapper 所有，而後者會隨 wrapper 一同消失。少了這個欄位，
    ///   popover 裡的按鈕會在 ARC 回收 wrapper 的那一刻起停止回應。
    /// - **popover 是否仍被 parent 著。** `removeFromAnchor` 必須恰好執行一次，而通往「已關閉的
    ///   popover」有兩條路——使用者點擊外部，以及 `dismissPopover`——兩者可能在同一次開啟中都觸發。
    /// - **這一次走的是哪一條路。** 兩種情況下 `closed` 都會觸發，而 `dismissPopover` 的約定是
    ///   它**不得**呼叫 `onDismiss`。
    @MainActor
    public final class Popover {
        let popover: Gtk.Popover
        /// Held for its signal handlers. See the type's documentation.
        /// 為其 signal handler 而持有。見本型別的文件。
        let content: Gtk.Widget
        var onDismiss: (() -> Void)?
        var isAnchored = false
        var isProgrammaticDismissal = false

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
            popover.closed = { [weak self] _ in
                guard let self else { return }
                self.detach()

                let wasProgrammatic = self.isProgrammaticDismissal
                self.isProgrammaticDismissal = false
                guard !wasProgrammatic else { return }
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
        attachmentEdge: Edge,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss

        // GTK's `position` names the side of the anchor the popover appears on,
        // which is the same thing `attachmentEdge` names. GTK still flips it
        // when the requested side would leave the monitor, and that flip is
        // wanted -- an off-screen popover honours the request and shows nothing.
        // GTK 的 `position` 指的是 popover 出現在錨點的哪一側，與 `attachmentEdge` 所指相同。
        // 當所請求的一側會超出螢幕時 GTK 仍會翻轉它，而那個翻轉是我們要的——一個跑到螢幕外的
        // popover 遵守了請求，卻什麼也沒顯示。
        popover.popover.position = switch attachmentEdge {
            case .top: .top
            case .bottom: .bottom
            case .leading: .left
            case .trailing: .right
        }

        popover.content.setSizeRequest(width: size.x, height: size.y)

        // Only when asked. A GTK popover is themed -- it has its own background,
        // border, shadow and arrow, all drawn by the theme -- and overriding the
        // background unconditionally would replace all of that with a flat
        // rectangle. This is the same mistake `updatePopoverMenu` was measured
        // making on P20 (see GtkBackend.swift), where the backend's own
        // rgb(44,44,44) stood in for whatever the user's theme had chosen.
        // 只在被要求時才設定。GTK 的 popover 是有主題的——它有自己的背景、邊框、陰影與尖角，全部
        // 由主題繪製——而無條件覆寫背景會把這一切換成一塊扁平的矩形。這正是 `updatePopoverMenu`
        // 曾在 P20 上被實測到犯下的同一個錯誤（見 GtkBackend.swift），當時 backend 自己的
        // rgb(44,44,44) 取代了使用者主題所選定的顏色。
        if let backgroundColor {
            popover.popover.cssProvider.loadCss(
                from: """
                    contents {
                        background: \(CSSProperty.rgba(backgroundColor.gtkColor));
                    }
                    """
            )
        } else {
            popover.popover.cssProvider.loadCss(from: "")
        }
    }

    public func showPopover(_ popover: Popover, relativeTo widget: Widget, window: Window) {
        popover.isAnchored = true
        popover.popover.popUp(anchoredTo: widget)
    }

    public func dismissPopover(_ popover: Popover) {
        popover.isProgrammaticDismissal = true
        popover.popover.popDown()
        // `popDown` animates, and `closed` arrives at the end of it, so the
        // detach happens in the handler rather than here.
        // `popDown` 有動畫，而 `closed` 在動畫結束時才送達，因此卸下的動作在 handler 中進行，
        // 不在此處。
    }
}
