import CGtk
import Gtk

/// Where the keyboard starts in a popover menu: as in an NSMenu, nothing is
/// highlighted when the menu opens, the first Down highlights the first item,
/// the first Up the last, and Return with nothing highlighted closes the menu
/// without choosing anything (measured on AppKitBackend with P19, 2026-10-19:
/// Down and Return chose Button item, Up and Return Second button item,
/// Return alone nothing).
///
/// GTK starts one item further on. `gtk_popover_show` focuses the first item
/// when the popover has no focus child (gtkpopover.c), and the item's focus
/// controller makes it the menu's active, selected item (gtkmodelbutton.c,
/// `focus_in_cb`), so the first Down reached the second item. When the popover
/// kept a focus child from its last opening, show focused nothing new, and a
/// reopened P19 menu drew Button item highlighted while one Down chose Second
/// button item: which item a key started from depended on what had happened
/// before (queue item 24(a)).
///
/// So before every opening the focus children inside the menu are cleared,
/// which makes GTK focus the first item every time, and after it that item is
/// drawn unselected. The first key decides: Down selects that item, Return or
/// space closes the menu, and anything else is GTK's own (Up wraps from the
/// first item to the last, as AppKit's does). A pointer that has selected an
/// item by then takes precedence, as on AppKit.
///
/// popover 選單中鍵盤從哪裡開始：與 NSMenu 相同，選單打開時沒有任何項目被標示，第一次 Down 標示第一項、第一次 Up
/// 標示最後一項，什麼都沒標示時按 Return 關閉選單而不選任何東西(2026-10-19 以 P19 在 AppKitBackend 實測:Down 加
/// Return 選了 Button item,Up 加 Return 選了 Second button item,只按 Return 什麼都沒選)。
///
/// GTK 從下一項開始。popover 沒有焦點子元件時，`gtk_popover_show` 讓第一項取得焦點(gtkpopover.c),而該項目的焦點
/// 控制器使它成為選單中作用中、被選取的項目(gtkmodelbutton.c 的 `focus_in_cb`),所以第一次 Down 到的是第二項。popover
/// 保留了上次打開時的焦點子元件時,show 不再讓任何項目取得焦點，重新打開的 P19 選單把 Button item 畫成標示狀態，一次
/// Down 卻選到 Second button item:按鍵從哪一項開始，取決於先前發生過什麼(queue 第 24(a) 項)。
///
/// 因此每次打開之前清除選單內的焦點子元件，使 GTK 每次都讓第一項取得焦點，打開之後把該項畫成未選取。第一個按鍵決定：
/// Down 選取該項，Return 或空白鍵關閉選單，其他按鍵交給 GTK 本身(Up 從第一項繞到最後一項，與 AppKit 相同)。在那之前
/// 指標已選取某一項時，以指標為準，與 AppKit 相同。
final class GtkMenuKeyboardStart {
    private static let dataKey = "scui-menu-keyboard-start"

    private let menu: UnsafeMutablePointer<GtkWidget>
    /// The item GTK focused when the menu opened, drawn unselected until the
    /// first key. / 選單打開時 GTK 讓其取得焦點的項目，在第一個按鍵之前畫成未選取。
    private var waitingItem: UnsafeMutablePointer<GtkWidget>?
    /// Which item the first Down selected, by position among the menu's items:
    /// for Return when nothing else marks one. A position, not the widget --
    /// under X11 on WSLg the menu rebuilt its items between the Down and the
    /// Return, and a pointer kept from the Down named a freed object (its class
    /// read <NULL-class>, P19, 2026-10-21).
    /// 第一次 Down 選取的是哪一項，以它在選單項目中的位置記住，供沒有其他標示時的 Return 使用。記位置而不是 widget——WSLg
    /// 的 X11 下，選單在 Down 與 Return 之間重建了它的項目，從 Down 留下的指標指向已釋放的物件(類別讀到 <NULL-class>,
    /// P19,2026-10-21)。
    private var keyboardIndex: Int?

    private init(menu: UnsafeMutablePointer<GtkWidget>) {
        self.menu = menu
    }

