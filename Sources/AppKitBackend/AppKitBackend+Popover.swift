import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    public typealias Popover = NSCustomPopover

    public func createPopover(content: NSView) -> NSCustomPopover {
        let popover = NSCustomPopover()

        // `.transient` is what makes it a popover rather than a small window:
        // it closes when the user clicks anywhere outside it, which is the
        // behaviour every platform's popover has and the reason a caller
        // reaches for one.
        // `.transient` 正是讓它成為 popover、而非一個小視窗的關鍵:使用者點擊它以外的任何地方時它
        // 就會關閉,而那是每個平台的 popover 都具備的行為,也是呼叫端會選用它的理由。
        popover.behavior = .transient

        let controller = NSViewController()
        // A container rather than the content view itself. NSPopover sizes its
        // content from the controller's view, and handing it a view that the
        // layout system also owns means two things setting the same frame.
        // 使用容器而非內容 view 本身。NSPopover 是依 controller 的 view 來決定其內容尺寸的,而把一個
        // 版面系統同時擁有的 view 交給它,會變成兩邊都在設定同一個 frame。
        let container = NSView()
        container.addSubview(content)
        controller.view = container
        popover.contentViewController = controller
        popover.customContent = content

        return popover
    }

    public func updatePopover(
        _ popover: NSCustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        backgroundColor: Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        // WRITTEN ON WINDOWS 2026-09-09 AND NOT RUN. The Windows side cannot
        // build AppKit; this compiles against the API as read, and the Mac side
        // verifies it. Same handover shape as #117.
        //
        // On the content view's layer, not on the NSPopover. `NSPopover` has
        // `appearance` (aqua / dark aqua / vibrant) and no background colour at
        // all -- so a colour cannot be expressed on the popover itself, and
        // reaching for `appearance` would silently substitute a different
        // meaning for the one the app asked for.
        //
        // nil clears the layer's colour rather than leaving the last one, so a
        // colour bound to state is removable. Clearing reveals NSPopover's own
        // vibrant chrome, which is what "leave it to the platform" means here --
        // it does not leave a hole, unlike the GTK case measured the same day.
        //
        // **本段於 2026-09-09 在 Windows 上寫成,未曾執行。** Windows 這側無法建置 AppKit;此處是
        // 對照所讀到的 API 寫出來的,由 Mac 那側驗證。與 #117 相同的交接形狀。
        //
        // 設在內容 view 的 layer 上,而非 NSPopover 上。`NSPopover` 只有 `appearance`
        // (aqua / dark aqua / vibrant),**完全沒有**背景色——因此顏色無法表達在 popover 本身,
        // 而改去動 `appearance` 會靜默地把 app 所要求的意義換成另一件事。
        //
        // nil 時清掉 layer 的顏色而不是留著上一個,使綁定於 state 的顏色可被移除。清掉後露出的是
        // `NSPopover` 自己的 vibrant 外觀,那正是此處「交給平台」的意思——它**不會**留下一個洞,
        // 與同一天在 GTK 上量到的情況不同。
        if let view = popover.contentViewController?.view {
            view.wantsLayer = true
            view.layer?.backgroundColor = backgroundColor.map { $0.nsColor.cgColor }
        }

        let contentSize = NSSize(width: size.x, height: size.y)
        popover.contentSize = contentSize
        popover.contentViewController?.view.frame = NSRect(
            origin: .zero,
            size: contentSize
        )
        popover.customContent?.frame = NSRect(origin: .zero, size: contentSize)
        popover.onDismiss = onDismiss
    }

    public func presentPopover(
        _ popover: NSCustomPopover,
        relativeTo anchor: NSView,
        window: NSCustomWindow
    ) {
        // `.maxY` puts it below the anchor, which is where a popover opened
        // from a button belongs. AppKit moves it to another edge by itself when
        // there is no room, which is the rule this backend is being left to
        // keep.
        // `.maxY` 會把它放在錨點下方,而那正是由按鈕開啟的 popover 該在的位置。空間不足時,AppKit
        // 會自行把它移到另一側——那正是此處刻意讓這個 backend 保有的規則。
        popover.willPresent()
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .maxY
        )
    }

    public func dismissPopover(_ popover: NSCustomPopover, window: NSCustomWindow) {
        // `performClose` rather than `close`: it runs the delegate callbacks,
        // and this backend's dismissal bookkeeping hangs off them. `close`
        // would take the popover off screen and leave the modifier believing it
        // was still up.
        // 使用 `performClose` 而非 `close`:前者會執行 delegate 回呼,而本 backend 的關閉記錄正是掛在
        // 那些回呼上。`close` 會把 popover 移出畫面,卻讓 modifier 以為它仍然開著。
        popover.performClose(nil)
    }

    public func size(ofPopover popover: NSCustomPopover) -> SIMD2<Int> {
        SIMD2(Int(popover.contentSize.width), Int(popover.contentSize.height))
    }
}

