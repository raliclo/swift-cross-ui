import CGtk
import Foundation
import Gtk
@_spi(Backends) import SwiftCrossUI
import GtkCHelpers

extension App {
    public typealias Backend = GtkBackend

    public var backend: GtkBackend {
        GtkBackend(appIdentifier: Self.metadata?.identifier)
    }
}

public final class GtkBackend:
    BaseAppBackend,
    BackendFeatures.IncomingURLs,
    BackendFeatures.ExternalURLs,
    BackendFeatures.RevealFiles,
    BackendFeatures.ApplicationMenus,
    BackendFeatures.FileDialogs,
    BackendFeatures.Alerts,
    BackendFeatures.Sheets,
    BackendFeatures.CornerRadius,
    BackendFeatures.Gestures,
    BackendFeatures.PopoverMenus,
    BackendFeatures.Tables,
    BackendFeatures.Paths,
    BackendFeatures.Tooltips,
    BackendFeatures.Colors,
    BackendFeatures.DatePickers,
    BackendFeatures.Windowing,
    BackendFeatures.LinearGradients,
    BackendFeatures.RadialGradients,
    BackendFeatures.HitTesting,
    BackendFeatures.DragAndDrop,
    BackendFeatures.Clipping
{
    public typealias Window = Gtk.ApplicationWindow
    public typealias Widget = Gtk.Widget
    public typealias Menu = Gtk.PopoverMenu
    public typealias Alert = Gtk.MessageDialog

    public class Sheet: Gtk.Window {
        var onDismiss: (() -> Void)? = nil
        var interactiveDismissDisabled = false
        var nestedSheet: Sheet?
    }

    public final class Path {
        var path: SwiftCrossUI.Path?
    }

    public let defaultTableRowContentHeight = 20
    public let defaultTableCellVerticalPadding = 4
    public let defaultPaddingAmount = 10
    public let scrollBarWidth = 0
    public let requiresToggleSwitchSpacer = false
    public let requiresImageUpdateOnScaleFactorChange = false
    public let supportsMultipleWindows = true
    public let deviceClass = DeviceClass.desktop
    public let supportedDatePickerStyles: [DatePickerStyle] = [.automatic, .graphical]
    public let supportedPickerStyles: [BackendPickerStyle] = [.menu]
    public let canOverrideWindowColorScheme = false
    public let restoresWindowFrames = false

    let defaultSheetCornerRadius = 10

    var gtkApp: Application
    private var selectableListStates: [ObjectIdentifier: SelectableListState] = [:]

    /// A window to be returned on the next call to ``GtkBackend/createWindow``.
    /// This is necessary because Gtk creates a root window no matter what, and
    /// this needs to be returned on the first call to `createWindow`.
    var precreatedWindow: Window?

    /// All current windows associated with the application. Doesn't include the
    /// precreated window until it gets 'created' via `createWindow`.
    var windows: [Window] = []

    /// The alert currently on screen for a window, keyed by window identity, and
    /// the alerts waiting behind it. SwiftUI shows one alert at a time per
    /// window; a second requested while one is up waits and appears when the
    /// first is dismissed, rather than a pile of modal dialogs fighting over the
    /// window (the P5 regression).
    private var shownAlert: [ObjectIdentifier: Alert] = [:]
    private var pendingAlerts:
        [ObjectIdentifier: [(alert: Alert, window: Window, handler: (Int) -> Void)]] = [:]

    private var rootEnvironmentChangeHandler: (() -> Void)?

    private var measurementCustomLabel: CustomLabel!

    private struct LogLocation: Hashable, Equatable {
        let file: String
        let line: Int
        let column: Int
    }

    private var logsPerformed: Set<LogLocation> = []

    func debugLogOnce(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        column: Int = #column
    ) {
        #if DEBUG
            let location = LogLocation(file: file, line: line, column: column)
            if logsPerformed.insert(location).inserted {
                logger.notice("\(message)")
            }
        #endif
    }

    // A separate initializer to satisfy `BackendFeatures.Core`'s requirements.
    public convenience init() {
        self.init(appIdentifier: nil)
    }

    /// Creates a backend instance. If `appIdentifier` is `nil`, the default
    /// identifier `com.example.SwiftCrossUIApp` is used.
    public init(appIdentifier: String?) {
        gtkApp = Application(
            applicationId: appIdentifier ?? "com.example.SwiftCrossUIApp",
            flags: SHIM_G_APPLICATION_HANDLES_OPEN
        )
        gtkApp.registerSession = true
    }

    var globalCSSProvider: CSSProvider?

    /// Guards `-actionfile` against replaying once per window. See
    /// `ActionFileReplay.swift`.
    #if SCUI_DEBUG
    var hasReplayedActionFile = false
    #endif

    /// Kept alive for as long as the backend is. A `GSimpleAction` added to the
    /// application is referenced by it, but the Swift wrapper holds the closure,
    /// and letting it go would leave the accelerator firing into freed memory.
    /// 需與 backend 同壽。加入 application 的 `GSimpleAction` 會被其持有，但 Swift wrapper 才是
    /// 持有 closure 的一方；若讓它被釋放，加速鍵便會觸發到已釋放的記憶體。
    private var quitAction: GSimpleAction?

    public func runMainLoop(_ callback: @escaping @MainActor () -> Void) {
        installQuitShortcut()
        gtkApp.run { window in
            self.measurementCustomLabel = (self.createTextView() as! CustomLabel)
            self.precreatedWindow = window
            callback()

            let provider = CSSProvider()
            provider.loadCss(
                from: """
                    list {
                        background: none;
                    }

                    list > row {
                        padding: 0;
                        min-height: 0;
                    }

                    .navigation-sidebar {
                        margin: 0;
                        padding: 0;
                    }

                    .navigation-sidebar > row { margin: 0;
                        padding: 0;
                    }

                    /* #390: make disabled controls clearly distinct. GTK's
                       default theme dims an insensitive widget only subtly --
                       mostly its label colour -- so a disabled button reads as
                       enabled at a glance. SwiftUI fades the whole control;
                       fade it here too. sensitive = false is already set on
                       each control (see updateButton et al.), which is what
                       :disabled matches. */
                    button:disabled,
                    checkbutton:disabled,
                    switch:disabled,
                    entry:disabled,
                    scale:disabled,
                    spinbutton:disabled {
                        opacity: 0.5;
                    }
                    """
            )

            // Keep a reference around so that the provider doesn't get removed as
            // soon as we exit this scope.
            self.globalCSSProvider = provider

            #if !os(macOS)
                Self.mainRunLoopTicklingLoop()
            #endif
        }
    }

    private static func mainRunLoopTicklingLoop(nextDelayMilliseconds: Int? = nil) {
        Self.runInMainThread(afterMilliseconds: nextDelayMilliseconds ?? 50) {
            // This performs one pass through the run loop
            let nextDate = RunLoop.main.limitDate(forMode: .default)

            // This isn't expected to be nil, but if it is we can just loop
            // again quickly with the default delay.
            let nextDelay = nextDate.map {
                return max(min(Int($0.timeIntervalSinceNow * 1000), 50), 0)
            }
            mainRunLoopTicklingLoop(nextDelayMilliseconds: nextDelay)
        }
    }

    public func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window {
        let window: Gtk.ApplicationWindow
        if let precreatedWindow {
            self.precreatedWindow = nil
            window = precreatedWindow
        } else {
            window = Gtk.ApplicationWindow(application: gtkApp)
        }

        windows.append(window)

        if let defaultSize {
            window.defaultSize = Size(
                width: defaultSize.x,
                height: defaultSize.y
            )
        }

        window.setChild(Gtk.Box())

        window.notifyIsActive = { _ in
            self.rootEnvironmentChangeHandler?()
        }

        return window
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        // TODO(stackotter): Support preferredColorScheme
    }

    public func setTitle(ofWindow window: Window, to title: String) {
        window.title = title
    }

    public func setBehaviors(
        ofWindow window: Window,
        closable: Bool,
        minimizable: Bool,
        resizable: Bool
    ) {
        // FIXME: This doesn't seem to work on macOS at least
        window.deletable = closable

        // TODO: Figure out if there's some magic way to disable minimization
        //   in a framework where the minimize button usually doesn't even exist

        window.resizable = resizable
    }

    public func setChild(ofWindow window: Window, to child: Widget) {
        let container = wrapInCustomRootContainer(child)
        window.setChild(container)
    }

    private func menubarHeight(ofWindow window: Window) -> Int {
        #if os(macOS)
            return 0
        #else
            if window.showMenuBar {
                // TODO: Don't hardcode this (if possible), because some Gtk
                //   themes may affect the height of the menu bar.
                25
            } else {
                0
            }
        #endif
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        let child = window.getChild() as! CustomRootWidget
        let size = child.getSize()
        return SIMD2(size.width, size.height)
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        // TODO: Detect whether window is fullscreen
        return true
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        let child = window.getChild() as! CustomRootWidget
        window.size = Size(
            width: newSize.x,
            height: newSize.y + menubarHeight(ofWindow: window)
        )
        child.preemptAllocatedSize(allocatedWidth: newSize.x, allocatedHeight: newSize.y)
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        window.setMinimumSize(to: Size(width: minimumSize.x, height: minimumSize.y))

        // A size request on the toplevel is only honoured as a launch hint; once
        // the window is realised GTK lets the user drag it below that, and the
        // content is clipped. What GTK does keep enforcing is the *child's*
        // measured minimum, so the enforced minimum has to live on the custom
        // root widget too -- and because this runs on every window update, it
        // tracks the content as it grows (the #289 case: taller content did not
        // raise the floor, so the window shrank into it).
        let root = window.getChild() as! CustomRootWidget
        root.setMinimumSize(minimumWidth: minimumSize.x, minimumHeight: minimumSize.y)

        // NB: GTK does not support setting maximum sizes for widgets. It just doesn't.
        // https://discourse.gnome.org/t/how-to-build-fixed-size-windows-in-gtk-4/22807/10
        if maximumSize != nil {
            debugLogOnce("GTK does not support setting maximum window sizes")
        }
    }

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (_ newSize: SIMD2<Int>) -> Void
    ) {
        let child = window.getChild() as! CustomRootWidget
        child.setResizeHandler { size in
            self.runInMainThread {
                action(SIMD2(size.width, size.height))
            }
        }
    }

    /// Ctrl-Q quits, which is the GTK convention and issue #478.
    ///
    /// Nothing provided this before. On macOS Cmd-Q comes free with AppKit's
    /// standard application menu; GTK has no equivalent, so an app built on this
    /// backend simply had no quit shortcut and the window stayed open.
    ///
    /// A `GAction` plus an accelerator rather than a key controller on each
    /// window: an accelerator is application-wide, so it works whichever window
    /// has focus and keeps working for windows created later.
    ///
    /// `g_application_quit` rather than closing windows one by one. Closing them
    /// runs each close handler, and an app that vetoes a close would refuse the
    /// shortcut -- which is the behaviour of a close request, not of a quit.
    ///
    /// Ctrl-Q 結束程式，這是 GTK 的慣例，也是 issue #478。
    ///
    /// 此前並無任何機制提供它。在 macOS 上，Cmd-Q 隨 AppKit 的標準應用程式選單而來；GTK 沒有對應
    /// 機制，因此以此 backend 建置的 app 根本沒有結束捷徑，視窗會一直開著。
    ///
    /// 使用 `GAction` 加上加速鍵，而非在每個視窗掛上 key controller：加速鍵是應用程式層級的，因此
    /// 無論哪個視窗取得焦點都有效，對日後才建立的視窗亦然。
    ///
    /// 使用 `g_application_quit` 而非逐一關閉視窗。逐一關閉會執行每個 close handler，而會否決關閉
    /// 的 app 將因此拒絕此捷徑——那是「關閉請求」的行為，不是「結束程式」的行為。
    private func installQuitShortcut() {
        let action = GSimpleAction(name: "quit") { [weak self] in
            self?.gtkApp.quit()
        }
        gtkApp.addAction(action)
        quitAction = action
        gtkApp.setAccelerators(["<Control>q"], forAction: "app.quit")
    }

    public func show(window: Window) {
        // present(), not show(). `Widget.show()` is gtk_widget_set_visible,
        // which maps the window without raising it or giving it focus; GTK 4
        // documents gtk_window_present as the way to show a window, and on
        // Windows it is what makes it the foreground window.
        //
        // Observed with set_visible: the window appeared but never became
        // foreground, so AppActivate could not raise it and screenshots of the
        // "whole desktop" photographed whatever was in front instead. Worse, a
        // GtkDropDown's popover opened from an unfocused window read as a
        // detached window that would not come forward and did not dismiss on
        // selection.
        //
        // 使用 present() 而非 show()。`Widget.show()` 實為 gtk_widget_set_visible，它只會把視窗
        // map 出來，不會將其提到最上層、也不會給予焦點；GTK 4 明確以 gtk_window_present 作為
        // 顯示視窗的方式，而在 Windows 上它正是使視窗成為前景視窗的呼叫。
        //
        // 使用 set_visible 時的實際觀察：視窗會出現但從未成為前景，因此 AppActivate 無法喚起
        // 它，而「整個桌面」的截圖只會拍到當時位於前方的其他內容。更嚴重的是，從一個未取得焦點
        // 的視窗開啟的 GtkDropDown popover，表現為一個無法被帶到前面、且選取後不會關閉的
        // 分離視窗。
        window.present()
        #if SCUI_DEBUG
        replayActionFileIfRequested()
        #endif
    }

    public func activate(window: Window) {
        window.present()
    }

    public func close(window: Window) {
        window.close()
    }

    public func setCloseHandler(
        ofWindow window: Window,
        to action: @escaping () -> Void
    ) {
        window.onCloseRequest = { _ in
            action()
            window.destroy()
        }
    }

    public func openExternalURL(_ url: URL) throws {
        // Used instead of gtk_uri_launcher_launch to maintain <4.10 compatibility
        gtk_show_uri(nil, url.absoluteString, guint(GDK_CURRENT_TIME))
    }

    public func revealFile(_ url: URL) throws {
        var success = false

        #if !os(Windows)
            let fileURI = url.absoluteString.replacingOccurrences(
                of: ",",
                with: "\\,"
            )
            let process = Process()
            process.arguments = [
                "dbus-send",
                "--print-reply",
                "--dest=org.freedesktop.FileManager1",
                "/org/freedesktop/FileManager1",
                "org.freedesktop.FileManager1.ShowItems",
                "array:string:\(fileURI)",
                "string:",
            ]
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            do {
                try process.run()
                process.waitUntilExit()

                success = process.terminationStatus == 0
            } catch {

            }
        #endif

        if !success {
            // Fall back to opening the parent directory without highlighting
            // the file.
            try openExternalURL(url.deletingLastPathComponent())
        }
    }

    private func renderMenu(
        _ menu: ResolvedMenu,
        actionMap: any GActionMap,
        actionNamespace: String,
        actionPrefix: String?,
        environment: EnvironmentValues
    ) -> GMenu {
        var currentSection = GMenu()
        var previousSections: [GMenu] = []

        for (i, item) in menu.items.enumerated() {
            let actionName =
                if let actionPrefix {
                    "\(actionPrefix)_\(i)"
                } else {
                    "\(i)"
                }

            render(item: item, environment: environment)
            func render(item: ResolvedMenu.Item, environment: EnvironmentValues) {
                switch item {
                    case .button(let label, let action):
                        if let action {
                            let gAction = GSimpleAction(name: actionName, action: action)
                            gAction.enabled = environment.isEnabled
                            actionMap.addAction(gAction)
                        }

                        currentSection.appendItem(
                            label: label,
                            actionName: "\(actionNamespace).\(actionName)"
                        )
                    case .toggle(let label, let value, let onChange):
                        let gAction = GSimpleAction(
                            name: actionName,
                            state: value,
                            action: onChange
                        )
                        gAction.enabled = environment.isEnabled
                        actionMap.addAction(gAction)

                        currentSection.appendItem(
                            label: label,
                            actionName: "\(actionNamespace).\(actionName)"
                        )
                    case .separator:
                        // GTK[3] doesn't have explicit separators per se, but instead deals with
                        // sections (actually quite similar to what you can do in SwiftUI with the
                        // Section view). It'll automatically draw separators between sections.
                        previousSections.append(currentSection)
                        currentSection = GMenu()
                    case .submenu(let submenu):
                        currentSection.appendSubmenu(
                            label: submenu.label,
                            content: renderMenu(
                                submenu.content,
                                actionMap: actionMap,
                                actionNamespace: actionNamespace,
                                actionPrefix: actionName,
                                environment: environment
                            )
                        )
                    case .modifiedEnvironment(let item, let modification):
                        render(item: item, environment: modification(environment))
                }
            }
        }

        if previousSections.isEmpty {
            // There are no dividers; just return the current section to keep the menu tree flat.
            return currentSection
        } else {
            let model = GMenu()
            for section in previousSections + [currentSection] {
                model.appendSection(label: nil, content: section)
            }
            return model
        }
    }

    private func renderMenuBar(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) -> GMenu {
        let model = GMenu()
        for (i, submenu) in submenus.enumerated() {
            model.appendSubmenu(
                label: submenu.label,
                content: renderMenu(
                    submenu.content,
                    actionMap: gtkApp,
                    actionNamespace: "app",
                    actionPrefix: "\(i)",
                    environment: environment
                )
            )
        }

        return model
    }

    public func setApplicationMenu(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) {
        let model = renderMenuBar(submenus, environment: environment)
        gtkApp.menuBarModel = model

        let showMenuBar = !submenus.isEmpty
        for window in windows {
            window.showMenuBar = showMenuBar
        }
    }

    class ThreadActionContext {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }
    }

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        let action = ThreadActionContext(action: action)
        g_idle_add_full(
            0,
            { context in
                guard let context else {
                    fatalError("Gtk action callback called without context")
                }

                let action = Unmanaged<ThreadActionContext>.fromOpaque(context)
                    .takeUnretainedValue()
                let innerAction = action.action
                MainActor.assumeIsolated {
                    innerAction()
                }

                return 0
            },
            Unmanaged<ThreadActionContext>.passRetained(action).toOpaque(),
            { _ in }
        )
    }

    private static func runInMainThread(
        afterMilliseconds delay: Int,
        action: @escaping @MainActor () -> Void
    ) {
        let action = ThreadActionContext(action: action)
        g_timeout_add_full(
            0,
            guint(max(delay, 0)),
            { context in
                guard let context else {
                    fatalError("Gtk action callback called without context")
                }

                let action = Unmanaged<ThreadActionContext>.fromOpaque(context)
                    .takeUnretainedValue()
                let innerAction = action.action
                MainActor.assumeIsolated {
                    innerAction()
                }

                // Cancel the recurring timeout after one iteration
                return 0
            },
            Unmanaged<ThreadActionContext>.passRetained(action).toOpaque(),
            { _ in }
        )
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        defaultEnvironment
            .with(\.appPhase, windows.contains(where: \.isActive) ? .active : .inactive)
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // TODO: React to theme changes
        self.rootEnvironmentChangeHandler = action
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // TODO: Record window scale factor in here
        rootEnvironment
            .with(\.scenePhase, window.isActive ? .active : .inactive)
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // TODO: Notify when window scale factor changes
    }

    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
        gtkApp.onOpen = { urls in
            for url in urls {
                action(url)
            }
        }
    }

    public func show(widget: Widget) {
        widget.show()
    }

    public func tag(widget: Widget, as tag: String) {
        widget.tag(as: tag)
    }

    // MARK: Containers

    public func createContainer() -> Widget {
        // Passthrough, not a plain Fixed. These containers draw nothing, and a
        // plain GtkFixed claims every point its children do not cover -- so an
        // overlay made everything beneath it unreachable by the pointer. See
        // gtk_passthrough_fixed.c.
        //
        // 使用 passthrough 而非一般的 Fixed。這些容器不繪製任何內容，而一般的 GtkFixed 會攔截
        // 其子元件未覆蓋的每一個點——因此 overlay 會使其下方的一切都無法被指標觸及。
        // 詳見 gtk_passthrough_fixed.c。
        return PassthroughFixed()
    }

    public func removeAllChildren(of container: Widget) {
        let container = container as! Fixed
        container.removeAllChildren()
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        let container = container as! Fixed
        container.put(child, index: index, x: 0, y: 0)
    }

    public func setPosition(ofChildAt index: Int, in container: Widget, to position: SIMD2<Int>) {
        let container = container as! Fixed
        container.move(container.children[index], x: Double(position.x), y: Double(position.y))
    }

    public func remove(childAt index: Int, from container: Widget) {
        let container = container as! Fixed
        let child = container.children[index]
        container.remove(child)
    }

    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
        // Gtk.Fixed doesn't let us rearrange children, so we just swap them in
        // our own list so that at least everything works on the SCUI side. The
        // only side effect of this approach is that overlapping widgets may
        // end up with unexpected z ordering. If that becomes an issue we may
        // have to make a custom replacement for Gtk.Fixed.
        let container = container as! Fixed
        container.children.swapAt(firstIndex, secondIndex)
    }

    public func createColorableRectangle() -> Widget {
        // The same passthrough widget the containers use, so a fully
        // transparent rectangle can decline the points it covers. See setColor.
        // 與各容器所使用的同一個 passthrough widget，如此完全透明的矩形便能放棄其所覆蓋的點。
        // 詳見 setColor。
        return PassthroughFixed()
    }

    public func setColor(
        ofColorableRectangle widget: Widget,
        to color: SwiftCrossUI.Color.Resolved
    ) {
        widget.css.set(property: .backgroundColor(color.gtkColor))

        // A fully transparent rectangle stops claiming the points it covers.
        //
        // Same rule as the containers: something that draws nothing does not
        // take the pointer from what is behind it. Without this, `Color.clear`
        // in a ZStack above a button swallows every click -- measured on P10,
        // where `Direct clicks` reached 2 while `Covered clicks` stayed at 0
        // with the overlay present, and the button worked the moment it was
        // removed. That is issue #454.
        //
        // Through the widget's own flag rather than `can-target`. `can-target`
        // belongs to `allowsHitTesting`, and having two things write it would
        // make the last writer win. The flag is read at hit time and combines
        // with the event-controller test, so `Color.clear` carrying a tap
        // gesture stays clickable whichever order the two are applied in.
        //
        // Set on every call rather than only when clear, because a colour
        // animating from transparent to opaque has to take clicks again.
        //
        // SwiftUI does let `Color.clear` take hits, with
        // `allowsHitTesting(false)` as the escape hatch. Diverging here is
        // deliberate and is what #454 asks for: a transparent layer that
        // silently eats input is the more surprising of the two behaviours, and
        // `allowsHitTesting` now exists for anyone who wants the other one.
        //
        // 完全透明的矩形不再攔截其所覆蓋的點。
        //
        // 與各容器同一條規則：不繪製任何內容的東西，不應從其後方的元件手中奪走指標。若無此段，
        // ZStack 中位於按鈕上方的 `Color.clear` 會吞掉每一次點擊——在 P10 實測，overlay 存在時
        // `Direct clicks` 達到 2 而 `Covered clicks` 停在 0，而移除 overlay 的當下按鈕即恢復正常。
        // 這就是 issue #454。
        //
        // 透過該 widget 自身的旗標而非 `can-target`。`can-target` 屬於 `allowsHitTesting`，若有
        // 兩處都寫入它，結果將取決於誰最後寫。此旗標於 hit 時讀取，並與 event controller 的判斷
        // 組合運作，因此帶有 tap gesture 的 `Color.clear` 無論兩者以何順序套用都仍可點擊。
        //
        // 每次呼叫都設定，而非僅在透明時設定，因為由透明漸變為不透明的顏色必須重新接收點擊。
        //
        // SwiftUI 確實讓 `Color.clear` 接收點擊，其逃生口是 `allowsHitTesting(false)`。此處刻意
        // 分歧，而這正是 #454 所要求的：「靜默吞掉輸入的透明圖層」是兩種行為中較令人意外的那一個，
        // 而想要另一種行為的人，現在已有 `allowsHitTesting` 可用。
        gtk_passthrough_fixed_set_opaque(widget.widgetPointer, color.opacity > 0 ? 1 : 0)
    }

    /// `can-target`, which GTK already defines as subtree-wide: hit testing
    /// skips a widget that cannot be targeted and does not descend into it.
    /// That is exactly `allowsHitTesting`'s meaning, so there is nothing to
    /// emulate.
    ///
    /// 使用 `can-target`，GTK 對它的定義本就及於整個子樹：hit testing 會略過無法被指定為目標的
    /// widget，也不會往其內部遞迴。這正是 `allowsHitTesting` 的語意，因此無需任何模擬。
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        gtk_widget_set_can_target(widget.widgetPointer, allowsHitTesting ? 1 : 0)
    }

    public func createCornerRadiusContainer(wrapping child: Widget) -> Widget {
        // SwiftUI's cornerRadius rounds *and* clips: a child larger than the box
        // is cut to it. AppKit does this with clipsToBounds and WinUI with a
        // geometric clip; GtkBackend was the one backend that only styled and
        // never clipped, which is #389. Clip through the same ClipFixed the
        // explicit clipped() uses -- a plain overflow: hidden does not work here
        // because a GtkFixed over-allocates to an oversized child and then clips
        // the wrong box; the P17-DOE experiment showed this. ClipFixed clips to
        // the size SwiftCrossUI decided instead.
        let container = ClipFixed()
        container.put(child, x: 0, y: 0)
        return container
    }

    // The explicit counterpart, clipped(), through the same clipping container.
    public func createClippedContainer() -> Widget {
        ClipFixed()
    }

    public func setCornerRadius(of widget: Widget, to radius: Int) {
        // Rounds the corners of the ClipFixed the container wraps content in; the
        // clip itself is handled by ClipFixed. A rounded radius rounds the border
        // visually while the clip stays rectangular -- exact for radius 0 (P3's
        // case) and a strict improvement for larger radii, where the old code did
        // not clip at all. A rounded clip would need gtk_snapshot_push_rounded_clip.
        widget.css.set(property: .cornerRadius(radius))
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let currentSize = widget.getSizeRequest()
        widget.setSizeRequest(width: -1, height: -1)
        let (width, height) = widget.getNaturalSize()
        widget.setSizeRequest(width: currentSize.width, height: currentSize.height)
        return SIMD2(width, height)
    }

    public func setSize(of widget: Widget, to size: SIMD2<Int>) {
        widget.setSizeRequest(width: size.x, height: size.y)
    }

    /// The sidebar width to open at when the content does not ask for more.
    ///
    /// Matches `defaultLeadingWidth` in AppKitBackend, so the two agree on what
    /// a navigation sidebar looks like before anyone drags it.
    static let defaultSidebarWidth = 200

    public func createSplitView(leadingChild: Widget, trailingChild: Widget) -> Widget {
        let widget = CustomPaned(orientation: .horizontal)
        let leadingContainer = wrapInCustomRootContainer(leadingChild)
        let trailingContainer = wrapInCustomRootContainer(trailingChild)

        widget.startChild = leadingContainer
        widget.endChild = trailingContainer
        widget.shrinkStartChild = false
        widget.shrinkEndChild = false

        // A starting guess only. The layout system reads sidebarWidth(ofSplitView:)
        // during layout, which runs before the first commit, so the divider needs
        // some value; setSidebarWidthBounds replaces it as soon as the sidebar's
        // real minimum and natural widths are known.
        widget.position = Self.defaultSidebarWidth
        return widget
    }

    public func setResizeHandler(
        ofSplitView splitView: Widget,
        to action: @escaping () -> Void
    ) {
        let splitView = splitView as! Paned
        splitView.notifyPosition = { _ in
            action()
        }
    }

    public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
        let splitView = splitView as! CustomPaned
        return splitView.position
    }

    public func setSidebarWidthBounds(
        ofSplitView splitView: Widget,
        minimum minimumWidth: Int,
        maximum maximumWidth: Int
    ) {
        let splitView = splitView as! CustomPaned
        show(widget: splitView.startChild!)

        // Measured before the size requests below, which would otherwise floor
        // the natural width at whatever we just asked for and make it useless
        // as a measure of what the content wants.
        let naturalSidebarWidth = splitView.startChild?.getNaturalSize().width ?? 0

        // The caller derives the maximum from the total width minus the
        // trailing pane's minimum, which can fall below the leading pane's
        // minimum when the split view is cramped.
        let maximumWidth = max(minimumWidth, maximumWidth)

        // SplitView.commit calls setSize(of:to:) immediately before this, and
        // that writes layout.size into the widget's size request, so reading it
        // back gives the width the two panes have to divide up. getNaturalSize()
        // answers a different question -- what the content would like -- so
        // using it here made the trailing pane's minimum wrong, and negative
        // whenever the natural width came out under the maximum.
        let requestedWidth = splitView.getSizeRequest().width
        let totalWidth = requestedWidth > 0 ? requestedWidth : splitView.getNaturalSize().width

        splitView.startChild?.setSizeRequest(width: minimumWidth, height: 0)
        splitView.endChild?.setSizeRequest(width: max(0, totalWidth - maximumWidth), height: 0)

        if splitView.hasEstablishedPosition {
            // Respect a divider the user has dragged, but keep it in range.
            splitView.position = min(max(splitView.position, minimumWidth), maximumWidth)
        } else {
            // First layout with real numbers. The minimum is what the content
            // cannot go below; the width to *open* at is what it would like,
            // floored by the platform's navigation width so a sidebar of short
            // labels still looks like a sidebar rather than a sliver.
            let defaultWidth = max(naturalSidebarWidth, Self.defaultSidebarWidth)
            splitView.position = min(max(defaultWidth, minimumWidth), maximumWidth)
            splitView.hasEstablishedPosition = true
        }
    }

    public func createScrollContainer(for child: Widget) -> Widget {
        let scrollView = ScrolledWindow()
        scrollView.setChild(child)
        return scrollView
    }

    public func updateScrollContainer(
        _ scrollView: Widget,
        environment: EnvironmentValues,
        bounceHorizontally: Bool,
        bounceVertically: Bool,
        hasHorizontalScrollBar: Bool,
        hasVerticalScrollBar: Bool
    ) {
        let scrollView = scrollView as! ScrolledWindow
        scrollView.setScrollBarPresence(
            hasVerticalScrollBar: hasVerticalScrollBar,
            hasHorizontalScrollBar: hasHorizontalScrollBar
        )
    }

    public func createSelectableListView() -> Widget {
        let listView = ListBox()
        listView.selectionMode = .single
        gtk_widget_add_css_class(listView.widgetPointer, "navigation-sidebar")
        return listView
    }

    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        let selectableListView = selectableListView as! ListBox
        selectableListView.sensitive = environment.isEnabled
    }

    public func baseItemPadding(
        ofSelectableListView listView: Widget
    ) -> SwiftCrossUI.EdgeInsets {
        SwiftCrossUI.EdgeInsets()
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        .zero
    }

    public func setItems(
        ofSelectableListView listView: Widget,
        to items: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        // NOTE: This implementation works under the same assumptions as
        //   AppKitBackend's implementation. Read the comment in
        //   AppKitBackend.setItems for more details. In short, we assume
        //   that modifications made to `items` between `setItems` calls
        //   are either all pops, or all appends (not a mix).

        let listView = listView as! ListBox
        let state = state(for: listView)

        let previousRowCount = state.rowCount
        state.rowCount = items.count

        state.isProgrammaticSelectionUpdate = true
        defer { state.isProgrammaticSelectionUpdate = false }

        if items.count > previousRowCount {
            for item in items[previousRowCount...] {
                listView.append(item)
            }
        } else if items.count < previousRowCount {
            for _ in 0..<(previousRowCount - items.count) {
                listView.removeRow(at: items.count)
            }
        }

        preserveNilSelection(of: listView, state: state)
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        let listView = listView as! ListBox
        let state = state(for: listView)
        listView.rowSelected = { _, selectedRow in
            guard !state.isProgrammaticSelectionUpdate else {
                return
            }
            guard !state.isClearingNilSelection else {
                self.preserveNilSelection(of: listView, state: state)
                return
            }
            guard let selectedRow else {
                return
            }
            let selection = Int(gtk_list_box_row_get_index(selectedRow))
            guard selection != state.selection else {
                return
            }
            state.selection = selection
            action(selection)
        }
    }

    public func setSelectedItem(ofSelectableListView listView: Widget, toItemAt index: Int?) {
        let listView = listView as! ListBox
        let state = state(for: listView)
        state.selection = index
        state.isProgrammaticSelectionUpdate = true
        defer { state.isProgrammaticSelectionUpdate = false }
        if let index {
            listView.selectRow(at: index)
        } else {
            preserveNilSelection(of: listView, state: state)
        }
    }

    private func preserveNilSelection(of listView: ListBox, state: SelectableListState) {
        guard state.selection == nil else {
            state.isClearingNilSelection = false
            return
        }

        state.isClearingNilSelection = true
        state.isProgrammaticSelectionUpdate = true
        listView.unselectAll()
        state.isProgrammaticSelectionUpdate = false

        runInMainThread { [listView, state] in
            guard state.selection == nil else {
                state.isClearingNilSelection = false
                return
            }

            state.isProgrammaticSelectionUpdate = true
            listView.unselectAll()
            state.isProgrammaticSelectionUpdate = false
            state.isClearingNilSelection = false
        }
    }

    private func state(for listView: ListBox) -> SelectableListState {
        let key = ObjectIdentifier(listView)
        if let state = selectableListStates[key] {
            return state
        }
        let state = SelectableListState()
        selectableListStates[key] = state
        return state
    }

    public func createTooltipContainer(wrapping child: Widget) -> Widget {
        TooltipContainer(child)
    }

    public func updateTooltipContainer(_ widget: Widget, tooltip: String) {
        let widget = widget as! TooltipContainer
        widget.setTooltip(text: tooltip)
    }

    // MARK: Passive views

    public func createTextView() -> Widget {
        let textView = CustomLabel(string: "")
        textView.horizontalAlignment = .start
        textView.wrap = true
        textView.lineWrapMode = .wordCharacter
        textView.ellipsize = .end
        textView.yalign = 0.0
        return textView
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let textView = textView as! CustomLabel
        textView.label = content
        textView.justify =
            switch environment.multilineTextAlignment {
                case .leading:
                    Justification.left
                case .center:
                    Justification.center
                case .trailing:
                    Justification.right
            }

        textView.selectable = environment.isTextSelectionEnabled
        textView.css.clear()
        textView.css.set(properties: Self.cssProperties(for: environment))
    }

    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        let ellipsize: EllipsizeMode
        if let widget = widget as? CustomLabel {
            ellipsize = widget.ellipsize
        } else if widget as? TextView != nil {
            // We don't ellipsize multi-line text editors
            ellipsize = .none
        } else {
            logger.warning(
                "\(#function) called with unexpected widget type \(type(of: widget))"
            )
            ellipsize = .none
        }

        let pango = Pango(for: widget)
        let (width, height) = pango.getTextSize(
            text,
            ellipsize: proposedHeight == nil ? .none : ellipsize,
            proposedWidth: proposedWidth.map(Double.init),
            proposedHeight: proposedHeight.map(Double.init)
        )

        var imposedHeight = height

        if let lineLimitSettings = environment.lineLimitSettings {
            let multilineString = [String](repeating: "a", count: lineLimitSettings.limit)
                .joined(separator: "\n")
            updateTextView(
                measurementCustomLabel,
                content: "",
                environment: environment
            )

            let pango = Pango(for: measurementCustomLabel)

            let (_, heightLimit) = pango.getTextSize(
                multilineString,
                ellipsize: .none,
                proposedWidth: nil,
                proposedHeight: nil
            )

            if heightLimit < imposedHeight || lineLimitSettings.reservesSpace {
                imposedHeight = heightLimit
            }
        }

        return SIMD2(width, imposedHeight)
    }

    public func createImageView() -> Widget {
        let imageView = Gtk.Picture()
        imageView.keepAspectRatio = false
        imageView.canShrink = true
        return imageView
    }

    public func updateImageView(
        _ imageView: Widget,
        rgbaData: [UInt8],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
        dataHasChanged: Bool,
        environment: EnvironmentValues
    ) {
        guard dataHasChanged else {
            return
        }

        let imageView = imageView as! Gtk.Picture
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: rgbaData.count)
        memcpy(buffer.baseAddress!, rgbaData, rgbaData.count)
        let pixbuf = gdk_pixbuf_new_from_data(
            buffer.baseAddress,
            GDK_COLORSPACE_RGB,
            1,
            8,
            Int32(width),
            Int32(height),
            Int32(width * 4),
            { buffer, _ in
                buffer?.deallocate()
            },
            nil
        )
        let texture = gdk_texture_new_for_pixbuf(pixbuf)!
        imageView.setPaintable(texture)
    }

    // private class Tables {
    //     var tableSizes: [ObjectIdentifier: (rows: Int, columns: Int)] = [:]
    // }

    // private let tables = Tables()

    // TODO: Implement tables
    // public func createTable(rows: Int, columns: Int) -> Widget {
    //     let widget = Grid()

    //     for i in 0..<rows {
    //         widget.insertRow(position: i)
    //     }

    //     for i in 0..<columns {
    //         widget.insertRow(position: i)
    //     }

    //     tables.tableSizes[ObjectIdentifier(widget)] = (rows: rows, columns: columns)

    //     widget.columnSpacing = 10
    //     widget.rowSpacing = 10

    //     return widget
    // }

    // public func setRowCount(ofTable table: Widget, to rows: Int) {
    //     let table = table as! Grid

    //     let rowDifference = rows - tables.tableSizes[ObjectIdentifier(table)]!.rows
    //     tables.tableSizes[ObjectIdentifier(table)]!.rows = rows
    //     if rowDifference < 0 {
    //         for _ in 0..<(-rowDifference) {
    //             table.removeRow(position: 0)
    //         }
    //     } else if rowDifference > 0 {
    //         for _ in 0..<rowDifference {
    //             table.insertRow(position: 0)
    //         }
    //     }

    // }

    // public func setColumnCount(ofTable table: Widget, to columns: Int) {
    //     let table = table as! Grid

    //     let columnDifference = columns - tables.tableSizes[ObjectIdentifier(table)]!.columns
    //     tables.tableSizes[ObjectIdentifier(table)]!.columns = columns
    //     if columnDifference < 0 {
    //         for _ in 0..<(-columnDifference) {
    //             table.removeColumn(position: 0)
    //         }
    //     } else if columnDifference > 0 {
    //         for _ in 0..<columnDifference {
    //             table.insertColumn(position: 0)
    //         }
    //     }

    // }

    // public func setCell(at position: CellPosition, inTable table: Widget, to widget: Widget) {
    //     let table = table as! Grid
    //     table.attach(
    //         child: widget,
    //         left: position.column,
    //         top: position.row,
    //         width: 1,
    //         height: 1
    //     )
    // }

    // MARK: Controls

    public func createButton() -> Widget {
        return Button()
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        // TODO: Update button label color using environment
        let button = button as! Gtk.Button
        button.sensitive = environment.isEnabled
        button.label = label
        button.clicked = { _ in action() }
        button.css.clear()
        button.css.set(properties: Self.cssProperties(for: environment, isControl: true))
    }

    public func createToggle() -> Widget {
        return ToggleButton()
    }

    public func updateToggle(
        _ toggle: Widget,
        label: String,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! Gtk.ToggleButton
        toggle.sensitive = environment.isEnabled
        toggle.label = label
        toggle.toggled = { widget in
            onChange(widget.active)
        }
        toggle.css.clear()
        // This is a control, but we set isControl to false anyway because isControl overrides
        // the button background and makes the on and off states of the toggle look identical.
        toggle.css.set(properties: Self.cssProperties(for: environment, isControl: false))
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! Gtk.ToggleButton

        toggle.withBlockedSignal(named: "toggled") {
            toggle.active = state
        }
    }

    public func createSwitch() -> Widget {
        return Switch()
    }

    public func updateSwitch(
        _ switchWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let switchWidget = switchWidget as! Gtk.Switch
        switchWidget.sensitive = environment.isEnabled
        switchWidget.notifyActive = { widget, _ in
            onChange(widget.active)
        }
    }

    public func setState(ofSwitch switchWidget: Widget, to state: Bool) {
        let switchWidget = switchWidget as! Gtk.Switch

        switchWidget.withBlockedSignal(named: "notify::active") {
            switchWidget.active = state
        }
    }

    public func createCheckbox() -> Widget {
        return Gtk.CheckButton()
    }

    public func updateCheckbox(
        _ checkboxWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let checkboxWidget = checkboxWidget as! Gtk.CheckButton
        checkboxWidget.sensitive = environment.isEnabled
        checkboxWidget.notifyActive = { widget, _ in
            onChange(widget.active)
        }
    }

    public func setState(ofCheckbox checkboxWidget: Widget, to state: Bool) {
        let checkboxWidget = checkboxWidget as! Gtk.CheckButton

        checkboxWidget.withBlockedSignal(named: "notify::active") {
            checkboxWidget.active = state
        }
    }

    public func createSlider() -> Widget {
        let scale = Scale()
        scale.expandHorizontally = true
        return scale
    }

    public func updateSlider(
        _ slider: Widget,
        minimum: Double,
        maximum: Double,
        decimalPlaces: Int,
        environment: EnvironmentValues,
        onChange: @escaping (Double) -> Void
    ) {
        let slider = slider as! Scale
        slider.sensitive = environment.isEnabled
        slider.minimum = minimum
        slider.maximum = maximum
        slider.digits = decimalPlaces
        slider.valueChanged = { widget in
            onChange(widget.value)
        }
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        let slider = slider as! Scale

        slider.withBlockedSignal(named: "value-changed") {
            slider.value = value
        }
    }

    public func createTextField() -> Widget {
        Entry()
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let textField = textField as! Entry
        textField.sensitive = environment.isEnabled
        textField.placeholderText = placeholder
        textField.changed = { widget in
            onChange(widget.text)
        }
        textField.activate = { _ in
            onSubmit()
        }

        textField.css.clear()
        textField.css.set(properties: Self.cssProperties(for: environment, isControl: true))
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField as! Entry
        textField.withBlockedSignal(named: "changed") {
            textField.text = content
        }
    }

    public func getContent(ofTextField textField: Widget) -> String {
        (textField as! Entry).text
    }

    public func createSecureField() -> Widget {
        let entry = Entry()
        entry.visibility = false
        return entry
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        updateTextField(
            secureField,
            placeholder: placeholder,
            environment: environment,
            onChange: onChange,
            onSubmit: onSubmit
        )
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        setContent(ofTextField: secureField, to: content)
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        getContent(ofTextField: secureField)
    }

    public func createTextEditor() -> Widget {
        let textEditor = Gtk.TextView()
        textEditor.wrapMode = .wordCharacter
        return textEditor
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = textEditor as! Gtk.TextView
        textEditor.buffer.changed = { buffer in
            onChange(buffer.text)
        }

        textEditor.css.clear()
        textEditor.css.set(properties: Self.cssProperties(for: environment, isControl: false))
        textEditor.css.set(property: CSSProperty(key: "background", value: "none"))
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditor = textEditor as! Gtk.TextView

        textEditor.buffer.withBlockedSignal(named: "changed") {
            textEditor.buffer.text = content
        }
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        let textEditor = textEditor as! Gtk.TextView
        return textEditor.buffer.text
    }

    public func createPicker(style: BackendPickerStyle) -> Widget {
        if style != .menu {
            let message = "unsupported picker style \(style)"
            logger.critical("\(message)")
            fatalError(message)
        }

        return DropDown(strings: [])
    }

    public func updatePicker(
        _ picker: Widget,
        options: [String],
        environment: EnvironmentValues,
        onChange: @escaping (Int?) -> Void
    ) {
        let picker = picker as! DropDown
        picker.sensitive = environment.isEnabled

        // Check whether the options need to be updated or not (avoiding unnecessary updates is
        // required to prevent an infinite loop caused by the onChange handler)
        var hasChanged = false
        for index in 0..<options.count {
            guard
                let item = gtk_string_list_get_string(picker.model, guint(index)),
                String(cString: item) == options[index]
            else {
                hasChanged = true
                break
            }
        }

        // picker.model could be longer than options
        if gtk_string_list_get_string(picker.model, guint(options.count)) != nil {
            hasChanged = true
        }

        // Apply the current text styles to the dropdown's labels
        var block = CSSBlock(forClass: picker.css.cssClass + " label")
        block.set(properties: Self.cssProperties(for: environment))
        picker.cssProvider.loadCss(from: block.stringRepresentation)

        guard hasChanged else {
            return
        }

        picker.model = gtk_string_list_new(
            UnsafePointer(
                options
                    .map({ UnsafePointer($0.unsafeUTF8Copy().baseAddress) })
                    .unsafeCopy()
                    .baseAddress
            )
        )

        picker.notifySelected = { picker, _ in
            if picker.selected == Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION)) {
                onChange(nil)
            } else {
                onChange(picker.selected)
            }
        }
    }

    public func setSelectedOption(ofPicker picker: Widget, to selectedOption: Int?) {
        let picker = picker as! DropDown
        if selectedOption != picker.selected {
            picker.selected = selectedOption ?? Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
        }
    }

    public func createProgressSpinner() -> Widget {
        let spinner = Spinner()
        spinner.spinning = true
        return spinner
    }

    public func createProgressBar() -> Widget {
        ProgressBar()
    }

    public func updateProgressBar(
        _ widget: Widget,
        progressFraction: Double?,
        environment: EnvironmentValues
    ) {
        let progressBar = widget as! ProgressBar
        progressBar.fraction = progressFraction ?? 0
        let backgroundColor: Gtk.Color
        switch environment.colorScheme {
            case .light:
                backgroundColor = Gtk.Color.eightBit(61, 61, 61, 38)
            case .dark:
                backgroundColor = Gtk.Color.eightBit(90, 90, 90)
        }
        progressBar.cssProvider.loadCss(
            from: """
                trough {
                    background-color: \(CSSProperty.rgba(backgroundColor));
                }
                """
        )
    }

    public func createPopoverMenu() -> PopoverMenu {
        let menu = Gtk.PopoverMenu()
        menu.hasArrow = false
        return menu
    }

    public func updatePopoverMenu(
        _ menu: Menu,
        content: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        // Update menu model and action handlers
        let actionGroup = Gtk.GSimpleActionGroup()
        menu.model = renderMenu(
            content,
            actionMap: actionGroup,
            actionNamespace: "menu",
            actionPrefix: nil,
            environment: environment
        )
        menu.insertActionGroup("menu", actionGroup)

        // Compute styles
        let menuBackground: Gtk.Color
        let menuItemHoverBackground: Gtk.Color
        let foreground = environment.suggestedForegroundColor.resolve(in: environment).gtkColor
        switch environment.colorScheme {
            case .light:
                menuBackground = Gtk.Color(1, 1, 1)
                menuItemHoverBackground = Gtk.Color(0.9, 0.9, 0.9)
            case .dark:
                menuBackground = Gtk.Color(0.175, 0.175, 0.175)
                menuItemHoverBackground = Gtk.Color(1, 1, 1, 0.1)
        }

        // Set styles
        menu.cssProvider.loadCss(
            from: """
                contents {
                    background: \(CSSProperty.rgba(menuBackground));
                }
                contents modelbutton:hover, contents modelbutton:selected {
                    background: \(CSSProperty.rgba(menuItemHoverBackground));
                }
                contents modelbutton label {
                    color: \(CSSProperty.rgba(foreground));
                }
                contents modelbutton {
                    color: \(CSSProperty.rgba(foreground));
                }
                """
        )
    }

    public func showPopoverMenu(
        _ menu: Menu,
        at position: SIMD2<Int>,
        relativeTo widget: Widget,
        closeHandler handleClose: @escaping () -> Void
    ) {
        menu.popUpAtWidget(widget, relativePosition: position)
        menu.onHide = {
            handleClose()
        }
    }

    public func createAlert() -> Alert {
        let dialog = Gtk.MessageDialog()

        // Register a custom shortcut controller to disable the default Escape-to-close
        // action. In future we'll probably want to conditionally re-enable this
        // shortcut in scenarios where we know which action button is the cancel action.
        let controller = gtk_shortcut_controller_new()
        let trigger = gtk_shortcut_trigger_parse_string("Escape")
        let action = gtk_callback_action_new({ _, _, _ in return 1 }, nil, { _ in })
        let shortcut = gtk_shortcut_new(trigger, action)
        gtk_shortcut_controller_add_shortcut(controller, shortcut)
        gtk_widget_add_controller(dialog.widgetPointer, controller)

        return dialog
    }

    public func updateAlert(
        _ alert: Alert,
        title: String,
        actionLabels: [String],
        environment: EnvironmentValues
    ) {
        alert.text = title
        for (i, label) in actionLabels.enumerated() {
            alert.addButton(label: label, responseId: i)
        }
    }

    public func showAlert(
        _ alert: Alert,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        let target = window ?? windows[0]
        let key = ObjectIdentifier(target)

        // One alert per window at a time. If this window already has one up,
        // queue this behind it instead of stacking a second modal dialog.
        guard shownAlert[key] == nil else {
            pendingAlerts[key, default: []].append((alert, target, handleResponse))
            return
        }

        present(alert, on: target, key: key, responseHandler: handleResponse)
    }

    private func present(
        _ alert: Alert,
        on target: Window,
        key: ObjectIdentifier,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        shownAlert[key] = alert
        alert.response = { [weak self] _, responseId in
            guard responseId != Int(UInt32(bitPattern: -4)) else {
                // Ignore escape key for now. Once we support detecting
                // the primary and secondary actions of alerts we can wire
                // this up to whichever action is the default cancellation
                // action.
                return
            }

            alert.destroy()
            self?.advanceAlerts(for: key)
            handleResponse(responseId)
        }
        alert.isModal = true
        alert.isDecorated = false
        alert.setTransient(for: target)
        alert.show()
    }

    /// Clears the shown alert for a window and presents the next one waiting on
    /// it, if any.
    private func advanceAlerts(for key: ObjectIdentifier) {
        shownAlert[key] = nil
        guard var queue = pendingAlerts[key], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        pendingAlerts[key] = queue.isEmpty ? nil : queue
        present(next.alert, on: next.window, key: key, responseHandler: next.handler)
    }

    public func dismissAlert(_ alert: Alert, window: Window?) {
        // The alert may be the one on screen or still waiting in a queue.
        if let key = shownAlert.first(where: { $0.value === alert })?.key {
            alert.destroy()
            advanceAlerts(for: key)
            return
        }
        for (key, queue) in pendingAlerts {
            if let index = queue.firstIndex(where: { $0.alert === alert }) {
                var queue = queue
                queue.remove(at: index)
                pendingAlerts[key] = queue.isEmpty ? nil : queue
                break
            }
        }
        alert.destroy()
    }

    public func showOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        // GtkFileDialog picks the call rather than a mode flag: selecting
        // several files is a different entry point from selecting one, and
        // folders are a third.
        let kind: FileDialogKind = switch openDialogOptions.singleKindSelectionMode {
            case .files:
                openDialogOptions.allowMultipleSelections ? .openMultiple : .openSingle
            case .directories:
                .selectFolder
        }

        showFileChooserDialog(
            fileDialogOptions: fileDialogOptions,
            kind: kind,
            defaultFileName: nil,
            window: window ?? windows[0],
            resultHandler: handleResult
        )
    }

    public func showSaveDialog(
        fileDialogOptions: FileDialogOptions,
        saveDialogOptions: SaveDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<URL>) -> Void
    ) {
        showFileChooserDialog(
            fileDialogOptions: fileDialogOptions,
            kind: .save,
            defaultFileName: saveDialogOptions.defaultFileName,
            window: window ?? windows[0]
        ) { result in
            switch result {
                case .success(let urls):
                    handleResult(.success(urls[0]))
                case .cancelled:
                    handleResult(.cancelled)
            }
        }

    }

    /// Which GtkFileDialog call a request maps to.
    private enum FileDialogKind {
        case openSingle
        case openMultiple
        case selectFolder
        case save
    }

    /// Carries the Swift result handler through GtkFileDialog's C callback.
    ///
    /// The async calls take a `gpointer` of user data, so the closure is boxed,
    /// passed as an opaque pointer and taken back out with a matching
    /// `takeRetainedValue`. That keeps it alive for exactly as long as the
    /// dialog is open, without the retain cycle the old GtkFileChooserNative
    /// code needed for the same purpose.
    private final class FileDialogRequest {
        let kind: FileDialogKind
        let handleResult: (DialogResult<[URL]>) -> Void

        init(kind: FileDialogKind, handleResult: @escaping (DialogResult<[URL]>) -> Void) {
            self.kind = kind
            self.handleResult = handleResult
        }
    }

    private func showFileChooserDialog(
        fileDialogOptions: FileDialogOptions,
        kind: FileDialogKind,
        defaultFileName: String?,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        // GtkFileDialog rather than GtkFileChooserNative, which the GIR marks
        // deprecated. The old API also does not close its dialog on Wayland
        // when no xdg-desktop-portal is present, as under WSLg: the response
        // arrives and the app gets the file, but the window stays on screen.
        // A stock GTK4 app using GtkFileDialog closes correctly in the same
        // session, which is what identified the API rather than our use of it.
        let dialog = gtk_file_dialog_new()
        gtk_file_dialog_set_title(dialog, fileDialogOptions.title)
        gtk_file_dialog_set_accept_label(dialog, fileDialogOptions.defaultButtonLabel)
        gtk_file_dialog_set_modal(dialog, 1)

        if let initialDirectory = fileDialogOptions.initialDirectory {
            let folder = g_file_new_for_path(initialDirectory.path)
            gtk_file_dialog_set_initial_folder(dialog, folder)
            g_object_unref(UnsafeMutableRawPointer(folder))
        }

        if let defaultFileName {
            gtk_file_dialog_set_initial_name(dialog, defaultFileName)
        }

        let request = FileDialogRequest(kind: kind, handleResult: handleResult)
        let userData = Unmanaged.passRetained(request).toOpaque()
        let parent: UnsafeMutablePointer<GtkWindow>? = (window ?? windows.first)?
            .widgetPointer.cast()

        let callback: GAsyncReadyCallback = { source, result, userData in
            guard let userData else { return }
            let request = Unmanaged<FileDialogRequest>.fromOpaque(userData)
                .takeRetainedValue()
            // GtkFileDialog has no named Swift type; it arrives as an opaque
            // pointer, which is what the _finish calls expect.
            let dialog = OpaquePointer(source)

            var error: UnsafeMutablePointer<GError>? = nil
            var urls: [URL] = []

            switch request.kind {
                case .openMultiple:
                    if let list = gtk_file_dialog_open_multiple_finish(dialog, result, &error) {
                        let count = g_list_model_get_n_items(list)
                        for index in 0..<count {
                            guard let item = g_list_model_get_item(list, index) else { continue }
                            if let path = g_file_get_path(OpaquePointer(item)) {
                                urls.append(URL(fileURLWithPath: String(cString: path)))
                                g_free(path)
                            }
                            g_object_unref(item)
                        }
                        g_object_unref(UnsafeMutableRawPointer(list))
                    }
                case .openSingle, .selectFolder, .save:
                    let file =
                        switch request.kind {
                            case .selectFolder:
                                gtk_file_dialog_select_folder_finish(dialog, result, &error)
                            case .save:
                                gtk_file_dialog_save_finish(dialog, result, &error)
                            default:
                                gtk_file_dialog_open_finish(dialog, result, &error)
                        }
                    if let file {
                        if let path = g_file_get_path(file) {
                            urls.append(URL(fileURLWithPath: String(cString: path)))
                            g_free(path)
                        }
                        g_object_unref(UnsafeMutableRawPointer(file))
                    }
            }

            // A dismissed dialog reports an error rather than an empty result,
            // so anything that produced no URLs is treated as a cancellation.
            // That covers the dismissal case and any failure to read the
            // selection back, neither of which the caller can act on
            // differently.
            if let error {
                g_error_free(error)
            }

            if urls.isEmpty {
                request.handleResult(.cancelled)
            } else {
                request.handleResult(.success(urls))
            }
        }

        switch kind {
            case .openSingle:
                gtk_file_dialog_open(dialog, parent, nil, callback, userData)
            case .openMultiple:
                gtk_file_dialog_open_multiple(dialog, parent, nil, callback, userData)
            case .selectFolder:
                gtk_file_dialog_select_folder(dialog, parent, nil, callback, userData)
            case .save:
                gtk_file_dialog_save(dialog, parent, nil, callback, userData)
        }

        // The dialog holds itself for the duration of the async call, so the
        // reference taken by `new` can go now.
        g_object_unref(UnsafeMutableRawPointer(dialog))
    }

    public func createTapGestureTarget(wrapping child: Widget, gesture: TapGesture) -> Widget {
        var gtkGesture: GestureSingle
        switch gesture.kind {
            case .primary:
                gtkGesture = GestureClick()
            case .secondary:
                gtkGesture = GestureClick()
                gtk_gesture_single_set_button(gtkGesture.opaquePointer, guint(GDK_BUTTON_SECONDARY))
            case .longPress:
                gtkGesture = GestureLongPress()
        }
        child.addEventController(gtkGesture)
        return child
    }

    public func updateTapGestureTarget(
        _ tapGestureTarget: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        switch gesture.kind {
            case .primary:
                let gesture =
                    tapGestureTarget.eventControllers.first {
                        $0 is GestureClick
                            && gtk_gesture_single_get_button($0.opaquePointer) == GDK_BUTTON_PRIMARY
                    } as! GestureClick
                gesture.pressed = { _, nPress, _, _ in
                    guard environment.isEnabled, nPress == 1 else {
                        return
                    }
                    action()
                }
            case .secondary:
                let gesture =
                    tapGestureTarget.eventControllers.first {
                        $0 is GestureClick &&
                            (gtk_gesture_single_get_button($0.opaquePointer) ==
                                GDK_BUTTON_SECONDARY)
                    } as! GestureClick
                gesture.pressed = { _, nPress, _, _ in
                    guard environment.isEnabled, nPress == 1 else {
                        return
                    }
                    action()
                }
            case .longPress:
                let gesture =
                    tapGestureTarget.eventControllers.lazy.compactMap { $0 as? GestureLongPress }
                        .first!
                gesture.pressed = { _, _, _ in
                    guard environment.isEnabled else {
                        return
                    }
                    action()
                }
        }
    }

    public func createHoverTarget(wrapping child: Widget) -> Widget {
        child.addEventController(EventControllerMotion())
        return child
    }

    public func updateHoverTarget(
        _ hoverTarget: Widget,
        environment: EnvironmentValues,
        action: @escaping (Bool) -> Void
    ) {
        let gesture =
            hoverTarget.eventControllers.first { $0 is EventControllerMotion }
                as! EventControllerMotion
        gesture.enter = { _, _, _ in
            guard environment.isEnabled else { return }
            action(true)
        }
        gesture.leave = { _ in
            guard environment.isEnabled else { return }
            action(false)
        }
    }

    // MARK: Drag and drop

    public func createDropTarget(wrapping child: Widget) -> Widget {
        child.addEventController(DropTarget())
        return child
    }

    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {
        let target =
            dropTarget.eventControllers.first { $0 is DropTarget } as! DropTarget

        // Map the cross-platform type identifiers onto the two GTypes the GTK
        // drop target negotiates over. An unknown identifier is simply not
        // offered, so a drag of that type is refused rather than mishandled.
        let acceptsFiles = acceptedTypes.contains(.fileURL)
        let acceptsText = acceptedTypes.contains(.plainText)
        target.setAcceptedTypes(fileURLs: acceptsFiles, text: acceptsText)

        target.onHover = { hovering in
            guard environment.isEnabled else { return }
            onHover(hovering)
        }

        // GTK delivers the payload as one value of the negotiated type. Rebuild
        // the DropItem with the matching identifier and the bytes verbatim -- a
        // file drop keeps its text/uri-list form, which is the platform
        // difference P25 exists to show.
        target.onDrop = { kind, contents in
            guard environment.isEnabled else { return false }
            let item: DropItem
            switch kind {
                case .fileURIList:
                    item = DropItem(type: .fileURL, data: Data(contents.utf8))
                case .text:
                    item = DropItem(type: .plainText, data: Data(contents.utf8))
            }
            return onDrop([item])
        }
    }

    // MARK: Paths

    public func createPathWidget() -> Widget {
        DrawingArea()
    }

    public func createPath() -> Path {
        Path()
    }

    public func updatePath(
        _ path: Path,
        _ source: SwiftCrossUI.Path,
        bounds: SwiftCrossUI.Path.Rect,
        pointsChanged: Bool,
        environment: EnvironmentValues
    ) {
        path.path = source
    }

    /// Assumes that the path backing widget has already been given the correct
    /// size.
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeColor: SwiftCrossUI.Color.Resolved,
        fillColor: SwiftCrossUI.Color.Resolved,
        overrideStrokeStyle: StrokeStyle?
    ) {
        let drawingArea = container as! Gtk.DrawingArea

        // We don't actually care about leaking backends, but might as well use
        // a weak reference anyway.
        drawingArea.setDrawFunc { [weak self] cairo, _, _ in
            guard let self, let path = path.path else {
                return
            }

            let fillRule: cairo_fill_rule_t
            switch path.fillRule {
                case .evenOdd:
                    fillRule = CAIRO_FILL_RULE_EVEN_ODD
                case .winding:
                    fillRule = CAIRO_FILL_RULE_WINDING
            }
            cairo_set_fill_rule(cairo, fillRule)

            let strokeStyle = overrideStrokeStyle ?? path.strokeStyle
            let strokeCap: cairo_line_cap_t
            switch strokeStyle.cap {
                case .butt:
                    strokeCap = CAIRO_LINE_CAP_BUTT
                case .round:
                    strokeCap = CAIRO_LINE_CAP_ROUND
                case .square:
                    strokeCap = CAIRO_LINE_CAP_SQUARE
            }
            cairo_set_line_cap(cairo, strokeCap)

            let strokeJoin: cairo_line_join_t
            switch strokeStyle.join {
                case .bevel:
                    strokeJoin = CAIRO_LINE_JOIN_BEVEL
                case .miter(let limit):
                    strokeJoin = CAIRO_LINE_JOIN_MITER
                    cairo_set_miter_limit(cairo, limit)
                case .round:
                    strokeJoin = CAIRO_LINE_JOIN_ROUND
            }
            cairo_set_line_join(cairo, strokeJoin)

            cairo_set_line_width(cairo, strokeStyle.width)

            self.renderPathActions(path.actions, to: cairo)

            let fillPattern = cairo_pattern_create_rgba(
                Double(fillColor.red),
                Double(fillColor.green),
                Double(fillColor.blue),
                Double(fillColor.opacity)
            )
            cairo_set_source(cairo, fillPattern)
            cairo_fill_preserve(cairo)
            cairo_pattern_destroy(fillPattern)

            let strokePattern = cairo_pattern_create_rgba(
                Double(strokeColor.red),
                Double(strokeColor.green),
                Double(strokeColor.blue),
                Double(strokeColor.opacity)
            )
            cairo_set_source(cairo, strokePattern)
            cairo_stroke(cairo)
            cairo_pattern_destroy(strokePattern)
        }
    }

    private func renderPathActions(
        _ actions: [SwiftCrossUI.Path.Action],
        to cairo: OpaquePointer
    ) {
        for action in actions {
            switch action {
                case .transform(let transform):
                    var matrix = cairo_matrix_t()
                    matrix.xx = transform.linearTransform.x
                    matrix.xy = transform.linearTransform.y
                    matrix.yx = transform.linearTransform.z
                    matrix.yy = transform.linearTransform.w
                    matrix.x0 = transform.translation.x
                    matrix.y0 = transform.translation.y
                    cairo_transform(cairo, &matrix)
                default:
                    break
            }
        }

        for (index, action) in actions.enumerated() {
            switch action {
                case .moveTo(let point):
                    cairo_move_to(cairo, point.x, point.y)
                case .lineTo(let point):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    cairo_line_to(cairo, point.x, point.y)
                case .quadCurve(let control, let end):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    var startX = 0.0
                    var startY = 0.0
                    cairo_get_current_point(cairo, &startX, &startY)
                    let start = SIMD2(startX, startY)
                    let control1 = (start + 2 * control) / 3
                    let control2 = (end + 2 * control) / 3
                    cairo_curve_to(
                        cairo,
                        control1.x,
                        control1.y,
                        control2.x,
                        control2.y,
                        end.x,
                        end.y
                    )
                case .cubicCurve(let control1, let control2, let end):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    cairo_curve_to(
                        cairo,
                        control1.x,
                        control1.y,
                        control2.x,
                        control2.y,
                        end.x,
                        end.y
                    )
                case .rectangle(let rect):
                    cairo_rectangle(
                        cairo,
                        rect.origin.x,
                        rect.origin.y,
                        rect.size.x,
                        rect.size.y
                    )
                case .circle(let center, let radius):
                    cairo_arc(cairo, center.x, center.y, radius, 0, 2 * .pi)
                case .arc(
                let center,
                let radius,
                let startAngle,
                let endAngle,
                let clockwise
            ):
                    let arcFunc = clockwise ? cairo_arc : cairo_arc_negative
                    arcFunc(
                        cairo,
                        center.x,
                        center.y,
                        radius,
                        startAngle,
                        endAngle
                    )
                case .transform(let transform):
                    var matrix = cairo_matrix_t()
                    matrix.xx = transform.linearTransform.x
                    matrix.xy = transform.linearTransform.y
                    matrix.yx = transform.linearTransform.z
                    matrix.yy = transform.linearTransform.w
                    matrix.x0 = transform.translation.x
                    matrix.y0 = transform.translation.y
                    cairo_matrix_invert(&matrix)
                    cairo_transform(cairo, &matrix)
                case .subpath(let subpathActions):
                    renderPathActions(subpathActions, to: cairo)
            }
        }
    }

    // MARK: Tables

    // defaultTableRowContentHeight and defaultTableCellVerticalPadding are
    // already declared near the top of this type, alongside the other backend
    // constants -- they were there before Tables was conformed to, waiting for
    // the rest.
    // defaultTableRowContentHeight 與 defaultTableCellVerticalPadding 已在本型別開頭、與其他
    // backend 常數一同宣告——它們在 Tables 被實作之前就已存在，等著其餘部分補上。

    public func createTable() -> Widget {
        Gtk.Table()
    }

    public func setRowCount(ofTable table: Widget, to rows: Int) {
        (table as! Gtk.Table).setRowCount(rows)
    }

    public func setColumnLabels(
        ofTable table: Widget,
        to labels: [String],
        environment: EnvironmentValues
    ) {
        let table = table as! Gtk.Table
        table.setColumnLabels(labels)
        table.css.clear()
        table.css.set(properties: Self.cssProperties(for: environment))
    }

    public func setCells(
        ofTable table: Widget,
        to cells: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        (table as! Gtk.Table).setCells(cells, rowHeights: rowHeights)
    }

    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {
        (table as! Gtk.Table).setTextSelectable(isSelectable)
    }

    public func createDatePicker() -> Widget {
        let widget = Gtk.Calendar()
        widget.date = Date()
        return widget
    }

    public func updateDatePicker(
        _ datePicker: Widget,
        environment: EnvironmentValues,
        date: Date,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        onChange: @escaping (Date) -> Void
    ) {
        if components.contains(.hourAndMinute) {
            debugLogOnce("Warning: time picker is unimplemented on GtkBackend")
        }

        let calendarWidget = datePicker as! Gtk.Calendar
        calendarWidget.date = date
        calendarWidget.daySelected = { calendarWidget in
            let date = max(range.lowerBound, min(calendarWidget.date, range.upperBound))
            calendarWidget.date = date
            onChange(date)
        }
        calendarWidget.sensitive = environment.isEnabled
        calendarWidget.css.clear()
        calendarWidget.css.set(properties: Self.cssProperties(for: environment, isControl: true))
    }

    // MARK: Helpers

    private func wrapInCustomRootContainer(_ widget: Widget) -> Widget {
        let container = CustomRootWidget()
        container.setChild(to: widget)
        return container
    }

    private static func cssProperties(
        for environment: EnvironmentValues,
        isControl: Bool = false
    ) -> [CSSProperty] {
        var properties: [CSSProperty] = []
        properties.append(
            .foregroundColor(
                environment.suggestedForegroundColor.resolve(in: environment).gtkColor
            )
        )
        let font = environment.resolvedFont
        switch font.identifier.kind {
            case .system:
                properties.append(.fontSize(font.pointSize))
                // For some reason I had to tweak these a bit to make them match
                // up with AppKit's font weights. The Gtk3 backend, since
                // removed, needed no such tweaking; it matched SwiftUI's text
                // layout and rendering remarkably well.
                let weightNumber =
                    switch font.weight {
                        case .ultraLight:
                            200
                        case .thin:
                            300
                        case .light:
                            400
                        case .regular:
                            500
                        case .medium:
                            600
                        case .semibold:
                            700
                        case .bold:
                            700
                        case .heavy:
                            800
                        case .black:
                            900
                    }
                properties.append(.fontWeight(weightNumber))
                switch font.design {
                    case .monospaced:
                        properties.append(.fontFamily("monospace"))
                    case .default:
                        break
                }
        }

        if font.isItalic {
            properties.append(.fontStyle("italic"))
        }

        if isControl {
            switch environment.colorScheme {
                case .light:
                    properties.append(.backgroundColor(Color(0.9, 0.9, 0.9, 1)))
                case .dark:
                    properties.append(.backgroundColor(Color(1, 1, 1, 0.1)))
            }
            properties.append(CSSProperty(key: "border", value: "none"))
            properties.append(CSSProperty(key: "box-shadow", value: "none"))
        }

        return properties
    }

    public func createSheet(content: Widget) -> Sheet {
        let sheet = Sheet()
        sheet.setChild(content)

        // Listen for interactive dismissals
        sheet.onCloseRequest = { [weak self, weak sheet] _ in
            guard let self, let sheet else {
                return
            }

            self.runInMainThread {
                self.dismissSheet(sheet)
                sheet.onDismiss?()
            }
        }

        // Allow the escape key to be used to dismiss interactively dismissible
        // sheets.
        sheet.setEscapeKeyPressedHandler { [weak self, weak sheet] in
            guard let self, let sheet, !sheet.interactiveDismissDisabled else {
                return
            }

            self.runInMainThread {
                self.dismissSheet(sheet)
                sheet.onDismiss?()
            }
        }

        return sheet
    }

    public func updateSheet(
        _ sheet: Sheet,
        window: Window,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void,
        cornerRadius: Double?,
        detents: [PresentationDetent],
        dragIndicatorVisibility: Visibility,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        interactiveDismissDisabled: Bool
    ) {
        sheet.size = Size(width: size.x, height: size.y)
        sheet.onDismiss = onDismiss

        // Add a slight border to not be just a flat corner
        sheet.css.clear()
        sheet.css.set(
            property: .border(
                color: SwiftCrossUI.Color.gray.resolve(in: environment).gtkColor,
                width: 1
            )
        )

        // Respect corner radius and background Color
        let radius = cornerRadius.map(Int.init) ?? defaultSheetCornerRadius
        sheet.css.set(property: .cornerRadius(radius))
        if let backgroundColor {
            sheet.css.set(property: .backgroundColor(backgroundColor.gtkColor))
        }

        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        // - detents are only supported on mobile so we ignore them.
        // - dragIndicatorVisibility is only supported on mobile so we ignore it.
    }

    public func presentSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        let parent = parentSheet ?? window
        sheet.isModal = true
        sheet.isDecorated = false
        sheet.destroyWithParent = true
        if let parentSheet {
            parentSheet.nestedSheet = sheet
        }
        sheet.setTransient(for: parent)
        sheet.present()
    }

    public func dismissSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        dismissSheet(sheet)
        parentSheet?.nestedSheet = nil
    }

    private func dismissSheet(_ sheet: Sheet) {
        // Dismiss the nested sheets from the topmost down. We could use
        // recursion here, but then unbounded nested sheets would allow for
        // users to cause programs to run out of stack relatively easily.
        var nestedSheets: [Sheet] = []
        var currentSheet = sheet
        while let nestedSheet = currentSheet.nestedSheet {
            nestedSheets.append(nestedSheet)
            currentSheet = nestedSheet
        }
        for nestedSheet in nestedSheets.reversed() {
            nestedSheet.destroy()
            nestedSheet.onDismiss?()
        }

        sheet.destroy()
    }

    public func size(ofSheet sheet: Sheet) -> SIMD2<Int> {
        return SIMD2(x: sheet.size.width, y: sheet.size.height)
    }
}

