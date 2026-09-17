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

        // **`contentSize` is set, and the controller's view is NOT repositioned.**
        //
        // This used to also do
        // `popover.contentViewController?.view.frame = NSRect(origin: .zero, ...)`,
        // and that line is what put the panel in the corner. AppKit owns where
        // the content view sits inside the popover's shell -- the shell is
        // larger, by the arrow and its margins -- and forcing the frame to
        // `.zero` moves it to the BOTTOM-LEFT of that shell, leaving the chrome
        // visible along the top and the right.
        //
        // Reported as "the green panel is not inside the popover, a lot of white
        // leaking on the right". Measured: shell 314x180, content 288x154, so 26
        // points in each axis that AppKit would have split evenly and this line
        // pushed entirely to two edges.
        //
        // The child fills the container instead, and follows it if AppKit
        // resizes it -- which is what `autoresizingMask` is for and what setting
        // a frame once cannot do.
        //
        // **設定 `contentSize`,而**不**重新定位 controller 的 view。**
        //
        // 此處原本還有一行 `popover.contentViewController?.view.frame = NSRect(origin: .zero, ...)`，
        // 而正是那一行把面板推到了角落。內容 view 在 popover 外殼中的位置由 AppKit 擁有——外殼比內容大，
        // 大出來的是箭頭與它的邊距——而把 frame 強制設為 `.zero`，會把它移到該外殼的**左下角**，於是
        // 上緣與右緣露出外殼。
        //
        // 回報的說法是「綠框不在 popover 內,右邊漏白很多」。量到:外殼 314x180、內容 288x154,也就是
        // 每個軸上有 26 點——AppKit 本來會把它平均分到兩側，而那一行把它整份推到了兩個邊。
        //
        // 改為讓子 view 填滿容器，並在 AppKit 調整容器大小時跟著走——那正是 `autoresizingMask` 的用途，
        // 也是「只設定一次 frame」做不到的事。
        let contentSize = NSSize(width: size.x, height: size.y)
        popover.contentSize = contentSize
        if let container = popover.contentViewController?.view {
            popover.customContent?.frame = container.bounds
            popover.customContent?.autoresizingMask = [.width, .height]
        }
        popover.onDismiss = onDismiss
    }

    public func presentPopover(
        _ popover: NSCustomPopover,
        relativeTo anchor: NSView,
        window: NSCustomWindow
    ) {
        // **`.minY` when nothing is asked for: below the anchor, which is what
        // the other four backends do and what this call always MEANT to do.**
        //
        // It carried `.maxY` from the day the popover landed, under a comment
        // saying that put the panel below the button, "which is where a popover
        // opened from a button belongs". The comment's intent was right and its
        // claim was wrong: driven on 2026-09-17 with no `arrowEdge` at all, P50
        // opened its panel ABOVE the button
        // (`p50-macos-final-20260917-195515.png`, the readout reading
        // `arrow edge: none (platform decides)`).
        //
        // The other four agree with each other: `GtkPopover`'s default position
        // is below, `PopupWindow.showAsDropDown` means below, WinUI's `Flyout`
        // auto-places below where it fits, and UIKit's `[.up, .down]` takes
        // below when there is room. AppKit was the only one placing a
        // no-preference popover above, so this is one app looking different on
        // one platform for no reason anybody chose.
        //
        // AppKit still moves the panel when there is no room below, which is
        // the rule this backend is being left to keep.
        //
        // **沒有任何要求時使用 `.minY`:錨點下方——那是另外四個 backend 的做法,也是本呼叫一直以來
        // 所「打算」做的事。**
        //
        // 它自這個 popover 落地那天起就帶著 `.maxY`,而其上的註解說那會把面板放在按鈕下方、
        // 「那正是由按鈕開啟的 popover 該在的位置」。那個註解的**意圖**是對的,它的**主張**是錯的:
        // 2026-09-17 在完全不給 `arrowEdge` 的情況下驅動,P50 把面板開在按鈕**上方**
        // (`p50-macos-final-20260917-195515.png`,讀數寫著 `arrow edge: none (platform decides)`)。
        //
        // 另外四個彼此一致:`GtkPopover` 的預設位置是下方、`PopupWindow.showAsDropDown` 就是下方、
        // WinUI 的 `Flyout` 自動放在放得下的下方、UIKit 的 `[.up, .down]` 在有空間時取下方。
        // 只有 AppKit 把「沒有偏好」的 popover 放在上方——那是同一支 app 在同一件事上,因為沒有人選擇過
        // 的理由而在某個平台上長得不一樣。
        //
        // 空間不足時 AppKit 依然會移動面板,那正是此處刻意讓這個 backend 保有的規則。
        popover.willPresent()
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: popover.preferredArrowEdge.map(Self.rectEdge(for:)) ?? .minY
        )
    }

    /// `NSRectEdge` for a side of the anchor.
    ///
    /// **`.maxY` puts the panel ABOVE the anchor, and this pair was written the
    /// other way round first.** The comment in `presentPopover` above said
    /// `.maxY` meant "below", reasoning from this backend's flipped views, and
    /// the first mapping here followed it: `.top` to `.minY`. Driven on
    /// 2026-09-17 with P50, the two captures said the opposite --
    /// `p50-macos-final-20260917-155815.png` has the app reporting
    /// `arrow edge: top` with the panel BELOW its button, and `-155948.png` has
    /// it reporting `bottom` with the panel ABOVE. The readout is what makes
    /// that a measurement rather than two pictures of a popover: AppKit moves a
    /// popover that does not fit, so a panel on the far side could always have
    /// been the platform's doing.
    ///
    /// `NSPopover` therefore reads `preferredEdge` in AppKit's own y-up screen
    /// space, not in the flipped space the anchor view is laid out in.
    ///
    /// 錨點某一側所對應的 `NSRectEdge`。
    ///
    /// **`.maxY` 會把面板放在錨點的上方,而這一組對應最初是寫反的。** 上面 `presentPopover` 的註解說
    /// `.maxY` 是「下方」——那是從本 backend 的翻轉 view 推論來的——而此處第一版的對應也照著寫:
    /// `.top` 對 `.minY`。2026-09-17 以 P50 驅動之後,那兩張擷圖說的正好相反:
    /// `p50-macos-final-20260917-155815.png` 裡 app 回報 `arrow edge: top`,而面板在按鈕**下方**;
    /// `-155948.png` 裡它回報 `bottom`,而面板在**上方**。使這成為一次量測、而非兩張 popover 照片的,
    /// 正是那行讀數:AppKit 會移動放不下的 popover,因此「面板落在另一側」永遠有可能是平台自己做的。
    ///
    /// 由此可知,`NSPopover` 是在 AppKit 自己 y 向上的**螢幕**座標系裡解讀 `preferredEdge` 的,
    /// 而不是在錨點 view 所處的那個翻轉空間裡。
    private static func rectEdge(for edge: SwiftCrossUI.Edge) -> NSRectEdge {
        switch edge {
            case .top: return .maxY
            case .bottom: return .minY
            case .leading: return .minX
            case .trailing: return .maxX
        }
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

    /// Which side of the anchor this popover has been asked to appear on
    /// (#109), or `nil` for the platform's own choice.
    ///
    /// Held here rather than passed to ``AppKitBackend/presentPopover(_:relativeTo:window:)``
    /// because the protocol sets it separately, before the popover is shown --
    /// see `BackendFeatures.PopoverArrowEdges`.
    ///
    /// 這個 popover 被要求出現在錨點的哪一側(#109);`nil` 代表交由平台自行決定。
    ///
    /// 存放於此而非傳給 ``AppKitBackend/presentPopover(_:relativeTo:window:)``,因為協定是分開設定
    /// 它的,且在該 popover 被顯示**之前**——見 `BackendFeatures.PopoverArrowEdges`。
    var preferredArrowEdge: SwiftCrossUI.Edge?

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

extension AppKitBackend: BackendFeatures.PopoverArrowEdges {
    /// Stores the preference; ``presentPopover(_:relativeTo:window:)`` spends it.
    ///
    /// `NSPopover` takes its edge as an argument to `show(relativeTo:of:preferredEdge:)`
    /// and keeps no settable property for it, so there is nothing to set on the
    /// object at this point -- which is why this is a field on
    /// ``NSCustomPopover`` and not a call into AppKit.
    ///
    /// **AppKit keeps its own rule when the preferred edge does not fit**, which
    /// is what the protocol asks for: `preferredEdge` is documented as a
    /// preference, and a popover with no room on that side is moved rather than
    /// drawn off screen.
    ///
    /// 存下這個偏好;由 ``presentPopover(_:relativeTo:window:)`` 使用它。
    ///
    /// `NSPopover` 是把邊當成 `show(relativeTo:of:preferredEdge:)` 的引數來接收的,它沒有對應的
    /// 可設定屬性,因此此刻在那個物件上沒有東西可設——這正是本項成為 ``NSCustomPopover`` 一個欄位、
    /// 而非一次對 AppKit 呼叫的原因。
    ///
    /// **偏好的那一側放不下時,AppKit 會保有它自己的規則**,而那正是協定所要求的:`preferredEdge`
    /// 的文件寫明它是一個偏好,而一個在該側沒有空間的 popover 會被移動,不會被畫到螢幕外。
    public func setPreferredArrowEdge(ofPopover popover: NSCustomPopover, to edge: Edge?) {
        popover.preferredArrowEdge = edge
    }
}
