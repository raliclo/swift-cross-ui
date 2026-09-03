//
//  Copyright © 2015 Tomas Linhart. All rights reserved.
//

import CGtk

open class Window: Widget {
    public var child: Widget?

    public convenience init() {
        self.init(gtk_window_new())
        registerSignals()
    }

    @GObjectProperty(named: "title") public var title: String?
    @GObjectProperty(named: "resizable") public var resizable: Bool
    @GObjectProperty(named: "deletable") public var deletable: Bool
    @GObjectProperty(named: "modal") public var isModal: Bool
    @GObjectProperty(named: "decorated") public var isDecorated: Bool
    @GObjectProperty(named: "destroy-with-parent") public var destroyWithParent: Bool

    public var isActive: Bool {
        gtk_window_is_active(castedPointer()).toBool()
    }

    public var isMaximized: Bool {
        gtk_window_is_maximized(castedPointer()).toBool()
    }

    public var isFullscreen: Bool {
        gtk_window_is_fullscreen(castedPointer()).toBool()
    }

    /// Asks the window manager to maximize the window. It is a request, not a
    /// command: the window manager may ignore it, and it does not take effect
    /// synchronously, so ``isMaximized`` can still be false immediately after.
    public func maximize() {
        gtk_window_maximize(castedPointer())
    }

    public func unmaximize() {
        gtk_window_unmaximize(castedPointer())
    }

    public func setTransient(for other: Window) {
        gtk_window_set_transient_for(castedPointer(), other.castedPointer())
    }

    /// The window must not be used after destruction.
    public func destroy() {
        gtk_window_destroy(castedPointer())
    }

    public var defaultSize: Size {
        get {
            var width: gint = 0
            var height: gint = 0
            gtk_window_get_default_size(castedPointer(), &width, &height)

            return Size(width: Int(width), height: Int(height))
        }
        set(size) {
            gtk_window_set_default_size(castedPointer(), gint(size.width), gint(size.height))
        }
    }

    public var size: Size {
        get {
            // TODO: The default size is the current size of the window unless we're
            //   in full screen. But we can't simply use the widget size, cause that
            //   doesn't work before the first proper update or something like that.
            defaultSize
        }
        set {
            // We set the 'default size' here because setting the size of the window
            // actually sets the window's minimum size. Whereas the 'default size' is
            // just the current size of the window, except when the window is in full
            // screen, in which case the 'default size' is the size that the window
            // should return to when it leaves full screen.
            defaultSize = newValue
        }
    }

    public func setMinimumSize(to minimumSize: Size) {
        gtk_widget_set_size_request(
            castedPointer(),
            gint(minimumSize.width),
            gint(minimumSize.height)
        )
    }

    public func setChild(_ child: Widget) {
        self.child?.parentWidget = nil
        self.child = child
        gtk_window_set_child(castedPointer(), child.widgetPointer)
        child.parentWidget = self
    }

    public func removeChild() {
        gtk_window_set_child(castedPointer(), nil)
        child?.parentWidget = nil
        child = nil
    }

    public func getChild() -> Widget? {
        return child
    }

