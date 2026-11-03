#if os(macOS)
    import AppKit
    import CGtk
    import GtkCHelpers
    import Gtk

    /// The window behaviours GTK does not carry to the NSWindow on macOS, where
    /// the titlebar is AppKit's own (GTK 4.24's Quartz backend gives the window
    /// a native titlebar: style mask titled|closable|miniaturizable|resizable,
    /// no `csd` class).
    ///
    /// Measured 2026-11-03 with a GTK 4.24.1 probe on this Mac:
    /// - `gtk_window_set_deletable(FALSE)` leaves `.closable` in the style mask
    ///   and the close button enabled -- the FIXME this replaces.
    /// - GTK has no minimize property at all.
    /// - Clearing `.closable` or `.miniaturizable` survives GTK's relayouts and
    ///   its own `resizable` changes, which only touch `.resizable`.
    /// - `contentMaxSize` set once is put back to FLT_MAX by GTK at its next
    ///   layout, but set again from the surface's `layout` signal it held through
    ///   default-size changes, `resizable` toggles and a frame change.
    ///
    /// In its own file so that AppKit is imported here only.
    ///
    /// macOS 上 GTK 沒有帶到 NSWindow 的視窗行為；那裡的 titlebar 是 AppKit 自己的(GTK 4.24 的 Quartz backend
    /// 給視窗原生 titlebar:style mask 為 titled|closable|miniaturizable|resizable,沒有 `csd` class)。
    ///
    /// 2026-11-03 在這台 Mac 上以 GTK 4.24.1 探針實測:
    /// - `gtk_window_set_deletable(FALSE)` 讓 style mask 保留 `.closable`,關閉鈕仍可按——即此處取代的 FIXME。
    /// - GTK 根本沒有最小化屬性。
    /// - 清除 `.closable` 或 `.miniaturizable` 之後，經過 GTK 的重新排版與它自己的 `resizable` 變更(只動 `.resizable`)
    ///   都會保留。
    /// - 只設一次的 `contentMaxSize` 會在 GTK 下一次排版時被設回 FLT_MAX;但從 surface 的 `layout` signal 再設一次，
    ///   就撐過了 default size 變更、`resizable` 切換與 frame 變更。
    ///
    /// 放在獨立檔案，讓只有這裡 import AppKit。
    extension GtkBackend {
        /// Applies `deletable`, `minimizable` and `maximumContentSize` to the
        /// window's NSWindow. Does nothing before the window is realized, when
        /// there is no NSWindow; `observeNativeWindowChrome` covers that.
        /// 把 `deletable`、`minimizable` 與 `maximumContentSize` 套用到視窗的 NSWindow。視窗 realize 之前沒有
        /// NSWindow,此時什麼都不做;那段由 `observeNativeWindowChrome` 補上。
        static func applyNativeWindowChrome(ofWindow window: Gtk.Window) {
            guard let native = scui_window_native_macos(window.widgetPointer) else { return }
            let nsWindow = Unmanaged<NSWindow>.fromOpaque(native).takeUnretainedValue()

            var mask = nsWindow.styleMask
            if window.deletable {
                mask.insert(.closable)
            } else {
                mask.remove(.closable)
            }
            if window.minimizable {
                mask.insert(.miniaturizable)
            } else {
                mask.remove(.miniaturizable)
            }
            if mask != nsWindow.styleMask {
                nsWindow.styleMask = mask
            }

            // Only while resizable: otherwise GTK pins the maximum to the
            // current size itself. The limit is in content units, and the
            // NSWindow's content view also holds the GTK titlebar or toolbar
            // inside the window, so the difference between the window and its
            // root widget is added.
            // 只在可調整大小時:否則 GTK 自己會把最大值釘在目前尺寸。上限以內容為單位，而 NSWindow 的 content view
            // 還包含視窗內的 GTK titlebar 或 toolbar,所以要加上視窗與其根 widget 之間的差。
            guard window.resizable else { return }
            if let maximum = window.maximumContentSize {
                var chromeWidth = 0
                var chromeHeight = 0
                if let root = window.getChild() as? CustomRootWidget {
                    let rootSize = root.getSize()
                    chromeWidth = max(0, Int(gtk_widget_get_width(window.widgetPointer)) - rootSize.width)
                    chromeHeight = max(0, Int(gtk_widget_get_height(window.widgetPointer)) - rootSize.height)
                }
                nsWindow.contentMaxSize = NSSize(
                    width: CGFloat(maximum.width + chromeWidth),
                    height: CGFloat(maximum.height + chromeHeight)
                )
            } else {
                // GTK's own value for a resizable window.
                // GTK 對可調整大小之視窗所用的值。
                nsWindow.contentMaxSize = NSSize(
                    width: CGFloat(Float.greatestFiniteMagnitude),
                    height: CGFloat(Float.greatestFiniteMagnitude)
                )
            }
        }

        /// Carries the window into the surface's `layout` handler without
        /// keeping it alive.
        /// 把視窗帶進 surface 的 `layout` handler,但不延長其生命週期。
        private final class NativeChromeBox {
            weak var window: Gtk.Window?

            init(_ window: Gtk.Window) {
                self.window = window
            }
        }

        /// Re-applies the chrome after every layout of the window's surface,
        /// because GTK rewrites `contentMaxSize` at each one. Connected once
        /// per surface, marked with `g_object_set_data`, so calling it again is
        /// harmless. Needs the surface, so it runs after `present()`.
        /// 在視窗 surface 的每一次排版之後重新套用，因為 GTK 每次都會改寫 `contentMaxSize`。每個 surface 只連接
        /// 一次(以 `g_object_set_data` 標記),所以重複呼叫無害。需要 surface,因此在 `present()` 之後執行。
        static func observeNativeWindowChrome(ofWindow window: Gtk.Window) {
            guard let surface = gtk_native_get_surface(OpaquePointer(window.widgetPointer)) else {
                return
            }
            let object = UnsafeMutablePointer<CGtk.GObject>(surface)
            let marker = "scui-native-chrome"
            guard g_object_get_data(object, marker) == nil else { return }
            g_object_set_data(object, marker, UnsafeMutableRawPointer(bitPattern: 1))

            let handler:
                @convention(c) (UnsafeMutableRawPointer?, gint, gint, UnsafeMutableRawPointer?) ->
                Void = { _, _, _, data in
                    guard let data else { return }
                    let box = Unmanaged<NativeChromeBox>.fromOpaque(data).takeUnretainedValue()
                    guard let window = box.window else { return }
                    MainActor.assumeIsolated {
                        GtkBackend.applyNativeWindowChrome(ofWindow: window)
                    }
                }
            g_signal_connect_data(
                UnsafeMutableRawPointer(surface),
                "layout",
                unsafeBitCast(handler, to: GCallback.self),
                Unmanaged.passRetained(NativeChromeBox(window)).toOpaque(),
                { data, _ in
                    guard let data else { return }
                    Unmanaged<NativeChromeBox>.fromOpaque(data).release()
                },
                GConnectFlags(rawValue: 0)
            )
            applyNativeWindowChrome(ofWindow: window)
        }
    }
#endif
