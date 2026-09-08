import CGtk

extension Popover {
    /// Sets the widget shown inside the popover.
    ///
    /// The caller must keep its own reference to `child`: GTK owns the
    /// GObject from here on, but the Swift wrapper owns the child's signal
    /// handlers, and those go away with it.
    public func setChild(_ child: Widget?) {
        gtk_popover_set_child(castedPointer(), child?.widgetPointer)
    }

    /// Closes the popover, as clicking outside it or pressing Escape does.
    public func popDown() {
        gtk_popover_popdown(castedPointer())
    }

    /// Attaches the popover to `anchor` and shows it there.
    ///
    /// The two calls belong together. `gtk_popover_popup` on a popover with no
    /// parent shows nothing at all -- GTK4 removed `gtk_popover_set_relative_to`
    /// and a popover is now an ordinary child of the widget it points at, so
    /// `gtk_widget_set_parent` *is* the anchoring step, not setup for it.
    ///
    /// Must be called at most once per popover. `gtk_widget_set_parent` on a
    /// widget that already has a parent is a GTK critical, and the shape of the
    /// bug it produces -- a warning on stderr and a popover that never appears
    /// again -- reads as "popovers stopped working" rather than as a double
    /// parent.
    ///
    /// - Parameter anchor: The widget to attach the popover to.
    ///
    /// 將 popover 附著於 `anchor` 並在該處顯示。
    ///
    /// 這兩個呼叫是一體的。對一個沒有 parent 的 popover 呼叫 `gtk_popover_popup` 什麼也不會顯示
    /// ——GTK4 移除了 `gtk_popover_set_relative_to`，popover 現在就是它所指向之 widget 的一個普通
    /// 子元件，因此 `gtk_widget_set_parent` **就是**那個錨定步驟，而不是它的前置準備。
    ///
    /// 每個 popover 最多只能呼叫一次。對已有 parent 的 widget 呼叫 `gtk_widget_set_parent` 會產生
    /// GTK critical，而它造成的 bug 形態——stderr 上一則警告、加上再也不出現的 popover——讀起來像是
    /// 「popover 壞掉了」，而不像「設了兩次 parent」。
    ///
    /// - Parameter anchor: 要附著的 widget。
    public func popUp(anchoredTo anchor: Widget) {
        gtk_widget_set_parent(widgetPointer, anchor.widgetPointer)
        gtk_popover_popup(castedPointer())
    }

    /// Detaches the popover from the widget it was anchored to.
    ///
    /// The counterpart to ``popUp(anchoredTo:)``, and not optional. A popover
    /// attached with `gtk_widget_set_parent` stays a child of its anchor after
    /// it pops down; dropping the Swift reference does not detach it, so an
    /// anchor that opens a popover repeatedly accumulates one hidden child per
    /// opening.
    ///
    /// 將 popover 自其錨定的 widget 上卸下。
    ///
    /// ``popUp(anchoredTo:)`` 的對應操作，且並非可有可無。以 `gtk_widget_set_parent` 附著的
    /// popover，在收起之後仍是其錨點的子元件；放掉 Swift 端的參考並不會卸下它，因此一個反覆開啟
    /// popover 的錨點，每開一次就會累積一個隱藏的子元件。
    public func removeFromAnchor() {
        gtk_widget_unparent(widgetPointer)
    }
}
