#if os(macOS)
    import AppKit
    import CGtk
    import GtkCHelpers
    import Gtk

    extension GtkBackend {
        /// Tags a GTK window's NSWindow as sRGB, which GTK does not do.
        ///
        /// Without it GTK's pixels are shown in the display's colour space: on a
        /// wide-gamut display every colour comes out more saturated than the same
        /// value on AppKitBackend. The measurement is beside
        /// `scui_window_native_macos` in gtk_helpers.h (queue item 16, 2026-10-14).
        /// In its own file so that AppKit is imported here only.
        ///
        /// 把 GTK 視窗的 NSWindow 標記為 sRGB,GTK 自己不做這件事。沒有它時，GTK 的像素以螢幕的色彩空間
        /// 顯示：在廣色域螢幕上，每個顏色都比 AppKitBackend 上同樣的值更飽和。量測記在 gtk_helpers.h 中
        /// `scui_window_native_macos` 旁(queue 第 16 項,2026-10-14)。放在獨立檔案，讓只有這裡 import AppKit。
        func tagColourSpace(ofWindow window: Window) {
            guard let native = scui_window_native_macos(window.widgetPointer) else { return }
            let nsWindow = Unmanaged<NSWindow>.fromOpaque(native).takeUnretainedValue()
            nsWindow.colorSpace = .sRGB
        }
    }
#endif
