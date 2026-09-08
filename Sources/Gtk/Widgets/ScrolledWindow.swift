import CGtk

public class ScrolledWindow: Widget {
    var child: Widget?

    public convenience init() {
        self.init(gtk_scrolled_window_new())
    }

    open override func didMoveToParent() {
        super.didMoveToParent()
    }

    /// Fires when a scroll goes past an edge, carrying which edge it was.
    ///
    /// The value is a `GtkPositionType`: 0 left, 1 right, 2 top, 3 bottom. It is
    /// what `.refreshable` watches for -- overshooting the top edge is GTK's
    /// pull-to-refresh gesture.
    ///
    /// **This exists because the signal cannot be connected from `GtkBackend`.**
    /// `GtkBackend+Refreshable.swift` arrived from the macOS side calling
    /// `scrolledWindow.addSignal(name: "edge-overshot") { (edge: Int) in ... }`,
    /// which fails twice over: `addSignal` is internal to this module, and the
    /// overload that takes no marshaller takes a NO-ARGUMENT callback, so the
    /// edge could not have been received even if the access level allowed it.
    /// Neither error could be seen from a Mac, where GtkBackend is not built.
    ///
    /// It is the same layering the toolbar hit hours earlier with
    /// `castedPointer`: raw GTK belongs in this module, and a backend gets a
    /// typed API. The compiler is pointing at the boundary rather than at an
    /// obstacle.
    ///
    /// 當捲動越過某個邊緣時觸發，並攜帶越過的是哪一個邊緣。
    ///
    /// 該值是 `GtkPositionType`：0 左、1 右、2 上、3 下。這正是 `.refreshable` 所監看的東西——越過上緣
    /// 就是 GTK 的下拉重新整理手勢。
    ///
    /// **它之所以存在，是因為該訊號無法從 `GtkBackend` 連接。** 由 macOS 側送來的
    /// `GtkBackend+Refreshable.swift` 寫的是
    /// `scrolledWindow.addSignal(name: "edge-overshot") { (edge: Int) in ... }`，而那有兩重錯誤：
    /// `addSignal` 對本模組而言是 internal，且「不帶 marshaller」的那個多載收的是**無參數**的 callback
    /// ——因此即使存取層級允許，那個 edge 值也接收不到。這兩個錯誤在 Mac 上都看不見，因為那裡不會建置
    /// GtkBackend。
    ///
    /// 這與數小時前工具列在 `castedPointer` 上撞到的是同一個分層：原始 GTK 呼叫屬於本模組，backend 拿到
    /// 的是帶型別的 API。編譯器指出的是邊界，不是障礙。
    public var edgeOvershot: ((ScrolledWindow, Int) -> Void)?

    open override func registerSignals() {
        super.registerSignals()

        let handler0:
            @convention(c) (UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer) -> Void = {
                _, value1, data in
                SignalBox1<Int>.run(data, value1)
            }

        addSignal(name: "edge-overshot", handler: gCallback(handler0)) {
            [weak self] (param0: Int) in
            guard let self else { return }
            self.edgeOvershot?(self, param0)
        }
    }

    @GObjectProperty(named: "min-content-width") public var minimumContentWidth: Int
    @GObjectProperty(named: "max-content-width") public var maximumContentWidth: Int

    @GObjectProperty(named: "min-content-height") public var minimumContentHeight: Int
    @GObjectProperty(named: "max-content-height") public var maximumContentHeight: Int

    @GObjectProperty(named: "propagate-natural-height") public var propagateNaturalHeight: Bool
    @GObjectProperty(named: "propagate-natural-width") public var propagateNaturalWidth: Bool

    public func setScrollBarPresence(hasVerticalScrollBar: Bool, hasHorizontalScrollBar: Bool) {
        gtk_scrolled_window_set_policy(
            opaquePointer,
            hasHorizontalScrollBar ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER,
            hasVerticalScrollBar ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER
        )
    }

    public func setChild(_ child: Widget) {
        self.child?.parentWidget = nil
        self.child = child
        gtk_scrolled_window_set_child(opaquePointer, child.widgetPointer)
        child.parentWidget = self
    }

    public func removeChild() {
        gtk_scrolled_window_set_child(opaquePointer, nil)
        child?.parentWidget = nil
        child = nil
    }

    public func getChild() -> Widget? {
        return child
    }
}