/// An `NSPopover` that reports its own dismissal.
///
/// Needed because a popover is `.transient`: the user closes it by clicking
/// somewhere else, and nothing in the view tree hears about that. Without the
/// callback the modifier's `isPresented` stays true, the next press does
/// nothing because it is already "presented", and the popover never comes back.
///
/// 一個會回報自身關閉的 `NSPopover`。
///
/// 之所以需要它,是因為 popover 是 `.transient` 的:使用者是靠點擊別處來關閉它的,而 view 樹中沒有
/// 任何東西會聽到這件事。少了這個回呼,modifier 的 `isPresented` 會維持為真,下一次按下也不會有任何
/// 反應——因為它「已經呈現了」——而該 popover 再也不會出現。
public final class NSCustomPopover: NSPopover, NSPopoverDelegate {
    var onDismiss: (() -> Void)?
    var customContent: NSView?

    /// Whether this presentation's close has already been reported.
    ///
    /// **`popoverDidClose(_:)` is called TWICE for one dismissal, and the reason
    /// is documented AppKit behaviour rather than a bug here.** `NSPopover`
    /// automatically registers a delegate that implements a notification-shaped
    /// method as an observer of the matching notification -- so this method is
    /// reached once by delegate dispatch and once by the notification centre.
    /// Measured 2026-09-10: one light dismissal of P50's panel produced two
    /// `popoverDidClose` calls with the SAME object identity, and P50's own
    /// `onDismiss` logged "popover alpha dismissed" twice in the same second.
    ///
    /// The consequence is not cosmetic. `PopoverModifier.handleDismiss` runs the
    /// application's `onDismiss` and then tears the popover's state down, so the
    /// second call runs an application closure a second time -- for an app that
    /// saves a draft or posts a request on dismissal, once is the contract.
    ///
    /// 這一次呈現的關閉是否已經回報過。
    ///
    /// **`popoverDidClose(_:)` 對一次關閉會被呼叫兩次,而原因是 AppKit 已載明的行為,不是此處的缺陷。**
    /// `NSPopover` 會把「實作了通知形狀方法的 delegate」自動註冊為對應通知的觀察者——因此本方法會被
    /// delegate 派送抵達一次,再被通知中心抵達一次。2026-09-10 實測:P50 面板的一次 light dismiss
    /// 產生了兩次 `popoverDidClose`,兩次的物件身分相同,而 P50 自己的 `onDismiss` 在同一秒內記下了
    /// 兩行「popover alpha dismissed」。
    ///
    /// 其後果不只是外觀問題。`PopoverModifier.handleDismiss` 會先執行應用程式的 `onDismiss`、再拆掉
    /// popover 的狀態,因此第二次呼叫等於把一個應用程式的 closure 再執行一遍——對一個「在關閉時存草稿
    /// 或送出請求」的 app 而言,契約是**一次**。
    private var hasReportedClose = false

    override public init() {
        super.init()
        delegate = self
    }

    // Required by NSPopover and unreachable here: this backend never
    // unarchives a popover, it constructs them. Trapping says so rather than
    // returning something half-built that would fail later and elsewhere.
    // NSPopover 要求提供,而此處不可能被觸及:本 backend 從不從封存還原 popover,它是建構它們的。
    // 此處直接中止是為了把這件事說清楚,而不是回傳一個「半成品」讓它稍後在別處失敗。
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NSCustomPopover cannot be created from a coder")
    }

    public func popoverDidClose(_ notification: Notification) {
        // Reported once per presentation. Reset when the popover is shown
        // again, in `presentPopover`, so a second presentation reports its own
        // close rather than being swallowed by the first one's flag.
        // 每一次呈現只回報一次。旗標會在 popover 再次被顯示時（於 `presentPopover`）重置，
        // 好讓第二次呈現能回報它自己的關閉，而不是被第一次的旗標吞掉。
        guard !hasReportedClose else { return }
        hasReportedClose = true
        onDismiss?()
    }

    /// Called by the backend when this popover is shown.
    /// 由 backend 在本 popover 被顯示時呼叫。
    func willPresent() {
        hasReportedClose = false
    }
}
