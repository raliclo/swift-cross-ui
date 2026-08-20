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
            self.onOpen?(uris)
        }
    }

    @discardableResult
    public func run(_ windowCallback: @escaping (ApplicationWindow) -> Void) -> Int {
        self.windowCallback = windowCallback

        let status = g_application_run(applicationPointer.cast(), 0, nil)
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

    public var onOpen: (([URL]) -> Void)?
}