extension UnsafeMutablePointer {
    func cast<T>() -> UnsafeMutablePointer<T> {
        let pointer = UnsafeRawPointer(self).bindMemory(to: T.self, capacity: 1)
        return UnsafeMutablePointer<T>(mutating: pointer)
    }
}

private final class SelectableListState {
    var selection: Int? = nil
    var rowCount = 0
    var isProgrammaticSelectionUpdate = false
    var isClearingNilSelection = false
}

/// A custom label subclass that supports ellipsizing multi-line text. Regular
/// `Label`s only display a single line of text when ellipsizing is enabled
/// because they don't pass their size request to their underlying Pango layout.
/// A `Paned` that remembers whether its divider has been placed using real
/// layout numbers yet.
///
/// The layout system treats the sidebar width as backend-owned state: it reads
/// `sidebarWidth(ofSplitView:)` and lays the panes out around whatever comes
/// back, only ever passing bounds the other way. Without this flag there is no
/// telling the initial guess apart from a width the user chose, so the divider
/// would either ignore its content forever or fight every drag.
class CustomPaned: Paned {
    var hasEstablishedPosition = false
}

class CustomLabel: Label {
    override func setSizeRequest(width: Int, height: Int) {
        super.setSizeRequest(width: width, height: height)

        // Override the label's layout height. We do this so that the label grows
        // vertically to fill available space even though we have ellipsizing
        // enabled (which generally causes labels to limit themselves to a single line).
        //
        // This code relies on the assumption that the layout won't get recreated
        // until after the label gets rendered. The docs recommend against mutating
        // the layout returned by gtk_label_get_layout.
        //
        // Ideally we'd use an Inscription instead, because it has this behavior
        // by default, but that's only available from Gtk 4.8, and the predecessor
        // CellRendererText isn't a widget.
        let layout = gtk_label_get_layout(opaquePointer)
        pango_layout_set_height(
            layout,
            Int32(
                (Double(height) * Double(PANGO_SCALE))
                    .rounded(.towardZero)
            )
        )
    }
}

