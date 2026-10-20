#if os(macOS)
    import AppKit
    import Foundation

    extension GtkBackend {
        /// Hands the URLs macOS sends as Apple events to the incoming-URL handler.
        ///
        /// On macOS a URL reaches an app through Launch Services: `open scui-testapp://x`,
        /// a link clicked elsewhere, or a second `open` while the app runs all arrive
        /// as a `kAEGetURL` event, not on the command line. GTK installs its own
        /// NSApplication delegate, and that delegate takes files only, so every URL
        /// event was dropped: P78 in a bundle, launched with `open`, logged no
        /// "received" at all (2026-10-20). GApplication's own forwarding of a second
        /// launch needs a D-Bus session bus, which macOS does not run, so this is
        /// the path that delivers the URL to the running instance there.
        ///
        /// Installed when the handler is set, which is inside `activate` and before
        /// GTK's main loop dispatches any event, so the launch URL is caught too.
        ///
        /// 把 macOS 以 Apple event 送來的 URL 交給 incoming-URL 處理器。macOS 上 URL 經由 Launch Services
        /// 到達 app:`open scui-testapp://x`、在別處點的連結、app 執行中再一次 `open`,都以 `kAEGetURL` 事件抵達，
        /// 而不在命令列上。GTK 安裝了自己的 NSApplication delegate,而它只接檔案，因此每個 URL 事件都被丟掉:
        /// 包成 bundle、以 `open` 啟動的 P78 一行「received」都沒記(2026-10-20)。GApplication 自己轉交第二次
        /// 啟動要靠 D-Bus session bus,macOS 不跑它，所以在這裡把 URL 交給執行中實例的就是這條路徑。
        /// 在設定處理器時安裝，那是在 `activate` 之內、GTK 主迴圈分派任何事件之前，因此啟動 URL 也接得到。
        func installAppleEventURLHandler(_ action: @escaping (URL) -> Void) {
            let receiver = AppleEventURLReceiver(action: action)
            NSAppleEventManager.shared().setEventHandler(
                receiver,
                andSelector: #selector(AppleEventURLReceiver.handleGetURL(_:withReplyEvent:)),
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventID(kAEGetURL)
            )
            // The manager does not retain its handler. / manager 不會 retain 處理器。
            AppleEventURLReceiver.current = receiver
        }
    }

    final class AppleEventURLReceiver: NSObject {
        nonisolated(unsafe) static var current: AppleEventURLReceiver?
        let action: (URL) -> Void

        init(action: @escaping (URL) -> Void) {
            self.action = action
        }

        @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
            guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
                let url = URL(string: text)
            else { return }
            action(url)
        }
    }
#endif
