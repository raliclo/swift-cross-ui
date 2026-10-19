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
        guard let item = waitingItem else { return false }
        waitingItem = nil
        guard !hasSelectedItem(menu) else { return false }
        switch keyval {
            case GDK_KEY_Down, GDK_KEY_KP_Down:
                gtk_widget_set_state_flags(item, GTK_STATE_FLAG_SELECTED, 0)
                gtk_widget_grab_focus(item)
                return true
            case GDK_KEY_Return, GDK_KEY_KP_Enter, GDK_KEY_ISO_Enter, GDK_KEY_space, GDK_KEY_KP_Space:
                gtk_popover_popdown(UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkPopover.self))
                return true
            default:
                return false
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
        if gtk_widget_get_state_flags(widget).rawValue & GTK_STATE_FLAG_SELECTED.rawValue != 0 {
            return true
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if hasSelectedItem(current) { return true }
            child = gtk_widget_get_next_sibling(current)
        }
        return false
    }
}