final class TooltipContainer: Fixed {
    private var tooltip: UnsafeMutableBufferPointer<CChar>

    init(_ child: Widget) {
        self.tooltip = UnsafeMutableBufferPointer(start: nil, count: 0)
        super.init()
        self.put(child, x: 0, y: 0)
    }

    deinit {
        deallocateText()
    }

    func setTooltip(text: String) {
        text.utf8CString.withUnsafeBufferPointer { buf in
            // TODO(bbrk24): Should this be `>=` or `==`?
            if tooltip.count >= buf.count {
                strcpy(tooltip.baseAddress!, buf.baseAddress!)
            } else {
                deallocateText()

                tooltip = .allocate(capacity: buf.count)
                tooltip.initialize(from: buf)
            }
        }

        gtk_widget_set_tooltip_text(widgetPointer, tooltip.baseAddress)
    }

    private func deallocateText() {
        if tooltip.count > 0 {
            tooltip.deinitialize()
            tooltip.deallocate()
        }

        tooltip = UnsafeMutableBufferPointer(start: nil, count: 0)
    }
}

// This class is incomplete and unused. It was meant to implement time components for DatePicker,
// but I couldn't get the spin buttons to work. TODOs include:
// - Fix the spin buttons
// - Update the strings in the AM/PM picker when the locale changes
// - Replace the calls to calendar.date(bySetting:value:of:) with something that actually does what we need
// - Implement range when possible
@available(macOS 13, *)
final class TimePicker: Box {
    private var hourCycle: Locale.HourCycle
    private let hourPicker: SpinButton
    private let hourMinuteSeparator = Label(string: ":")
    private let minutePicker = SpinButton(range: 0, max: 59, step: 1)
    private var minuteSecondSeparator: Label?
    private var secondPicker: SpinButton?
    private var amPmPicker: DropDown?