    /// The natural height of this window's titlebar widget, or nil when it has
    /// none.
    ///
    /// The point of asking is that `gtk_widget_measure` answers WITHOUT a size
    /// allocation, so a caller can know what the decoration will cost before the
    /// window is mapped -- which is the only way to size a window correctly on
    /// the first layout pass rather than correcting it on the second.
    ///
    /// nil is a real answer, not a failure: `gtk_window_get_titlebar` returns
    /// NULL when nothing has called `gtk_window_set_titlebar`, and GTK then
    /// draws whatever decoration the platform gives. There is no widget to
    /// measure in that case and the caller has to fall back to measuring after
    /// the fact.
    ///
    /// 本視窗 titlebar widget 的自然高度；若沒有 titlebar 則為 nil。
    ///
    /// 之所以問這件事，是因為 `gtk_widget_measure` **不需要 size allocation** 就能回答，
    /// 因此呼叫端可以在視窗被 map 之前就知道裝飾的成本——而那是「第一次版面計算就把視窗開對」
    /// 的唯一途徑，否則就只能在第二次計算時修正。
    ///
    /// nil 是一個真正的答案，不是失敗：未曾呼叫 `gtk_window_set_titlebar` 時
    /// `gtk_window_get_titlebar` 會回傳 NULL，此時 GTK 畫的是平台給的裝飾。那種情況下沒有
    /// widget 可量，呼叫端只能退回事後量測。
    public var titlebarNaturalHeight: Int? {
        guard let titlebar = gtk_window_get_titlebar(castedPointer()) else {
            return nil
        }
        var minimum: gint = 0
        var natural: gint = 0
        var minimumBaseline: gint = 0
        var naturalBaseline: gint = 0
        gtk_widget_measure(
            titlebar,
            GTK_ORIENTATION_VERTICAL,
            -1,
            &minimum,
            &natural,
            &minimumBaseline,
            &naturalBaseline
        )
        return Int(natural)
    }

    public func present() {
        gtk_window_present(castedPointer())
    }

    public func close() {
        gtk_window_close(castedPointer())
    }

    public func setEscapeKeyPressedHandler(to handler: (() -> Void)?) {
        escapeKeyPressed = handler

        guard escapeKeyEventController == nil else { return }

        let keyEventController = EventControllerKey()
        keyEventController.keyPressed = { [weak self] _, keyval, _, _ in
            // Returning true stops the key propagating, which is the point of
            // handling it: before the generated signal could return a value
            // (#594) Escape was handled here *and* passed on to everything below.
            // Anything else returns false so it carries on as normal.
            // 回傳 true 會停止該按鍵繼續傳播，而這正是「處理它」的意義：在產生的 signal 能夠回傳值
            // （#594）之前，Escape 會在此被處理，同時仍被往下傳給其他所有元件。其餘按鍵回傳 false，
            // 使其照常繼續傳播。
            guard keyval == GDK_KEY_Escape else { return false }
            self?.escapeKeyPressed?()
            return true
        }
        escapeKeyEventController = keyEventController
        addEventController(keyEventController)
    }

    open override func registerSignals() {
        addSignal(name: "close-request") { [weak self] () in
            guard let self else { return }
            self.onCloseRequest?(self)
        }
        addSignal(name: "destroy") { [weak self] () in
            guard let self else { return }
            self.onDestroy?(self)
        }
        addSignal(name: "notify::scale-factor") { [weak self] () in
            guard let self else { return }
            self.onScaleFactorChange?(self)
        }
    }

    private var escapeKeyEventController: EventControllerKey?
    public var onCloseRequest: ((Window) -> Void)?
    public var onDestroy: ((Window) -> Void)?

    /// Fires when GTK changes the scale factor it lays this window out at.
    ///
    /// The property rather than a display or monitor signal: GTK's scale factor
    /// is the buffer scale it actually used, an integer by design, not the
    /// fraction a display advertises. Watching the display would fire on changes
    /// GTK did not act on and miss the moment it did.
    ///
    /// Public because a backend cannot reach `addSignal`, which is internal to
    /// this module -- registering the signal has to happen in here.
    ///
    /// 當 GTK 改變它為此視窗排版所用的 scale factor 時觸發。
    ///
    /// 監聽的是該屬性，而非顯示器或螢幕的訊號：GTK 的 scale factor 是它實際使用的 buffer
    /// scale，依設計為整數，而非顯示器所宣稱的小數。改為監聽顯示器，會在 GTK 並未據以動作的變化
    /// 上觸發，卻錯過它真正動作的那一刻。
    ///
    /// 之所以公開，是因為 backend 取用不到對本模組為 internal 的 `addSignal`——註冊訊號這件事
    /// 必須發生在這裡。
    public var onScaleFactorChange: ((Window) -> Void)?
    public var escapeKeyPressed: (() -> Void)?
}

final class ValueBox<T> {
    let value: T
    init(value: T) {
        self.value = value
    }
}
