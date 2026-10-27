import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// The work is in ``Gtk/ScrolledWindow/scroll(to:anchor:)``, and it is there
    /// rather than here because raw GTK belongs in the `Gtk` module and a
    /// backend gets a typed API. Calling `gtk_adjustment_set_value` from here
    /// would compile -- `opaquePointer` is public -- and would break that
    /// layering.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// 實際的工作在 ``Gtk/ScrolledWindow/scroll(to:anchor:)``,而它在那裡而不在此處,是因為原始 GTK
    /// 屬於 `Gtk` 模組,而 backend 拿到的是型別化的 API。從此處呼叫 `gtk_adjustment_set_value` 會編得過——
    /// `opaquePointer` 是 public 的——卻會打破這個分層。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        guard let container = Self.scrolledWindow(of: scrollView) else { return }
        // Only a container that holds the child scrolls to it. GTK can compute
        // the child's position relative to ANY widget in the window, so without
        // this check every scroll view under a reader moved to the same offset:
        // P58's "left to L30" put the right column at R30 too (2026-10-16).
        // 只有包含該子 view 的容器才捲動。GTK 可以算出子 view 相對於視窗中**任何** widget 的位置，
        // 因此少了這項檢查,reader 底下的每個捲動視圖都會移到同一個偏移:P58 的「left to L30」
        // 也把右欄帶到了 R30(2026-10-16)。
        guard gtk_widget_is_ancestor(child.widgetPointer, container.widgetPointer) != 0 else {
            return
        }
        container.scroll(
            to: child,
            anchor: anchor.map { (x: Double($0.x), y: Double($0.y)) }
        )
    }
}
