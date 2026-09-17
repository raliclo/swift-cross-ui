@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI
import WindowsFoundation

/// `.popover` for WinUI, built on `Flyout`.
///
/// `Flyout` rather than `Popup`. Both put content above the page, but `Popup`
/// takes raw coordinates and leaves light dismiss, placement, flipping at the
/// screen edge, the beak and the shadow to the caller. `Flyout` is the control
/// Windows itself uses for exactly this, and `showAt(_:)` takes the anchor
/// directly -- which is the parameter the whole protocol exists for.
///
/// 為 WinUI 實作的 `.popover`，建構於 `Flyout` 之上。
///
/// 選 `Flyout` 而非 `Popup`。兩者都能把內容放到頁面之上，但 `Popup` 接受的是原始座標，並把點擊
/// 外部關閉、定位、在螢幕邊緣翻轉、尖角與陰影全部留給呼叫端。`Flyout` 則是 Windows 自己就用於
/// 此事的控制項，而 `showAt(_:)` 直接接受錨點——那正是整個 protocol 之所以存在的那個參數。
extension WinUIBackend {
    @MainActor
    public final class Popover {
        let flyout: WinUI.Flyout
        var dismissHandler: (() -> Void)?
        /// The side the app asked for, or nil for XAML's own choice (#109).
        ///
        /// **Stored rather than written straight onto the flyout**, because
        /// `presentPopover` assigns `placement` immediately before `showAt` --
        /// see the note there. A preference set earlier would be overwritten by
        /// that line and take effect on the NEXT presentation instead of this
        /// one: right forever after being wrong once, which reads as a race and
        /// is not.
        ///
        /// app 所要求的那一側;nil 表示交由 XAML 自行決定(#109)。
        ///
        /// **存起來、而不是直接寫到 flyout 上**,因為 `presentPopover` 會在 `showAt` 之前立刻指派
        /// `placement`(見該處註解)。先前設定的偏好會被那一行蓋掉,於是它會在**下一次**呈現時才生效
        /// ——「錯一次、之後永遠對」,看起來像競態,其實不是。
        var preferredPlacement: WinUI.FlyoutPlacementMode?

        init(content: WinUI.FrameworkElement) {
            flyout = WinUI.Flyout()
            flyout.content = content
            // `closed` fires for both user and programmatic dismissals and
            // carries nothing to tell them apart. It no longer needs to: the
            // handler runs on both, which is SwiftUI's rule -- `onDismiss:` runs
            // when the presentation ends however it ended -- and is what
            // AppKitBackend already did, since `NSPopover.performClose` runs
            // `popoverDidClose`. There used to be an `isProgrammaticDismissal`
            // flag here suppressing the programmatic case, and it made three
            // shipped backends disagree about one callback.
            //
            // Firing on both does not loop; the argument is written out in
            // `GtkBackend+Popovers.swift`, and rests on `PopoverModifier`
            // clearing `children.popover` immediately after `dismissPopover` and
            // only entering that branch when `isPresented` is already false.
            //
            // NOTE `Sheet.isProgrammaticDismissal` in `WinUIBackend+Sheets.swift`
            // is the same flag for the same reason and has NOT been changed
            // here. SwiftUI's `sheet(isPresented:onDismiss:)` fires on both paths
            // too, so sheets look misaligned in the same way -- but that is a
            // separate change with its own five backends to check, and pretending
            // this one covered it would be worse than saying so.
            //
            // 使用者關閉與程式關閉都會觸發 `closed`，且它沒有攜帶任何足以區分兩者的資訊；而現在它也
            // 不需要區分：兩種情況下 handler 都會執行，那正是 SwiftUI 的規則——無論 presentation 以
            // 何種方式結束，`onDismiss:` 都會執行——也正是 AppKitBackend 原本的行為，因為
            // `NSPopover.performClose` 會執行 `popoverDidClose`。此處原本有一個
            // `isProgrammaticDismissal` 旗標壓住程式化的那一條路，導致三個已發布的 backend 對同一個
            // 回呼各說各話。
            //
            // 兩條路都觸發不會造成迴圈；完整論證寫在 `GtkBackend+Popovers.swift`，其依據是
            // `PopoverModifier` 在呼叫 `dismissPopover` 之後立刻清掉 `children.popover`，而且只有在
            // `isPresented` 已經為 false 時才會進入該分支。
            //
            // 注意：`WinUIBackend+Sheets.swift` 中的 `Sheet.isProgrammaticDismissal` 是同一個旗標、
            // 同樣的理由，而此處**並未**一併更動。SwiftUI 的 `sheet(isPresented:onDismiss:)` 同樣在
            // 兩條路上都會觸發，因此 sheet 也存在同一種偏差——但那是另一項變更，有它自己的五個
            // backend 要檢查，而假裝這次一併解決了會比說清楚更糟。
            flyout.closed.addHandler { [weak self] _, _ in
                guard let self else { return }
                self.dismissHandler?()
            }
        }
    }

