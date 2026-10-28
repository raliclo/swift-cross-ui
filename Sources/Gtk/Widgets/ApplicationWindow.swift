//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk

public class ApplicationWindow: Window {
    public convenience init(application: Application) {
        self.init(
            gtk_application_window_new(application.applicationPointer)
        )
        registerSignals()
    }

    public override func registerSignals() {
        super.registerSignals()

        // `notify::` hands the handler a GParamSpec, not the new value, so the
        // value is read from the window. See `GObject.addNotificationSignal`.
        // `notify::` 交給 handler 的是 GParamSpec 而不是新值，所以值從視窗讀取。見 `GObject.addNotificationSignal`。
        addNotificationSignal(name: "notify::is-active") { [weak self] in
            guard let self else { return }
            self.notifyIsActive?(self.isActive)
        }
    }

    public var notifyIsActive: ((Bool) -> Void)?

    @GObjectProperty(named: "show-menubar") public var showMenuBar: Bool
}
