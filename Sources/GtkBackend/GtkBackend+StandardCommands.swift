import CGtk
import Foundation
import Gtk
import SwiftCrossUI

/// The standard commands on GTK, for the menus ``Scene/enableMenu(_:)`` turns on.
///
/// GTK has no menu of its own to borrow these from, so each is carried out here.
/// The editing commands go to the focused widget as the actions GTK's text
/// widgets install -- `clipboard.cut`, `text.undo` and the rest -- which is how
/// GTK's own context menu reaches them; a widget without the action ignores it.
///
/// Left out, because GTK has nothing to do for them: Services, Hide, Hide Others
/// and Show All are macOS's, and there is no help viewer to open.
///
/// GTK 上的標準指令，供 ``Scene/enableMenu(_:)`` 打開的選單使用。GTK 沒有自己的選單可以借用，所以每一項都在這裡執行。
/// 編輯指令以 GTK 文字元件所安裝的 action(`clipboard.cut`、`text.undo` 等)送給聚焦的 widget,GTK 自己的內容選單
/// 也是這樣呼叫它們;沒有該 action 的 widget 會忽略。沒有納入的:Services、Hide、Hide Others、Show All 是 macOS 的概念，
/// 而這裡沒有說明檢視器可以開啟。
extension GtkBackend: BackendFeatures.StandardCommands {
    public func hasStandardCommand(_ command: StandardCommand) -> Bool {
        switch command {
            case .services, .hide, .hideOthers, .showAll, .help: false
            default: true
        }
    }

    public func performStandardCommand(_ command: StandardCommand) {
        let active = windows.first(where: \.isActive) ?? windows.first
        func pointer(_ window: Gtk.Window) -> UnsafeMutablePointer<GtkWindow> {
            UnsafeMutableRawPointer(window.widgetPointer).assumingMemoryBound(to: GtkWindow.self)
        }
        func send(_ action: String) {
            guard let active, let focus = gtk_window_get_focus(pointer(active)) else { return }
            // The `_variant` form: `gtk_widget_activate_action` is variadic and Swift cannot call it.
            // 用 `_variant` 版本:`gtk_widget_activate_action` 是可變參數函式，Swift 無法呼叫。
            _ = gtk_widget_activate_action_variant(focus, action, nil)
        }
        switch command {
            case .undo: send("text.undo")
            case .redo: send("text.redo")
            case .cut: send("clipboard.cut")
            case .copy: send("clipboard.copy")
            case .paste: send("clipboard.paste")
            case .delete: send("selection.delete")
            case .selectAll: send("selection.select-all")
            case .close: active?.close()
            case .closeAll: for window in windows { window.close() }
            case .minimize:
                if let active { gtk_window_minimize(pointer(active)) }
            case .zoom:
                guard let active else { return }
                if gtk_window_is_maximized(pointer(active)) != 0 {
                    gtk_window_unmaximize(pointer(active))
                } else {
                    gtk_window_maximize(pointer(active))
                }
            case .bringAllToFront: for window in windows { window.present() }
            case .quit: gtkApp.quit()
            case .about:
                let name = ProcessInfo.processInfo.processName
                let dialog = gtk_about_dialog_new()
                name.withCString {
                    gtk_about_dialog_set_program_name(OpaquePointer(dialog), $0)
                }
                if let active {
                    gtk_window_set_transient_for(
                        UnsafeMutableRawPointer(dialog)?.assumingMemoryBound(to: GtkWindow.self),
                        pointer(active))
                }
                gtk_window_present(
                    UnsafeMutableRawPointer(dialog)?.assumingMemoryBound(to: GtkWindow.self))
            case .newWindow, .services, .hide, .hideOthers, .showAll, .help:
                // New Window is opened by the framework; the rest are not offered.
                // 「New Window」由框架開啟;其餘不提供。
                break
        }
    }
}