    public func createPopover(content: Widget) -> Popover {
        Popover(content: content)
    }

    public func updatePopover(
        _ popover: Popover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        // Qualified for the same reason GtkBackend's is: `UWP.Color` and
        // `SwiftCrossUI.Color` are both in scope here and the bare name is
        // ambiguous. Both files needed it and only one got it on the first
        // pass -- the fix was written, its reason was written down, and the
        // sibling two directories away was not checked.
        // 需要限定名稱,理由與 GtkBackend 那份相同:此處 `UWP.Color` 與 `SwiftCrossUI.Color` 同時
        // 在 scope,裸名有歧義。兩個檔案都需要,而第一次只有一個改到——修正寫了、理由也寫了,
        // 卻沒去看兩層目錄外的那個同類檔案。
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.dismissHandler = onDismiss

        // On the CONTENT, not on the Flyout. A `Flyout` has no Background of its
        // own -- the chrome belongs to its `FlyoutPresenter`, which is created
        // by the template and is not reachable from here without hunting the
        // visual tree at open time. Painting the content is both simpler and
        // closer to what was asked, since the content is what fills the panel.
        //
        // nil restores the transparent brush rather than leaving the last
        // colour: a colour bound to state has to be removable. Transparent is
        // right HERE and does not contradict the protocol's "nil means leave it
        // to the platform" -- the FlyoutPresenter behind this content still
        // draws the system's own acrylic backing, so clearing the content's
        // brush reveals the platform chrome rather than a hole.
        //
        // 設在**內容**上,而不是 Flyout 上。`Flyout` 自己沒有 Background——那層外觀屬於它的
        // `FlyoutPresenter`,後者由樣板建立,若不在開啟時去翻 visual tree 便無從取得。為內容上色
        // 既比較簡單,也更接近所要求的事,因為填滿面板的正是內容。
        //
        // nil 時還原為透明筆刷,而不是留著上一次的顏色:綁定於 state 的顏色必須可被移除。透明在
        // **此處**是正確的,且不與 protocol 的「nil 表示交給平台」相牴觸——內容背後的
        // `FlyoutPresenter` 仍會繪製系統自己的 acrylic 底色,因此清掉內容的筆刷露出的是平台外觀,
        // 而不是一個洞。
        if let content = popover.flyout.content as? WinUI.Control {
            content.background = WinUI.SolidColorBrush(
                backgroundColor?.uwpColor ?? UWP.Color.transparent
            )
        }

        if let content = popover.flyout.content as? WinUI.FrameworkElement {
            content.width = Double(size.x)
            content.height = Double(size.y)
        }

        // The flyout's background is left to the system. A `FlyoutPresenter` is
        // themed -- acrylic or a solid theme brush, a border, a corner radius
        // and a shadow -- and painting a flat colour onto the content would sit
        // a rectangle inside all of that rather than replacing it.
        //
        // flyout 的背景交給系統。`FlyoutPresenter` 是有主題的——壓克力材質或純色主題筆刷、邊框、
        // 圓角與陰影——而把一塊扁平顏色塗到內容上，只會在這一切之內擺進一個矩形，並不會取代它們。

        // The presenter's own padding is left alone. WinUI's `FlyoutPresenter`
        // inserts a margin around flyout content, and removing it needs a
        // `FlyoutPresenter` `Style` -- `FlyoutBase` is a `DependencyObject`, not
        // a `FrameworkElement`, so it has no `resources` dictionary to override
        // the way `WinUIBackend+Sheets.swift` overrides `ContentDialog`'s. The
        // result is a popover slightly larger than its content, which is what a
        // Windows popover looks like anyway.
        //
        // 此處不動 presenter 自身的內距。WinUI 的 `FlyoutPresenter` 會在 flyout 內容周圍加上邊距，
        // 而要移除它需要一個 `FlyoutPresenter` 的 `Style`——`FlyoutBase` 是 `DependencyObject` 而非
        // `FrameworkElement`，因此它沒有 `resources` 字典可供覆寫，不像
        // `WinUIBackend+Sheets.swift` 覆寫 `ContentDialog` 的那樣。其結果是 popover 會比其內容略大，
        // 而 Windows 上的 popover 本來就是這個樣子。
    }

