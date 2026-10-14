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
/// Services is a submenu saying none apply, Help says there is none, Hide minimizes
/// and Show All brings the windows back; on macOS these go to the application object.
///
/// GTK 上的標準指令，供 ``Scene/enableMenu(_:)`` 打開的選單使用。GTK 沒有自己的選單可以借用，所以每一項都在這裡執行。
/// 編輯指令以 GTK 文字元件所安裝的 action(`clipboard.cut`、`text.undo` 等)送給聚焦的 widget,GTK 自己的內容選單
/// 也是這樣呼叫它們;沒有該 action 的 widget 會忽略。Services 是寫著「沒有可用服務」的子選單，Help 說明沒有說明書，
/// Hide 把視窗最小化、Show All 把它們帶回來;在 macOS 上這些交給 application 物件。
extension GtkBackend: BackendFeatures.StandardCommands {
    public func hasStandardCommand(_ command: StandardCommand) -> Bool {
        switch command {
            // Hide Others needs the other apps' windows, which GTK cannot reach; on macOS the
            // application object can. Elsewhere it is left out -- for the Windows side to add
            // with the platform's own calls.
            // 「Hide Others」需要碰到其他 app 的視窗，GTK 做不到;macOS 上 application 物件可以。其他系統上不提供，
            // 留給 Windows 端用平台自己的呼叫補上。
            case .hideOthers: Self.isDarwin
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
            // A text field's history and a text editor's are the framework's (`TextUndoHistory`).
            // 文字欄位與文字編輯器的歷史都由框架保存(`TextUndoHistory`)。
            case .undo, .redo:
                if let active, let focus = gtk_window_get_focus(pointer(active)),
                   let history = TextUndoHistory.containing(focus)
                {
                    if command == .undo { history.undo() } else { history.redo() }
                } else {
                    send(command == .undo ? "text.undo" : "text.redo")
                }
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
                        pointer(active)
                    )
                }
                gtk_window_present(
                    UnsafeMutableRawPointer(dialog)?.assumingMemoryBound(to: GtkWindow.self)
                )
            case .hide:
                // The app out of the way: macOS hides it; elsewhere every window is minimized,
                // which leaves it reachable, where a hidden window would have no way back.
                // 讓 app 讓開:macOS 上隱藏它;其他系統上把每個視窗最小化，這樣還找得回來，隱藏的視窗則沒有回來的路。
                if !Self.sendToApplication("hide:") {
                    for window in windows { gtk_window_minimize(pointer(window)) }
                }
            case .hideOthers:
                _ = Self.sendToApplication("hideOtherApplications:")
            case .showAll:
                if !Self.sendToApplication("unhideAllApplications:") {
                    for window in windows { window.present() }
                }
            case .help:
                // What AppKit says for an app with no help book.
                // AppKit 對沒有說明書的 app 所說的話。
                let alert = createAlert()
                alert.text = "Help isn’t available for \(ProcessInfo.processInfo.processName)."
                alert.addButton(label: "OK", responseId: 0)
                showAlert(alert, window: active) { [weak self] _ in
                    self?.dismissAlert(alert, window: active)
                }
            case .newWindow, .services:
                // New Window is opened by the framework, and Services is a submenu it draws.
                // 「New Window」由框架開啟，Services 是框架畫的子選單。
                break
        }
    }
}

extension GtkBackend {
    #if canImport(Darwin)
        static let isDarwin = true
    #else
        static let isDarwin = false
    #endif

    /// Sends an action to macOS's application object, where GTK runs on macOS.
    /// Through the Objective-C runtime: GtkBackend does not link AppKit.
    /// 在 macOS 上執行的 GTK,把動作送給 macOS 的 application 物件。經由 Objective-C runtime:GtkBackend 不連結 AppKit。
    static func sendToApplication(_ selector: String) -> Bool {
        #if canImport(Darwin)
            guard let type = NSClassFromString("NSApplication") as? NSObject.Type,
                  let application = type.perform(NSSelectorFromString("sharedApplication"))?
                  .takeUnretainedValue() as? NSObject
            else { return false }
            _ = application.perform(NSSelectorFromString(selector), with: nil)
            return true
        #else
            return false
        #endif
    }
}
