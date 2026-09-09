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

    /// Scrolls so that `child` is visible, optionally placing it at `anchor`.
    ///
    /// **Not `gtk_viewport_scroll_to`, which is GTK 4.12 and this package builds
    /// against < 4.10** -- the same floor that makes `GtkBackend.swift:2009` use
    /// `gtk_show_uri` rather than `gtk_uri_launcher_launch`. What is available
    /// is `gtk_widget_compute_point`, which has been there since 4.0, so the
    /// child's position is computed here and the adjustment is set directly.
    ///
    /// That means no animation. `gtk_adjustment_set_value` is instantaneous, and
    /// GTK 4's kinetic scrolling is driven by input rather than by the API, so
    /// there is nothing to animate through. Said here rather than discovered:
    /// a scroll that arrives instantly on one platform and glides on four reads
    /// as a stutter.
    ///
    /// A nil anchor takes the shortest scroll that makes the child visible,
    /// which is what SwiftUI's nil anchor means; an anchor asks for a position.
    ///
    /// 捲動使 `child` 可見,並可選擇性地把它放在 `anchor` 的位置。
    ///
    /// **不是 `gtk_viewport_scroll_to`,那需要 GTK 4.12,而本套件建置於 < 4.10 之上**——正是那個下限
    /// 使得 `GtkBackend.swift:2009` 採用 `gtk_show_uri` 而非 `gtk_uri_launcher_launch`。可用的是
    /// `gtk_widget_compute_point`,它自 4.0 就存在,因此子元件的位置在此處計算,並直接設定 adjustment。
    ///
    /// 那意味著沒有動畫。`gtk_adjustment_set_value` 是瞬時的,而 GTK 4 的慣性捲動是由輸入驅動、而非
    /// 由 API 驅動,因此根本沒有東西可以拿來做動畫。此處明說,而不是留給人去發現:一個「在一個平台上
    /// 瞬間抵達、在另外四個平台上滑行」的捲動,讀起來像是卡頓。
    ///
    /// nil 的 anchor 採取「讓該子元件可見的最短捲動」,那正是 SwiftUI 中 nil anchor 的意思;
    /// 給定 anchor 則是在要求一個位置。
    public func scroll(to child: Widget, anchor: (x: Double, y: Double)?) {
        var point = graphene_point_t(x: 0, y: 0)
        var origin = graphene_point_t(x: 0, y: 0)
        guard gtk_widget_compute_point(child.widgetPointer, widgetPointer, &origin, &point) != 0
        else { return }

        setAdjustment(
            gtk_scrolled_window_get_vadjustment(opaquePointer),
            childStart: Double(point.y),
            childExtent: Double(gtk_widget_get_height(child.widgetPointer)),
            anchor: anchor?.y
        )
        setAdjustment(
            gtk_scrolled_window_get_hadjustment(opaquePointer),
            childStart: Double(point.x),
            childExtent: Double(gtk_widget_get_width(child.widgetPointer)),
            anchor: anchor?.x
        )
    }

    /// Moves one adjustment, clamped to what it can actually represent.
    ///
    /// GtkAdjustment silently clamps a value outside `[lower, upper - page]`,
    /// so an out-of-range write does not fail -- it lands somewhere else. The
    /// clamp is done here so the value that is set is the value that was meant.
    ///
    /// 移動一個 adjustment,並夾限到它實際能表示的範圍。
    ///
    /// GtkAdjustment 會靜默地夾限落在 `[lower, upper - page]` 之外的值,因此一次超出範圍的寫入不會
    /// 失敗——它只是落在別的地方。此處先做夾限,好讓「被設定的值」就是「原本想要的值」。
    /// - Note: The parameter is `UnsafeMutablePointer<GtkAdjustment>?`, NOT
    ///   `OpaquePointer?`. `gtk_scrolled_window_get_vadjustment` returns the
    ///   former, and this arrived declaring the latter -- written on a machine
    ///   that cannot build GtkBackend, so nothing there could have caught it.
    ///
    ///   It produced SIXTEEN errors from ONE cause. With the parameter wrong,
    ///   `gtk_adjustment_get_upper(adjustment)` no longer resolves to the C
    ///   function, so Swift went looking elsewhere and reported `cannot convert
    ///   value of type 'Duration' to expected argument type 'Double'` on the
    ///   arithmetic below. There is no `Duration` in this file. Fixing the two
    ///   pointer types fixes all sixteen; chasing the `Duration` message would
    ///   have been chasing a symptom two frames from its cause.
    ///
    /// - Note: 參數型別是 `UnsafeMutablePointer<GtkAdjustment>?`，**不是** `OpaquePointer?`。
    ///   `gtk_scrolled_window_get_vadjustment` 回傳的是前者，而此處送來時宣告的是後者——它寫於一台
    ///   無法建置 GtkBackend 的機器上，因此那裡不可能發現這件事。
    ///
    ///   它由**一個**成因產生了**十六個**錯誤。參數型別一錯，`gtk_adjustment_get_upper(adjustment)`
    ///   就不再解析到那個 C 函式，於是 Swift 轉而尋找別處，並在下方的算術上回報
    ///   `cannot convert value of type 'Duration' to expected argument type 'Double'`。本檔中根本沒有
    ///   `Duration`。修正這兩個指標型別即可修掉全部十六個；去追那則 `Duration` 訊息，等於在距離成因
    ///   兩層之外追一個症狀。
    private func setAdjustment(
        _ adjustment: UnsafeMutablePointer<GtkAdjustment>?,
        childStart: Double,
        childExtent: Double,
        anchor: Double?
    ) {
        guard let adjustment else { return }
        let page = gtk_adjustment_get_page_size(adjustment)
        let current = gtk_adjustment_get_value(adjustment)
        let start = current + childStart

        let target: Double
        if let anchor {
            target = start - (page - childExtent) * anchor
        } else if childStart < 0 {
            target = start
        } else if childStart + childExtent > page {
            target = start + childExtent - page
        } else {
            return
        }

        let upper = gtk_adjustment_get_upper(adjustment)
        let lower = gtk_adjustment_get_lower(adjustment)
        gtk_adjustment_set_value(adjustment, min(max(lower, target), max(lower, upper - page)))
    }
}