    public func presentPopover(_ popover: Popover, relativeTo anchor: Widget, window: Window) {
        popover.flyout.xamlRoot = window.content.xamlRoot

        // With no preference from the app: `.bottom`, below the anchor. That is
        // what the other four backends do; the Mac side aligned AppKit to it on
        // the same day (cf4a4a88), and one app should not open its popover on a
        // different side on one platform for no reason anybody chose. That
        // commit's comment says WinUI's Flyout "auto-places below where it
        // fits". It does not, as the next paragraph measures.
        //
        // 沒有 app 的偏好時:`.bottom`,錨點下方。另外四個 backend 都這樣做,Mac 端同日也把 AppKit 對齊到
        // 這一側(cf4a4a88);同一支 app 不該因為沒人選過的理由,在某個平台上把 popover 開在另一側。那個
        // commit 的註解說 WinUI 的 Flyout「自動放在放得下的下方」——並不是,見下一段的量測。
        //
        // **This used to be `.auto`, and `.auto` showed NOTHING.** Measured
        // 2026-09-17 on P50: with no arrowEdge, both panels logged
        // `popover ... shown` and neither appeared. An out-of-process UIA dump
        // had no PANEL node, and a window capture and a desktop capture both
        // showed no panel. The runs covered PANEL BETA, PANEL ALPHA, and ALPHA
        // cycled through every edge back to none, 0 of 3 each. The positive
        // control: with `.trailing` set, the same dump found `PANEL ALPHA`, so the
        // probe can see an open flyout. Changing only this fallback to a side
        // made both panels appear. The 2026-09-16 verification drove only SET
        // preferences, which is how the default path went unexercised. `.auto`
        // had been here since dea9ccff.
        //
        // The reason `.auto` was chosen does not hold either. That comment said a
        // fixed side "would be honoured even where there is no room". Measured
        // the day before, on this backend: `.bottom` on a button with no room
        // below flipped the panel ABOVE it. The sided values are preferences, and
        // XAML moves the flyout when they do not fit, so the side is not the
        // BACKEND's choice in any way that matters.
        //
        // **這裡原本是 `.auto`,而 `.auto` 什麼都不顯示。** 2026-09-17 以 P50 實測:不帶 arrowEdge 時,
        // 兩塊面板都記下 `popover ... shown`,卻都沒有出現——行程外 UIA dump 沒有 PANEL 節點,視窗擷取與
        // 桌面擷取都沒有面板(PANEL BETA、PANEL ALPHA、以及把 ALPHA 循環一圈回到 none,各 0/3)。正向對照:
        // 設為 `.trailing` 時同一份 dump 找得到 `PANEL ALPHA`,證明探針看得到打開的 flyout。**只把這個
        // 預設值改成某一側**,兩塊面板就都出現了。2026-09-16 的驗收只驅動了**有設定**的偏好,預設路徑
        // 因此從未被走過;`.auto` 自 dea9ccff 起就在這裡。
        //
        // 當初選 `.auto` 的理由也不成立。那段註解說釘死的一側「在沒有空間的地方也會被忠實遵守」;而前一天
        // 在本 backend 上量到:下方沒有空間的按鈕設 `.bottom`,面板被翻到**上方**。有方向的值是**偏好**,
        // 放不下時 XAML 會移動 flyout。
        popover.flyout.placement = popover.preferredPlacement ?? .bottom

        do {
            try popover.flyout.showAt(anchor)
        } catch {
            // Not fatal. A flyout whose anchor has left the tree throws rather
            // than crashing, and taking the process down for a popover is
            // exactly what this backend's presentation code already refuses to
            // do elsewhere -- see `presentSheetNow`.
            // 非致命。錨點已離開 tree 的 flyout 會擲出錯誤而非崩潰，而為了一個 popover 就終止行程，
            // 正是本 backend 的呈現程式碼在別處已經拒絕做的事——見 `presentSheetNow`。
            print("Error: \(error)")
        }
    }

