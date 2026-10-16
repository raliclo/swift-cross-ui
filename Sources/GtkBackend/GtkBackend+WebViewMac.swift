#if os(macOS)
    import AppKit
    import CGtk
    import Foundation
    import GtkCHelpers
    import WebKit

    /// The macOS ``GtkWebEngine``: WebKit itself, kept over the GTK box.
    ///
    /// Homebrew has no WebKitGTK for macOS, so the dlopen route Linux takes
    /// (gtk_webkit.c) found nothing and P27 and P38 showed "WebKitGTK could not
    /// start" (2026-10-16). The engine macOS does have is WebKit.
    ///
    /// **A sibling of GDK's view, not a subview.** GDK's content view hosts its own
    /// layer, and AppKit does not support subviews of a layer-hosting view: added
    /// there, the page loaded (P38 reported the navigation) and never showed.
    ///
    /// macOS 的 ``GtkWebEngine``:WebKit 本身，覆蓋在 GTK box 上。Homebrew 沒有 macOS 版的 WebKitGTK,Linux 的
    /// dlopen 路線找不到任何東西,P27 與 P38 顯示「WebKitGTK could not start」(2026-10-16)。**是 GDK view 的兄弟，
    /// 而不是子視圖**:GDK 的 content view 自己承載 layer,AppKit 不支援 layer-hosting view 的子視圖；放在那裡時頁面
    /// 有載入(P38 回報了導覽)卻從未顯示。
    ///
    /// `@unchecked Sendable`: touched only on GTK's thread, which on macOS is the
    /// main thread WebKit requires. 只在 GTK 的執行緒上被觸碰，在 macOS 上就是 WebKit 要求的主執行緒。
    final class WKWebEngine: GtkWebEngine, @unchecked Sendable {
        var onNavigate: ((URL) -> Void)?
        private var webView: WKWebView?
        private var delegate: NavigationDelegate?
        private var pending: URL?
        private var keyRoot: UInt = 0

        private final class NavigationDelegate: NSObject, WKNavigationDelegate {
            weak var engine: WKWebEngine?
            // Committed, not finished: a page that loads slowly has still been
            // navigated to, as WebView2's SourceChanged reports it on Windows.
            // 以 commit 而非 finish 為準：載入很慢的頁面也已經被導覽到了，與 Windows 上 WebView2 的 SourceChanged 一致。
            func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
                if let url = webView.url { engine?.onNavigate?(url) }
            }
        }

        init() {
            MainActor.assumeIsolated {
                let view = WKWebView(frame: .zero)
                let delegate = NavigationDelegate()
                delegate.engine = self
                view.navigationDelegate = delegate
                view.isHidden = true
                self.webView = view
                self.delegate = delegate
            }
        }

        deinit {
            let view = webView
            MainActor.assumeIsolated { view?.removeFromSuperview() }
        }

        func attach(to host: UnsafeMutablePointer<GtkWidget>) {}

        func show(in root: UnsafeMutablePointer<GtkWidget>, at frame: GtkWebEngineFrame) {
            // By address: a pointer is not Sendable, and this is GTK's thread anyway.
            // 以位址傳入：指標不是 Sendable,而這裡本來就是 GTK 的執行緒。
            let rootAddress = UInt(bitPattern: root)
            MainActor.assumeIsolated {
                guard let webView,
                    let rootWidget = UnsafeMutablePointer<GtkWidget>(bitPattern: rootAddress),
                    let nativeWindow = scui_window_native_macos(rootWidget),
                    let content = Unmanaged<NSWindow>.fromOpaque(nativeWindow).takeUnretainedValue()
                        .contentView,
                    let frameView = content.superview
                else { return }
                // GTK counts y from the top; AppKit from the bottom unless flipped.
                // GTK 的 y 由上往下;AppKit 由下往上，除非是 flipped。
                let inContent = NSRect(
                    x: frame.x,
                    y: content.isFlipped ? frame.y : content.bounds.height - frame.y - frame.height,
                    width: frame.width,
                    height: frame.height
                )
                if webView.superview !== frameView {
                    frameView.addSubview(webView, positioned: .above, relativeTo: content)
                }
                webView.frame = content.convert(inContent, to: frameView)
                if keyRoot != rootAddress {
                    keyRoot = rootAddress
                    routeKeys(on: rootWidget)
                }
                webView.isHidden = false
                if let url = pending {
                    pending = nil
                    webView.load(URLRequest(url: url))
                }
            }
        }

        func hide() {
            let view = webView
            MainActor.assumeIsolated { view?.isHidden = true }
        }

        func navigate(to url: URL) {
            MainActor.assumeIsolated {
                if let webView, webView.superview != nil {
                    webView.load(URLRequest(url: url))
                } else {
                    pending = url
                }
            }
        }

        // MARK: Keys

        /// Hands keys to the page while the page has the focus.
        ///
        /// GDK turns every NSEvent into a GdkEvent and passes the NSEvent on to
        /// `NSApp.sendEvent` -- and from there to the window's first responder --
        /// only when GTK leaves it unhandled. So a focused WKWebView got the keys
        /// GTK happened to ignore and lost the rest: P38's Option-Tab reached the
        /// link, its Return did not (GTK handled the keyDown; only the keyUp came
        /// through), and Navigations reported stayed at 1 (2026-10-16). A capture
        /// phase controller on the GTK window takes a key first; while the first
        /// responder is inside the page, it rebuilds the NSEvent, sends it through
        /// `NSApp`, and marks it handled so GTK does not act on it too.
        ///
        /// A press in the GTK content outside the page hands the first responder
        /// back to GDK's view, so the keys go to GTK again; a press on the page is
        /// forwarded by GDK and WebKit takes the focus itself.
        ///
        /// 頁面有焦點時把按鍵交給頁面。GDK 把每個 NSEvent 轉成 GdkEvent,只有 GTK 沒處理時才把 NSEvent 交給
        /// `NSApp.sendEvent`,再到視窗的 first responder。所以聚焦的 WKWebView 只拿到 GTK 剛好不理的按鍵:P38 的 Option-Tab
        /// 到了連結,Return 沒有(GTK 處理了 keyDown,只有 keyUp 過來),Navigations reported 停在 1(2026-10-16)。GTK 視窗上
        /// capture 階段的控制器先拿到按鍵;first responder 在頁面內時，重建 NSEvent、經 `NSApp` 送出，並標記為已處理，免得
        /// GTK 也動作。在頁面以外的 GTK 內容上按下，會把 first responder 還給 GDK 的 view,按鍵回到 GTK;按在頁面上則由 GDK
        /// 轉送,WebKit 自己取得焦點。
        private final class KeyRoutingBox {
            weak var engine: WKWebEngine?
            init(_ engine: WKWebEngine) { self.engine = engine }
        }

        private func routeKeys(on root: UnsafeMutablePointer<GtkWidget>) {
            let legacy = gtk_event_controller_legacy_new()!
            gtk_event_controller_set_propagation_phase(legacy, GTK_PHASE_CAPTURE)
            gtk_widget_add_controller(root, legacy)
            let callback:
                @convention(c) (
                    UnsafeMutableRawPointer,
                    OpaquePointer,
                    UnsafeMutableRawPointer
                ) -> gboolean = { _, event, data in
                    // Addresses, not pointers, across the isolation boundary.
                    let eventAddress = UInt(bitPattern: event)
                    let boxAddress = UInt(bitPattern: data)
                    return MainActor.assumeIsolated {
                        guard let event = OpaquePointer(bitPattern: eventAddress),
                            let data = UnsafeMutableRawPointer(bitPattern: boxAddress)
                        else { return false }
                        return Unmanaged<KeyRoutingBox>.fromOpaque(data).takeUnretainedValue()
                            .engine?.received(event) ?? false
                    } ? 1 : 0
                }
            g_signal_connect_data(
                UnsafeMutableRawPointer(legacy),
                "event",
                unsafeBitCast(callback, to: GCallback.self),
                Unmanaged.passRetained(KeyRoutingBox(self)).toOpaque(),
                { data, _ in
                    guard let data else { return }
                    Unmanaged<KeyRoutingBox>.fromOpaque(data).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }

        /// Whether the event went to the page and GTK must not act on it.
        @MainActor
        private func received(_ event: OpaquePointer) -> Bool {
            guard let webView, !webView.isHidden, let window = webView.window else { return false }
            let pageHasFocus = (window.firstResponder as? NSView)?.isDescendant(of: webView) ?? false
            switch gdk_event_get_event_type(event) {
                case GDK_BUTTON_PRESS:
                    let point = webView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    if pageHasFocus, !webView.bounds.contains(point) {
                        window.makeFirstResponder(window.contentView)
                    }
                    return false
                case GDK_KEY_PRESS, GDK_KEY_RELEASE:
                    guard pageHasFocus, gdk_key_event_is_modifier(event) == 0,
                        let key = Self.nsEvent(from: event, in: window)
                    else { return false }
                    NSApp.sendEvent(key)
                    return true
                default:
                    return false
            }
        }

        /// The NSEvent a GDK key event came from, rebuilt: GDK on macOS keeps the
        /// virtual key code as the keycode, and the characters follow the keyval.
        /// GDK 鍵盤事件原本的 NSEvent,重建:macOS 上的 GDK 以虛擬鍵碼為 keycode,字元依 keyval。
        @MainActor
        private static func nsEvent(from event: OpaquePointer, in window: NSWindow) -> NSEvent? {
            let keyval = gdk_key_event_get_keyval(event)
            let state = gdk_event_get_modifier_state(event)
            var flags: NSEvent.ModifierFlags = []
            if state.rawValue & GDK_SHIFT_MASK.rawValue != 0 { flags.insert(.shift) }
            if state.rawValue & GDK_CONTROL_MASK.rawValue != 0 { flags.insert(.control) }
            if state.rawValue & GDK_ALT_MASK.rawValue != 0 { flags.insert(.option) }
            if state.rawValue & (GDK_META_MASK.rawValue | GDK_SUPER_MASK.rawValue) != 0 {
                flags.insert(.command)
            }
            let special: [Int32: UInt32] = [
                GDK_KEY_Return: 0x0D, GDK_KEY_KP_Enter: 0x03, GDK_KEY_Tab: 0x09,
                GDK_KEY_ISO_Left_Tab: 0x19, GDK_KEY_BackSpace: 0x7F, GDK_KEY_Escape: 0x1B,
                GDK_KEY_Delete: 0xF728, GDK_KEY_Up: 0xF700, GDK_KEY_Down: 0xF701,
                GDK_KEY_Left: 0xF702, GDK_KEY_Right: 0xF703, GDK_KEY_Home: 0xF729,
                GDK_KEY_End: 0xF72B, GDK_KEY_Page_Up: 0xF72C, GDK_KEY_Page_Down: 0xF72D,
            ]
            let scalar = special[Int32(keyval)] ?? gdk_keyval_to_unicode(keyval)
            let characters = Unicode.Scalar(scalar).map { String(Character($0)) } ?? ""
            return NSEvent.keyEvent(
                with: gdk_event_get_event_type(event) == GDK_KEY_PRESS ? .keyDown : .keyUp,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: UInt16(gdk_key_event_get_keycode(event))
            )
        }
    }
#endif