    var onChange: ((Date) -> Void)?

    init() {
        let hourCycle = Locale.current.hourCycle

        self.hourCycle = hourCycle
        self.hourPicker = SpinButton(
            range: TimePicker.minHour(for: hourCycle),
            max: TimePicker.maxHour(for: hourCycle),
            step: 1
        )

        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0))

        self.hourPicker.wrap = true
        self.hourPicker.orientation = .vertical
        self.hourPicker.numeric = true
        self.minutePicker.wrap = true
        self.minutePicker.orientation = .vertical
        self.minutePicker.numeric = true

        self.add(self.hourPicker)
        self.add(self.hourMinuteSeparator)
        self.add(self.minutePicker)
    }

    func setEnabled(to isEnabled: Bool) {
        hourPicker.sensitive = isEnabled
    }

    private static func minHour(for hourCycle: Locale.HourCycle) -> Double {
        switch hourCycle {
            case .zeroToEleven, .zeroToTwentyThree: 0
            case .oneToTwelve, .oneToTwentyFour: 1
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }

    private static func maxHour(for hourCycle: Locale.HourCycle) -> Double {
        switch hourCycle {
            case .zeroToEleven: 11
            case .oneToTwelve: 12
            case .zeroToTwentyThree: 23
            case .oneToTwentyFour: 24
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }

    func update(calendar: Foundation.Calendar, date: Date, showSeconds: Bool) {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)

        if showSeconds {
            let secondsRange = calendar.range(of: .second, in: .minute, for: date) ?? 0..<60
            if let secondPicker {
                secondPicker.setRange(
                    min: Double(secondsRange.lowerBound),
                    max: Double(secondsRange.upperBound - 1)
                )
            } else {
                minuteSecondSeparator = Label(string: ":")
                secondPicker = SpinButton(
                    range: Double(secondsRange.lowerBound),
                    max: Double(secondsRange.upperBound - 1),
                    step: 1
                )
                secondPicker!.numeric = true
                secondPicker!.wrap = true
                secondPicker!.text = "\(components.second!)"
                insert(child: minuteSecondSeparator!, after: minutePicker)
                insert(child: secondPicker!, after: minuteSecondSeparator!)
            }
        } else {
            if let minuteSecondSeparator {
                remove(minuteSecondSeparator)
                self.minuteSecondSeparator = nil
            }
            if let secondPicker {
                remove(secondPicker)
                self.secondPicker = nil
            }
        }

        let minutesRange = calendar.range(of: .minute, in: .hour, for: date) ?? 0..<60
        minutePicker.setRange(
            min: Double(minutesRange.lowerBound),
            max: Double(minutesRange.upperBound - 1)
        )
        minutePicker.text = "\(components.minute!)"
        minutePicker.valueChanged = { [unowned self] minutePicker in
            guard
                let value = Int(exactly: minutePicker.value),
                let newDate = calendar.date(bySetting: .minute, value: value, of: date)
            else {
                return
            }
            self.onChange?(newDate)
        }

        let hoursRange = calendar.range(of: .hour, in: .day, for: date)
        self.hourCycle = (calendar.locale ?? .current).hourCycle
        let effectiveHours = hoursRange?.map {
            TimePicker.transformToRange($0, hourCycle: self.hourCycle)
        }

        hourPicker.setRange(
            min: effectiveHours?.min().map(Double.init(_:))
                ?? TimePicker.minHour(for: self.hourCycle),
            max: effectiveHours?.max().map(Double.init(_:))
                ?? TimePicker.maxHour(for: self.hourCycle)
        )

        if self.hourCycle == .oneToTwelve || self.hourCycle == .zeroToEleven {
            if let amPmPicker {
                // update strings if necessary
            } else {
                amPmPicker = DropDown(strings: [calendar.amSymbol, calendar.pmSymbol])
                add(amPmPicker!)
            }
        } else {
            if let amPmPicker {
                remove(amPmPicker)
                self.amPmPicker = nil
            }
        }

        hourPicker.text =
            "\(TimePicker.transformToRange(components.hour!, hourCycle: self.hourCycle))"
        hourPicker.valueChanged = { [unowned self] hourPicker in
            guard
                let value = Int(exactly: hourPicker.value),
                let newDate = calendar.date(bySetting: .hour, value: value, of: date)
            else {
                return
            }
            self.onChange?(newDate)
        }
    }

    private static func transformToRange(_ value: Int, hourCycle: Locale.HourCycle) -> Int {
        switch hourCycle {
            case .zeroToEleven: value % 12
            case .oneToTwelve: (value + 11) % 12 + 1
            case .zeroToTwentyThree: value % 24
            case .oneToTwentyFour: (value + 23) % 24 + 1
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }
}