    static func attach(to menu: Gtk.PopoverMenu) {
        let start = GtkMenuKeyboardStart(menu: menu.widgetPointer)
        let keys = EventControllerKey()
        gtk_event_controller_set_propagation_phase(keys.opaquePointer, GTK_PHASE_CAPTURE)
        keys.keyPressed = { [unowned start] _, keyval, _, _ in
            start.keyPressed(Int32(keyval))
        }
        menu.addEventController(keys)

        // +1 here, released by the destroy notify with the menu.
        // 此處 +1,由選單的 destroy notify 釋放。
        g_object_set_data_full(
            menu.gobjectPointer,
            dataKey,
            Unmanaged.passRetained(start).toOpaque(),
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkMenuKeyboardStart>.fromOpaque(pointer).release()
            }
        )
    }

    static func of(_ menu: Gtk.PopoverMenu) -> GtkMenuKeyboardStart? {
        guard let pointer = g_object_get_data(menu.gobjectPointer, dataKey) else { return nil }
        return Unmanaged<GtkMenuKeyboardStart>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Before the menu opens: no focus child anywhere inside it, so GTK
    /// focuses the first item. / 選單打開之前：其中任何地方都沒有焦點子元件，使 GTK 讓第一項取得焦點。
    func willOpen() {
        waitingItem = nil
        keyboardIndex = nil
        clearFocusChildren(of: menu)
    }

    /// After the menu opens: the item GTK focused is drawn unselected.
    /// 選單打開之後:GTK 讓其取得焦點的項目畫成未選取。
    func didOpen() {
        guard let root = gtk_widget_get_root(menu),
            let focus = gtk_root_get_focus(root),
            gtk_widget_is_ancestor(focus, menu) != 0
        else { return }
        gtk_widget_unset_state_flags(focus, GTK_STATE_FLAG_SELECTED)
        waitingItem = focus
    }

    private func keyPressed(_ keyval: Int32) -> Bool {
        // Return, Enter or space on a selected item activates it here rather
        // than leaving it to GTK. Under X11 on WSLg GTK did nothing with it:
        // the Down reached this controller and selected the first item, the
        // Return reached it too and went on to GTK, and P19 logged no click --
        // the menu stayed open, so the file's next "open the menu" closed it and
        // every later key fell on the window (2026-10-21). On macOS and Windows
        // GTK activated the item itself; one activation here is the same thing.
        // 在選取的項目上按 Return、Enter 或空白鍵時，由這裡觸發它，而不交給 GTK。WSLg 的 X11 下 GTK 對它什麼都沒做:
        // Down 到了這個控制器並選取第一項,Return 也到了、再交給 GTK,P19 卻沒有記到點擊——選單沒關，檔案的下一次
        // 「打開選單」把它關掉，之後的每個鍵都落在視窗上(2026-10-21)。macOS 與 Windows 上 GTK 會自己觸發該項目；
        // 在這裡觸發一次是同一件事。
        if waitingItem == nil, Self.activates(keyval), let selected = activeItem(),
            Self.activate(selected)
        {
            return true
        }
        guard let item = waitingItem else { return false }
        waitingItem = nil
        guard !hasSelectedItem(menu) else { return false }
        switch keyval {
            case GDK_KEY_Down, GDK_KEY_KP_Down:
                // The first item as it is now, not the widget remembered at
                // opening: the menu can rebuild its items in between, and under
                // X11 on WSLg it did -- the remembered GtkModelButton was no
                // longer in the menu (its position read -1, P19, 2026-10-21), so
                // selecting and focusing it changed nothing on screen and Return
                // then found nothing to choose.
                // 用此刻的第一項，而不是打開時記下的 widget:選單可能在兩者之間重建項目，WSLg 的 X11 下確實如此——記下的
                // GtkModelButton 已不在選單中(位置讀到 -1,P19,2026-10-21),選取並聚焦它在畫面上毫無作用，之後的 Return
                // 也就找不到可選的項目。
                let first = Self.modelButtons(in: menu).first ?? item
                gtk_widget_set_state_flags(first, GTK_STATE_FLAG_SELECTED, 0)
                keyboardIndex = 0
                gtk_widget_grab_focus(first)
                return true
            case GDK_KEY_Up, GDK_KEY_KP_Up:
                // The last item, chosen here for the same reason as Down's first:
                // left to GTK, Up started from the stale focus and selected
                // nothing under X11 on WSLg (P19, 2026-10-21). On macOS and
                // Windows GTK wrapped to the last item, which this does too.
                // 最後一項，理由與 Down 選第一項相同：交給 GTK 時，Up 從失效的焦點開始，WSLg 的 X11 下什麼都沒選到
                // (P19,2026-10-21)。macOS 與 Windows 上 GTK 會繞到最後一項，這裡也是。
                let items = Self.modelButtons(in: menu)
                guard let last = items.last else { return false }
                gtk_widget_set_state_flags(last, GTK_STATE_FLAG_SELECTED, 0)
                keyboardIndex = items.count - 1
                gtk_widget_grab_focus(last)
                return true
            case GDK_KEY_Return, GDK_KEY_KP_Enter, GDK_KEY_ISO_Enter, GDK_KEY_space, GDK_KEY_KP_Space:
                gtk_popover_popdown(UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkPopover.self))
                return true
            default:
                return false
        }
    }

    /// The item Return activates: the selected one, else the focused one in
    /// the menu, else the one the first Down selected -- under X11 on WSLg the
    /// selected flag was gone by the time Return arrived (2026-10-21).
    /// Return 觸發的項目：選取的那一項，否則是選單中有焦點的那一項，否則是第一次 Down 選取的那一項——WSLg 的 X11 下，
    /// Return 到達時選取標記已經不見了(2026-10-21)。
    private func activeItem() -> UnsafeMutablePointer<GtkWidget>? {
        if let selected = selectedItem(in: menu) { return selected }
        if let root = gtk_widget_get_root(menu), let focus = gtk_root_get_focus(root),
            gtk_widget_is_ancestor(focus, menu) != 0
        {
            return focus
        }
        return keyboardIndex.flatMap { index in
            let items = Self.modelButtons(in: menu)
            return index < items.count ? items[index] : nil
        }
    }

    /// Runs an item the way a click does: through its action, as a
    /// GtkModelButton is a GtkActionable bound to the menu's action. Under X11
    /// on WSLg `gtk_widget_activate` on the selected GtkModelButton chose
    /// nothing (P19, 2026-10-21); the action is what a click reaches.
    /// 以點擊的方式執行一個項目：透過它的 action——GtkModelButton 是綁定在選單 action 上的 GtkActionable。WSLg 的
    /// X11 下對選取的 GtkModelButton 呼叫 `gtk_widget_activate` 什麼都沒選到(P19,2026-10-21);點擊到達的是 action。
    private static func activate(_ item: UnsafeMutablePointer<GtkWidget>) -> Bool {
        let actionable = OpaquePointer(item)
        if g_type_check_instance_is_a(
            UnsafeMutableRawPointer(item).assumingMemoryBound(to: GTypeInstance.self),
            gtk_actionable_get_type()
        ) != 0, let name = gtk_actionable_get_action_name(actionable) {
            return gtk_widget_activate_action_variant(
                item, name, gtk_actionable_get_action_target_value(actionable)
            ) != 0
        }
        return gtk_widget_activate(item) != 0
    }

    /// The menu's GtkModelButtons in tree order.
    /// 選單中的 GtkModelButton,依樹的順序。
    private static func modelButtons(in widget: UnsafeMutablePointer<GtkWidget>) -> [UnsafeMutablePointer<GtkWidget>] {
        var found: [UnsafeMutablePointer<GtkWidget>] = []
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            let instance = UnsafeMutableRawPointer(current).assumingMemoryBound(to: GTypeInstance.self)
            if String(cString: g_type_name_from_instance(instance)) == "GtkModelButton" {
                found.append(current)
            }
            found += modelButtons(in: current)
            child = gtk_widget_get_next_sibling(current)
        }
        return found
    }

    private static func activates(_ keyval: Int32) -> Bool {
        switch keyval {
            case GDK_KEY_Return, GDK_KEY_KP_Enter, GDK_KEY_ISO_Enter, GDK_KEY_space, GDK_KEY_KP_Space: true
            default: false
        }
    }

    private func clearFocusChildren(of widget: UnsafeMutablePointer<GtkWidget>) {
        gtk_widget_set_focus_child(widget, nil)
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            clearFocusChildren(of: current)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    private func hasSelectedItem(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        selectedItem(in: widget) != nil
    }

    private func selectedItem(in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
        if gtk_widget_get_state_flags(widget).rawValue & GTK_STATE_FLAG_SELECTED.rawValue != 0 {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = selectedItem(in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }
}