    public func dismissPopover(_ popover: Popover, window: Window) {
        do {
            try popover.flyout.hide()
        } catch {
            print("Error: \(error)")
        }
    }

    public func size(ofPopover popover: Popover) -> SIMD2<Int> {
        guard let content = popover.flyout.content as? WinUI.FrameworkElement else {
            return .zero
        }

        // `width`/`height` are what `updatePopover` wrote. A `FrameworkElement`
        // reports them whether or not it has ever been laid out -- they are the
        // requested size, not a measured one -- so this answers for a flyout
        // that has never been shown, which `actualWidth`/`actualHeight` could
        // not: those stay 0 until the element is in a live visual tree, and a
        // flyout's content is not in one until `showAt`.
        //
        // Unset, they are `Double.nan`, XAML's spelling of "Auto". That is the
        // state between `createPopover` and the first `updatePopover`, and
        // `Int(Double.nan)` traps rather than returning a number, so the NaN
        // case has to be taken before the conversion and not after it.
        //
        // `width`/`height` 就是 `updatePopover` 寫進去的值。無論 `FrameworkElement` 是否曾經完成
        // 版面計算，它都會回報這兩個值——它們是被請求的尺寸，而非量測出來的——因此對一個從未顯示過的
        // flyout 這仍答得出來，而 `actualWidth`/`actualHeight` 做不到：在元素進入活的 visual tree
        // 之前它們都是 0，而 flyout 的內容在 `showAt` 之前並不在其中。
        //
        // 未設定時它們是 `Double.nan`，也就是 XAML 對「Auto」的寫法。那正是 `createPopover` 與第一次
        // `updatePopover` 之間的狀態，而 `Int(Double.nan)` 會直接中止、不會回傳數字，因此 NaN 這個
        // 情況必須在轉型之前處理，不能在之後。
        if !content.width.isNaN && !content.height.isNaN {
            return SIMD2(Int(content.width), Int(content.height))
        }

        // XAML's own answer, filled in by the last measure pass. Zero before
        // there has been one, which is the truthful reply to "how big is a
        // popover nothing has measured yet".
        // XAML 自己的答案，由最近一次 measure pass 填入。在第一次 measure 之前它是零，而對於
        // 「一個還沒有任何東西量測過的 popover 有多大」來說，零正是誠實的回答。
        let desired = content.desiredSize
        return SIMD2(Int(desired.width), Int(desired.height))
    }
}

/// The preferred side for a popover's arrow (#109).
///
/// `FlyoutPlacementMode`'s sided values are preferences in XAML's own terms --
/// a flyout with no room on the requested side moves -- which is what
/// ``BackendFeatures/PopoverArrowEdges`` promises and what GtkBackend gets from
/// `GtkPopover.position`. Two platforms, one contract, neither of them asked to
/// implement flipping.
///
/// **`leading`/`trailing` resolve as left/right**, the same limitation stated on
/// the GTK side: `FlyoutPlacementMode` has `.leftEdgeAlignedTop` and friends but
/// nothing that follows writing direction, so a right-to-left layout would want
/// them swapped. Said here rather than left for someone to find.
///
/// popover 箭頭的偏好側(#109)。
///
/// `FlyoutPlacementMode` 中帶側邊的那些值,依 XAML 自己的定義就是**偏好**——在所要求的一側沒有空間時,
/// flyout 會移動——那正是 ``BackendFeatures/PopoverArrowEdges`` 所承諾的,也正是 GtkBackend 從
/// `GtkPopover.position` 得到的東西。兩個平台、同一個約定,而且兩者都不需要自己實作翻轉。
///
/// **`leading`/`trailing` 解析為 left/right**,與 GTK 那側寫明的限制相同:`FlyoutPlacementMode`
/// 有 `.leftEdgeAlignedTop` 之類的值,但沒有任何一個會跟隨書寫方向,因此由右至左的版面應當對調。
/// 寫在這裡,而不是留給某個人自己去發現。
extension WinUIBackend: BackendFeatures.PopoverArrowEdges {
    public func setPreferredArrowEdge(ofPopover popover: Popover, to edge: Edge?) {
        popover.preferredPlacement = edge.map { edge in
            switch edge {
                case .top: return WinUI.FlyoutPlacementMode.top
                case .bottom: return WinUI.FlyoutPlacementMode.bottom
                case .leading: return WinUI.FlyoutPlacementMode.left
                case .trailing: return WinUI.FlyoutPlacementMode.right
            }
        }
    }
}
