import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// The work is in ``Gtk/ScrolledWindow/scroll(to:anchor:)``, and it is there
    /// rather than here for the reason `castedPointer` and `addSignal` both
    /// taught this repository in the same week: raw GTK belongs in the `Gtk`
    /// module and a backend gets a typed API. Calling
    /// `gtk_adjustment_set_value` from here would compile -- `opaquePointer` is
    /// public -- and it would be the fourth instance of the same layering
    /// mistake.
    ///
    /// **UNVERIFIED.** GtkBackend is built and run on the Windows machine in
    /// this project's split, so this file has been compiled by nobody. What to
    /// check first: that `gtk_widget_compute_point` returns the child's offset
    /// relative to the SCROLLED WINDOW rather than to its viewport -- if it is
    /// the viewport, the value already has the current scroll subtracted and
    /// adding `current` in `setAdjustment` doubles it.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// 實際的工作在 ``Gtk/ScrolledWindow/scroll(to:anchor:)``,而它在那裡而不在此處,理由正是
    /// `castedPointer` 與 `addSignal` 在同一週教給這個倉庫的那一件事:原始 GTK 屬於 `Gtk` 模組,
    /// 而 backend 拿到的是型別化的 API。從此處呼叫 `gtk_adjustment_set_value` 會編得過——
    /// `opaquePointer` 是 public 的——而那會是同一個分層錯誤的第四次。
    ///
    /// **未經驗證。** 在本專案的分工中,GtkBackend 是在 Windows 機器上建置與執行的,因此這個檔案
    /// 沒有被任何人編譯過。應優先檢查的是:`gtk_widget_compute_point` 回傳的子元件位移,究竟是相對於
    /// **scrolled window** 還是相對於它的 viewport——若是後者,該值已經扣掉了目前的捲動量,而
    /// `setAdjustment` 中再加上 `current` 會讓它變成兩倍。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        guard let container = scrollView as? ScrolledWindow else { return }
        container.scroll(
            to: child,
            anchor: anchor.map { (x: Double($0.x), y: Double($0.y)) }
        )
    }
}
