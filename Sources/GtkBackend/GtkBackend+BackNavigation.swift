import Foundation
import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.BackNavigation` on GTK: the keys and mouse button each
/// platform calls Back, on every OS GtkBackend runs on.
///
/// - **Alt+Left** (Option+Left on a Mac keyboard), the Back shortcut of GNOME
///   apps, browsers and Windows Explorer.
/// - **The Back key** -- `GDK_KEY_Back`, X11's `XF86Back`; on Windows, where
///   GDK has no keysym for it, the keycode `VK_BROWSER_BACK`.
/// - **Command-[** on macOS, where Command reaches GTK as `GDK_META_MASK`.
/// - **The mouse's back button**: button 8 under X11 and Wayland, and button 4
///   under GDK's macOS and Windows backends, which number the extra buttons
///   after the first three (`NSEvent.buttonNumber` 3 and `XBUTTON1`) rather
///   than after the X11 wheel buttons. Under X11 and Wayland buttons 4 to 7
///   are the wheel and never reach a click gesture.
///
/// The keys are read in the bubble phase, after the focused widget: a text
/// field that handles Alt+Left itself (moving its cursor by word, say) keeps
/// the key. The mouse buttons are read in the capture phase, since no widget
/// has a use for them, and the press is claimed when it went back.
///
/// GTK 上的 `BackendFeatures.BackNavigation`:GtkBackend 所執行的每個作業系統上，各平台稱為「返回」的按鍵與滑鼠鍵。
///
/// - **Alt+Left**(Mac 鍵盤上的 Option+Left),GNOME app、瀏覽器與 Windows 檔案總管的返回快捷鍵。
/// - **返回鍵**——`GDK_KEY_Back`,即 X11 的 `XF86Back`;Windows 上 GDK 沒有它的 keysym,以 keycode `VK_BROWSER_BACK` 辨認。
/// - macOS 上的 **Command-[**,Command 在那裡以 `GDK_META_MASK` 抵達 GTK。
/// - **滑鼠返回鍵**:X11 與 Wayland 下是 button 8;GDK 的 macOS 與 Windows backend 下是 button 4,它們把額外的按鍵接在
///   前三個之後編號(`NSEvent.buttonNumber` 3 與 `XBUTTON1`),而不是接在 X11 的滾輪按鍵之後。X11 與 Wayland 下
///   button 4 到 7 是滾輪，永遠不會抵達 click gesture。
///
/// 按鍵在 bubble 階段、於聚焦的 widget 之後讀取：自己處理 Alt+Left 的文字欄位(例如逐字移動游標)保有該鍵。
/// 滑鼠鍵在 capture 階段讀取，因為沒有 widget 用得到它們；返回成功時 claim 該次按壓。
///
/// **Sheets** are `GtkBackend.Sheet` windows of their own and take Back the
/// same way with their own handler. While a modal window is transient for a
/// window -- a sheet over it -- that window ignores Back, so Back never reaches
/// under a sheet.
///
/// **The trackpad on macOS** (GtkBackend+BackNavigationMac.swift): GDK's macOS
/// backend translates no `NSEvent.swipe` -- `gdk/macos/gdkmacosdisplay-translate.c`
/// has cases for magnify, rotate and scroll and none for swipe, so
/// `GtkGestureSwipe` never fires there -- and so the three-finger swipe is read
/// from AppKit with a local event monitor. The two-finger swipe arrives as a
/// touchpad scroll with phases, which GDK does deliver.
///
/// **sheet** 是自己的 `GtkBackend.Sheet` 視窗，以同樣方式、用自己的 handler 接下返回。有 modal 視窗以某視窗為 transient
/// parent 時(其上開著 sheet),該視窗忽略返回，因此返回永遠不會穿到 sheet 底下。
///
/// **macOS 上的觸控板**(GtkBackend+BackNavigationMac.swift):GDK 的 macOS backend 不轉譯任何 `NSEvent.swipe`——
/// `gdk/macos/gdkmacosdisplay-translate.c` 有 magnify、rotate 與 scroll 的分支，沒有 swipe 的，所以 `GtkGestureSwipe` 在那裡
/// 永遠不會觸發——因此三指滑動以本地事件監看器從 AppKit 讀取。雙指滑動以帶有階段的觸控板捲動抵達，GDK 確實會遞送。
extension GtkBackend: BackendFeatures.BackNavigation, BackendFeatures.SheetBackNavigation {
    public func setBackNavigationHandler(
        ofWindow window: Window,
        to action: (@MainActor () -> Bool)?
    ) {
        GtkBackNavigation.setHandler(action, of: window)
    }

    public func setBackNavigationHandler(
        ofSheet sheet: Sheet,
        to action: (@MainActor () -> Bool)?
    ) {
        GtkBackNavigation.setHandler(action, of: sheet)
    }
}

@MainActor
enum GtkBackNavigation {
    /// Each window's handler, by the window's widget pointer.
    /// 每個視窗的 handler,以視窗的 widget 指標為鍵。
    private(set) static var handlers: [UnsafeMutableRawPointer: @MainActor () -> Bool] = [:]
    /// The windows whose controllers are attached. 已掛上 controller 的視窗。
    private static var attached: Set<UnsafeMutableRawPointer> = []

    static func setHandler(_ action: (@MainActor () -> Bool)?, of window: Gtk.Window) {
        let key = UnsafeMutableRawPointer(window.widgetPointer)
        handlers[key] = action
        guard action != nil, !attached.contains(key) else { return }
        attached.insert(key)
        attach(to: window, key: key)
    }

    /// Runs the handler of the window at `key`, unless a sheet is up over it.
    /// 執行 `key` 那個視窗的 handler,除非它上面開著 sheet。
    /// Prints `SCUI-BackNavigation: <source>: popped` or `nothing to pop`, so a
    /// run shows which input fired. 印出 `SCUI-BackNavigation: <來源>: popped` 或 `nothing to pop`,讓一次執行看得出是哪個輸入觸發。
    static func goBack(_ key: UnsafeMutableRawPointer, source: String) -> Bool {
        guard let handler = handlers[key] else { return false }
        if hasModalWindow(over: key) {
            log("GTK \(source): ignored, a sheet is over the window")
            return false
        }
        let wentBack = handler()
        log("GTK \(source): \(wentBack ? "popped" : "nothing to pop")")
        return wentBack
    }

    /// One line on stderr, unbuffered, so it survives the app being killed.
    /// stderr 上的一行(不經緩衝),app 被終止也不會遺失。
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("SCUI-BackNavigation: \(message)\n".utf8))
    }

    /// Whether a visible modal window is transient for the window at `key`.
    /// 是否有可見的 modal 視窗以 `key` 那個視窗為 transient parent。
    private static func hasModalWindow(over key: UnsafeMutableRawPointer) -> Bool {
        let toplevels = gtk_window_get_toplevels()
        for index in 0..<g_list_model_get_n_items(toplevels) {
            guard let item = g_list_model_get_item(toplevels, index) else { continue }
            defer { g_object_unref(item) }
            let window = item.assumingMemoryBound(to: GtkWindow.self)
            if gtk_window_get_modal(window) != 0,
               gtk_widget_get_visible(item.assumingMemoryBound(to: GtkWidget.self)) != 0,
               let parent = gtk_window_get_transient_for(window),
               UnsafeMutableRawPointer(parent) == key
            {
                return true
            }
        }
        return false
    }

    /// The mouse buttons GDK reports for a mouse's back button on this OS.
    /// 此作業系統上，GDK 為滑鼠返回鍵回報的按鍵編號。
    private static var backButtons: [guint] {
        #if os(macOS) || os(Windows)
            [4, 8]
        #else
            [8]
        #endif
    }

    /// Which of the Back keys above a key press is, or `nil`.
    ///
    /// GDK on Windows has no keysym for `VK_BROWSER_BACK`: `gdk/win32/gdkkeys-win32.c`
    /// maps `VK_LEFT` and the other special keys in `DEFINE_SPECIAL` and lists no
    /// browser key, so the Back key arrives without `GDK_KEY_Back`. GDK passes
    /// the virtual-key code as the hardware keycode there, which is what is
    /// read on Windows.
    ///
    /// 一次按鍵是上方哪一個返回鍵，或 `nil`。Windows 上的 GDK 沒有 `VK_BROWSER_BACK` 的 keysym:`gdk/win32/gdkkeys-win32.c` 在
    /// `DEFINE_SPECIAL` 中對應了 `VK_LEFT` 等特殊鍵，沒有列出任何瀏覽器鍵，所以返回鍵抵達時沒有 `GDK_KEY_Back`。GDK 在那裡把
    /// virtual-key code 當成 hardware keycode 傳出,Windows 上讀的就是它。
    static func backKeySource(_ keyval: UInt, _ keycode: UInt, _ state: GdkModifierType) -> String? {
        let modifiers = state.rawValue
            & (GDK_SHIFT_MASK.rawValue | GDK_CONTROL_MASK.rawValue | GDK_ALT_MASK.rawValue
                | GDK_SUPER_MASK.rawValue | GDK_META_MASK.rawValue)
        #if os(Windows)
            if keycode == 0xA6 { return "VK_BROWSER_BACK (keycode 0xA6)" }
        #endif
        switch Int32(keyval) {
            case GDK_KEY_Back:
                return "Back key (GDK_KEY_Back)"
            case GDK_KEY_Left, GDK_KEY_KP_Left:
                return modifiers == GDK_ALT_MASK.rawValue ? "Alt+Left" : nil
            case GDK_KEY_bracketleft:
                #if os(macOS)
                    let command = modifiers != 0
                        && modifiers & ~(GDK_META_MASK.rawValue | GDK_SUPER_MASK.rawValue) == 0
                    return command ? "Command-[" : nil
                #else
                    return nil
                #endif
            default:
                return nil
        }
    }

    private static func attach(to window: Gtk.Window, key: UnsafeMutableRawPointer) {
        let keys = EventControllerKey()
        keys.keyPressed = { _, keyval, keycode, state in
            guard let source = backKeySource(keyval, keycode, state) else { return false }
            return goBack(key, source: source)
        }
        window.addEventController(keys)

        for button in backButtons {
            let click = GestureClick()
            gtk_gesture_single_set_button(click.opaquePointer, button)
            gtk_event_controller_set_propagation_phase(click.opaquePointer, GTK_PHASE_CAPTURE)
            click.pressed = { gesture, _, _, _ in
                if goBack(key, source: "mouse button \(button)") {
                    gtk_gesture_set_state(gesture.opaquePointer, GTK_EVENT_SEQUENCE_CLAIMED)
                }
            }
            window.addEventController(click)
        }

        #if os(macOS)
            attachTrackpad(to: window, key: key)
        #endif
    }
}
