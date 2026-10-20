//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk
import Foundation

public class Application: GObject, GActionMap {
    var applicationPointer: UnsafeMutablePointer<GtkApplication> {
        UnsafeMutablePointer(OpaquePointer(gobjectPointer))
    }

    private var windowCallback: ((ApplicationWindow) -> Void)?
    private var hasActivated = false

    public var actionMapPointer: OpaquePointer {
        OpaquePointer(applicationPointer)
    }

    private var _menuBarModel: GMenu?
    public var menuBarModel: GMenu? {
        get {
            _menuBarModel
        }
        set {
            gtk_application_set_menubar(
                applicationPointer,
                (newValue?.pointer).map(UnsafeMutablePointer.init)
            )
            _menuBarModel = newValue
        }
    }

    @GObjectProperty(named: "register-session") public var registerSession: Bool

    /// Binds keyboard accelerators to an action, e.g. `["<Control>q"]` for
    /// `"app.quit"`.
    ///
    /// Application-wide, so it fires whichever window has focus and keeps
    /// working for windows created later -- unlike a key controller, which has
    /// to be attached to each window as it appears.
    ///
    /// 將鍵盤加速鍵繫結至某個動作，例如以 `["<Control>q"]` 繫結 `"app.quit"`。
    ///
    /// 其作用範圍為整個應用程式，因此無論哪個視窗取得焦點都會觸發，對日後才建立的視窗亦然——這與
    /// key controller 不同，後者必須在每個視窗出現時逐一掛載。
    public func setAccelerators(_ accelerators: [String], forAction action: String) {
        // A NULL-terminated array of C strings, which is what GTK wants and what
        // Swift's automatic `[String]` bridging does not produce.
        // GTK 要求的是以 NULL 結尾的 C 字串陣列，而 Swift 對 `[String]` 的自動橋接不會產生這種形式。
        let owned: [UnsafeMutablePointer<CChar>?] = accelerators.map { strdup($0) }
        var pointers: [UnsafePointer<CChar>?] = owned.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        pointers.append(nil)
        gtk_application_set_accels_for_action(applicationPointer, action, &pointers)
        for pointer in owned {
            free(pointer)
        }
    }

    /// Ends the application's main loop.
    ///
    /// Not the same as closing every window: closing runs each window's close
    /// handler, and an application that vetoes a close would refuse to quit.
    ///
    /// 結束應用程式的 main loop。
    ///
    /// 這與「關閉所有視窗」不同：關閉會執行每個視窗的 close handler，而會否決關閉的應用程式將
    /// 因此拒絕結束。
    public func quit() {
        g_application_quit(UnsafeMutablePointer(OpaquePointer(applicationPointer)))
    }

    public init(applicationId: String, flags: GApplicationFlags = .init(rawValue: 0)) {
        super.init(
            gtk_application_new(applicationId, flags)
        )
        registerSignals()
    }

    public override func registerSignals() {
        addSignal(name: "activate") {
            self.activate()
        }

        let handler1:
            @convention(c) (
                UnsafeMutableRawPointer,
                UnsafeMutablePointer<OpaquePointer>,
                gint,
                UnsafeMutableRawPointer,
                UnsafeMutableRawPointer
            ) -> Void = { _, files, nFiles, _, data in
                SignalBox2<UnsafeMutablePointer<OpaquePointer>, Int>.run(data, files, Int(nFiles))
            }

        addSignal(name: "open", handler: gCallback(handler1)) {
            [weak self] (files: UnsafeMutablePointer<OpaquePointer>, nFiles: Int) in
            guard let self else { return }
            var uris: [URL] = []
            for i in 0..<nFiles {
                uris.append(
                    GFile(files[i]).uri
                )
            }
            // With HANDLES_OPEN a launch that carries files emits `open` instead
            // of `activate`, so the window is made here when it does not exist
            // yet; otherwise an app launched with a URL would have no window.
            // 有 HANDLES_OPEN 時，帶檔案的啟動會發出 `open` 而非 `activate`,因此視窗尚不存在時在此建立；否則以
            // URL 啟動的 app 將沒有視窗。
            self.activate()
            if let onOpen = self.onOpen {
                onOpen(uris)
            } else {
                self.pendingOpen.append(contentsOf: uris)
            }
        }
    }

    @discardableResult
    public func run(_ windowCallback: @escaping (ApplicationWindow) -> Void) -> Int {
        self.windowCallback = windowCallback

        // Only the arguments that are URLs, after argv[0]. With argc 0, as this
        // was, GApplication never saw the command line, so the URL an app was
        // launched with never became an `open` -- and neither did the one a
        // second launch forwards, which is the same path in the other process.
        // P78 read "received 0" on Windows GTK (2026-10-20). Not the whole argv:
        // GApplication parses options itself, and an app's own flag such as
        // `--debug` would make it fail with "Unknown option" before any window.
        // A URL needs a scheme of two letters or more, so `C:/x` stays a path.
        //
        // 只傳 argv[0] 之後屬於 URL 的引數。原本 argc 為 0,GApplication 從未看到命令列，因此 app 啟動時帶的
        // URL 從未成為 `open`——第二次啟動所轉交的也一樣，那是另一個行程裡的同一條路徑。P78 在 Windows GTK 上讀到
        // 「received 0」(2026-10-20)。不傳整個 argv:GApplication 會自行解析選項,app 自己的旗標(例如 `--debug`)
        // 會讓它在任何視窗出現前以「Unknown option」失敗。URL 的 scheme 須至少兩個字母，因此 `C:/x` 仍是路徑。
        let urls = CommandLine.arguments.dropFirst().filter { argument in
            guard !argument.hasPrefix("-"), let url = URL(string: argument),
                let scheme = url.scheme
            else { return false }
            return scheme.count > 1
        }
        let arguments = [CommandLine.arguments.first ?? "app"] + urls
        let owned: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        var argv = owned
        let status = g_application_run(
            applicationPointer.cast(), gint(arguments.count), &argv)
        for pointer in owned {
            free(pointer)
        }
        g_object_unref(applicationPointer)
        return Int(status)
    }

    private func activate() {
        // When set up as a DBusActivatable application on Linux and launched
        // the GNOME app launcher, the activate signal triggers twice, causing
        // two instances of the application's main window unless we ignore the
        // second activation.
        guard !hasActivated else {
            return
        }

        hasActivated = true
        let window = ApplicationWindow(application: self)
        windowCallback?(window)
    }

    /// Receives the URLs of every `open`, from this process's own command line
    /// and from later launches GApplication forwards to it. URLs that arrive
    /// before it is set (the launch URL: `open` comes before the window, and the
    /// window is what sets this) are kept and handed over when it is.
    /// 接收每一次 `open` 的 URL:來自本行程自己的命令列，以及 GApplication 轉交過來的後續啟動。在它設定之前抵達的
    /// URL(啟動 URL:`open` 早於視窗，而設定它的正是視窗)會先保留，設定時再交出。
    public var onOpen: (([URL]) -> Void)? {
        didSet {
            guard let onOpen, !pendingOpen.isEmpty else { return }
            let urls = pendingOpen
            pendingOpen = []
            onOpen(urls)
        }
    }
    private var pendingOpen: [URL] = []
}
