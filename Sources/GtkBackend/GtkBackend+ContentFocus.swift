import CGtk
import Gtk

/// The widget the Edit menu's standard commands act on: the window's focus,
/// unless that focus is in the menu bar, in which case the last focus that
/// was not.
///
/// Clicking a GtkPopoverMenuBar item moves the window's focus onto the item
/// and leaves it there after the menu closes. Every standard edit command
/// went to `gtk_window_get_focus`, so Select All, Copy, Cut, Paste, Delete,
/// Undo and Redo all reached the GtkPopoverMenuBarItem and did nothing --
/// measured on Windows GTK with P92, 2026-10-21, by a log in
/// `performStandardCommand` (focus=GtkPopoverMenuBarItem for every command)
/// and by the user clicking Edit > Select All, Copy and Delete by hand. macOS
/// never showed it: there GTK's menus are the native menu, which takes no focus.
///
/// So each window with a menu bar remembers, weakly, its last focus outside
/// the menu bar (`notify::focus-widget`); a widget that goes away is simply
/// forgotten, never dangled.
///
/// Edit 選單標準指令作用的 widget:視窗的焦點；若焦點在選單列裡，就用最後一個不在選單列裡的焦點。點
/// GtkPopoverMenuBar 的項目會把視窗焦點移到該項目上，選單關閉後也不還回去。每個標準編輯指令都送給
/// `gtk_window_get_focus`,於是全選、複製、剪下、貼上、刪除、復原、重做全都送到 GtkPopoverMenuBarItem,什麼都沒做——
/// 2026-10-21 於 Windows GTK 以 P92 實測(`performStandardCommand` 裡的紀錄：每個指令都是 focus=GtkPopoverMenuBarItem),
/// 使用者手動點 Edit > Select All、Copy、Delete 也一樣。macOS 從未出現：那裡 GTK 的選單是原生選單，不拿焦點。因此有選單列
/// 的每個視窗都以弱參考記住它在選單列以外的最後焦點(`notify::focus-widget`);消失的 widget 只會被遺忘，不會變成懸空指標。
enum GtkContentFocus {
    private static let dataKey = "scui-content-focus"

    /// Starts remembering the content focus of `window`. Idempotent.
    /// 開始記住 `window` 的內容焦點。重複呼叫無妨。
    static func track(_ window: UnsafeMutablePointer<GtkWindow>) {
        let object = UnsafeMutableRawPointer(window)
        guard g_object_get_data(object.assumingMemoryBound(to: CGtk.GObject.self), dataKey) == nil
        else { return }

        let reference = UnsafeMutablePointer<GWeakRef>.allocate(capacity: 1)
        g_weak_ref_init(reference, nil)
        g_object_set_data_full(
            object.assumingMemoryBound(to: CGtk.GObject.self),
            dataKey,
            UnsafeMutableRawPointer(reference),
            { pointer in
                guard let pointer else { return }
                let reference = pointer.assumingMemoryBound(to: GWeakRef.self)
                g_weak_ref_clear(reference)
                reference.deallocate()
            }
        )

        let callback:
            @convention(c) (
                UnsafeMutableRawPointer,
                UnsafeMutableRawPointer,
                UnsafeMutableRawPointer
            ) -> Void = { window, _, data in
                let focus = gtk_window_get_focus(window.assumingMemoryBound(to: GtkWindow.self))
                guard let focus, !GtkContentFocus.isInMenuBar(focus) else { return }
                g_weak_ref_set(data.assumingMemoryBound(to: GWeakRef.self), UnsafeMutableRawPointer(focus))
            }
        g_signal_connect_data(
            object,
            "notify::focus-widget",
            unsafeBitCast(callback, to: GCallback.self),
            UnsafeMutableRawPointer(reference),
            nil,
            GConnectFlags(rawValue: 0)
        )
    }

    /// The widget an edit command should go to in `window`.
    /// `window` 中編輯指令應送往的 widget。
    static func target(in window: UnsafeMutablePointer<GtkWindow>) -> UnsafeMutablePointer<GtkWidget>? {
        let focus = gtk_window_get_focus(window)
        if let focus, !isInMenuBar(focus) { return focus }
        let object = UnsafeMutableRawPointer(window).assumingMemoryBound(to: CGtk.GObject.self)
        guard let stored = g_object_get_data(object, dataKey) else { return focus }
        // `g_weak_ref_get` returns a new reference; the widget is still owned by
        // its window, so the extra one is dropped at once.
        // `g_weak_ref_get` 回傳新的參考；widget 仍由視窗持有，所以多出的那個立刻釋放。
        guard let remembered = g_weak_ref_get(stored.assumingMemoryBound(to: GWeakRef.self))
        else { return focus }
        g_object_unref(remembered)
        return remembered.assumingMemoryBound(to: GtkWidget.self)
    }

    /// Whether `widget` is the menu bar or inside it (CSS node `menubar`).
    /// `widget` 是否為選單列或在其中(CSS 節點 `menubar`)。
    static func isInMenuBar(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
        var current: UnsafeMutablePointer<GtkWidget>? = widget
        while let node = current {
            if String(cString: gtk_widget_get_css_name(node)) == "menubar" { return true }
            current = gtk_widget_get_parent(node)
        }
        return false
    }
}
