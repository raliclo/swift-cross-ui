@_spi(Backends) import SwiftCrossUI
import Foundation
import UWP
import WinUI
import WindowsFoundation

/// `.popover` for WinUI, built on `Flyout`.
///
/// `Flyout` rather than `Popup`. Both put content above the page, but `Popup`
/// takes raw coordinates and leaves light dismiss, placement, flipping at the
/// screen edge and the shadow to the caller. `Flyout` is the control Windows
/// itself uses for exactly this, and `showAt(_:)` takes the anchor directly --
/// which is the parameter the whole protocol exists for.
///
/// **The arrow is NOT the Flyout's.** This comment used to list "the beak" among
/// the things `Flyout` handles, and it draws none. The user reported it on
/// 2026-09-17 ("There is no arrow"), looking at P50 captures where the panel
/// was a plain rectangle, while GtkPopover beside it drew its beak. The arrow
/// is drawn by `PopoverArrow` below.
///
/// 為 WinUI 實作的 `.popover`，建構於 `Flyout` 之上。
///
/// 選 `Flyout` 而非 `Popup`。兩者都能把內容放到頁面之上，但 `Popup` 接受的是原始座標，並把點擊
/// 外部關閉、定位、在螢幕邊緣翻轉與陰影全部留給呼叫端。`Flyout` 則是 Windows 自己就用於
/// 此事的控制項，而 `showAt(_:)` 直接接受錨點——那正是整個 protocol 之所以存在的那個參數。
///
/// **箭頭不是 Flyout 畫的。** 這段註解原本把「尖角」列為 `Flyout` 會處理的東西之一,而它一個也沒畫。
/// 使用者 2026-09-17 回報(「There is no arrow」):P50 擷圖裡面板只是一個矩形,而旁邊的 GtkPopover
/// 畫出了尖角。箭頭由下方的 `PopoverArrow` 繪製。
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

        /// The element the flyout was last shown at, which the arrow points to.
        /// 上一次 flyout 顯示時所依附的元素,也就是箭頭要指向的地方。
        weak var anchor: WinUI.FrameworkElement?

        let arrow = PopoverArrow()

        init(content: WinUI.FrameworkElement) {
            flyout = WinUI.Flyout()
            flyout.content = content
            // Placed only once XAML has laid the presenter out, which is after
            // `opened`: at `opened` its size can still be zero. One turn of the
            // main queue is enough; the same deferral P69's readback needs.
            // 只在 XAML 排好 presenter 之後才放:`opened` 當下它的尺寸可能還是零。主佇列讓一輪就夠,
            // 與 P69 讀回所需的延後相同。
            flyout.opened.addHandler { [weak self] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let anchor = self.anchor else { return }
                        self.arrow.show(for: self.flyout, anchoredTo: anchor)
                    }
                }
            }
            flyout.closing.addHandler { [weak self] _, _ in
                self?.arrow.hide()
            }
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
        popover.anchor = anchor

        // Plain `showAt(anchor)`, and the room for the arrow is made afterwards by
        // `PopoverArrow`. `FlyoutShowOptions` was tried first and rejected, both
        // measured on P50 on 2026-09-17:
        // - `exclusionRect` alone: no effect. The gap stayed 4 DIP.
        // - `position` plus `exclusionRect`: the gap became right, but a
        //   `.leading` panel with no room on the left no longer flipped. It was
        //   clamped to x=0 on top of its own button (panel 0-301, button
        //   126-339).
        // 用樸素的 `showAt(anchor)`,箭頭的空間之後由 `PopoverArrow` 讓出。先試過 `FlyoutShowOptions`
        // 並放棄,兩者皆於 2026-09-17 以 P50 實測:只設 `exclusionRect` 沒有作用(間距仍是 4 DIP);
        // 加上 `position` 間距對了,但左側沒空間的 `.leading` 面板**不再翻轉**,被夾到 x=0、蓋在自己的
        // 按鈕上(面板 0–301,按鈕 126–339)。
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

/// The arrow between a popover and its anchor, which `Flyout` does not draw.
///
/// **It is placed from where the panel LANDED, not from where it was asked to
/// go.** A placement is a preference, and XAML moves the flyout when the
/// requested side has no room. Measured 2026-09-16: `.bottom` on a button near
/// the window's bottom edge opened above it. An arrow drawn from the preference
/// would point away from the anchor in exactly that case. So both rectangles
/// are read after layout, and the side follows from them.
///
/// It is a separate `Popup` with two `Path`s. The first is a filled triangle
/// whose base sinks into the panel far enough to cover the border line beneath
/// it. The second strokes only the two slanted sides, so the arrow and the
/// panel read as one outline. Both brushes are the presenter's own, whatever
/// the theme resolved them to, so light, dark and acrylic are matched rather
/// than guessed.
///
/// No arrow is drawn when the rectangles overlap (no side to point from), or
/// when the edge facing the anchor is too short to hold one clear of the
/// corners. A wrong arrow is worse than none.
///
/// popover 與其錨點之間的箭頭——`Flyout` 不畫它。
///
/// **位置依面板實際「落在」哪裡決定,不是依它被要求去哪裡。** placement 是偏好,要求的那一側沒有空間時
/// XAML 會移動 flyout。2026-09-16 實測:靠近視窗底緣的按鈕設 `.bottom`,面板開在它上方。依偏好畫的箭頭,
/// 在這種情況下正好會指離錨點。所以兩個矩形都在排版後讀取,側邊由它們推出。
///
/// 它是一個獨立的 `Popup`,內含兩個 `Path`:一個填滿的三角形(底邊陷入面板,足以蓋掉底下的邊框線),以及一條
/// 只描兩條斜邊的線,讓箭頭與面板讀起來是同一條外框。兩支筆刷都取自 presenter 自己——無論主題把它們解析成
/// 什麼——因此淺色、深色與壓克力都是對上的,而不是猜的。
///
/// 兩個矩形重疊(沒有可指的側邊),或面向錨點的那條邊太短、放不下一個避開圓角的箭頭時,就不畫。錯的箭頭比
/// 沒有箭頭更糟。
@MainActor
final class PopoverArrow {
    private let popup = WinUI.Popup()
    private let canvas = WinUI.Canvas()
    private let fill = WinUI.Path()
    private let outline = WinUI.Path()

    /// Base width and height of the triangle, in effective pixels.
    /// 三角形的底寬與高,單位為 effective pixel。
    private let baseWidth: Float = 20
    static let depth: Float = 10
    private var depth: Float { Self.depth }

    init() {
        canvas.isHitTestVisible = false
        canvas.children.append(fill)
        canvas.children.append(outline)
        popup.child = canvas
        popup.isHitTestVisible = false
    }

    func hide() {
        popup.isOpen = false
    }

    func show(for flyout: WinUI.Flyout, anchoredTo anchor: WinUI.FrameworkElement) {
        guard
            let content = flyout.content,
            let presenter = Self.presenter(containing: content)
        else {
            hide()
            return
        }
        // A presenter can be reused between openings, so any shift left from
        // the last one is removed before measuring.
        // presenter 可能在多次開啟之間被重用,因此量測前先移除上一次留下的位移。
        presenter.translation = WindowsFoundation.Vector3(x: 0, y: 0, z: 0)
        guard
            let root = anchor.xamlRoot?.content,
            var panel = Self.bounds(of: presenter, in: root),
            let target = Self.bounds(of: anchor, in: root)
        else {
            hide()
            return
        }

        if ProcessInfo.processInfo.environment["SCUI_DEBUG_POPOVER_ARROW"] == "1" {
            // stderr, unbuffered: a `print` into a pipe is lost when the process is killed.
            // 寫到不緩衝的 stderr:`print` 寫進管線時,行程被結束就會遺失。
            FileHandle.standardError.write(
                Data(
                    ("popover arrow: panel \(panel.minX),\(panel.minY)-\(panel.maxX),\(panel.maxY)"
                        + " anchor \(target.minX),\(target.minY)-\(target.maxX),\(target.maxY)\n").utf8
                )
            )
        }

        let corner = Float(max(presenter.cornerRadius.topLeft, presenter.cornerRadius.bottomRight))
        let border = Float(max(presenter.borderThickness.top, 1))
        // How far the base sinks into the panel: past the border, so the fill
        // hides the border line under the arrow.
        // 底邊陷入面板的深度:越過邊框,讓填色蓋掉箭頭底下那段邊框線。
        let sink = border + 1

        // Points in root coordinates: tip, then the two base corners.
        // 以 root 座標表示的點:尖端,再來是底邊的兩個角。
        let tip: (Float, Float)
        let baseA: (Float, Float)
        let baseB: (Float, Float)
        let half = baseWidth / 2

        func along(_ centre: Float, _ low: Float, _ high: Float) -> Float? {
            let lower = low + corner + half
            let upper = high - corner - half
            guard lower <= upper else { return nil }
            return min(max(centre, lower), upper)
        }

        // XAML leaves about 4 DIP between panel and anchor, and the arrow needs
        // its depth plus a little air, or its tip lands ON the button. Measured
        // 2026-09-17 on P50: gap 4 DIP on all four sides, tip over the button's
        // edge. The panel is moved the difference, away from the anchor, with
        // `translation`, which leaves XAML's placement and flipping untouched.
        // XAML 在面板與錨點之間只留約 4 DIP,而箭頭需要它的深度再加一點空隙,否則尖端會落在按鈕**上**。
        // 2026-09-17 以 P50 實測:四個方向間距都是 4 DIP、尖端壓在按鈕邊緣。面板以 `translation` 往遠離錨點
        // 的方向移動差額,這不會動到 XAML 的定位與翻轉。
        let air: Float = 3
        func shift(_ gap: Float) -> Float { max(0, depth + air - gap) }

        if panel.minY >= target.maxY - 1, let x = along(target.midX, panel.minX, panel.maxX) {
            // Panel below the anchor: arrow on its top edge, pointing up.
            // 面板在錨點下方:箭頭在它的上緣,朝上。
            let move = shift(panel.minY - target.maxY)
            presenter.translation = WindowsFoundation.Vector3(x: 0, y: move, z: 0)
            panel.minY += move
            panel.maxY += move
            tip = (x, panel.minY - depth)
            baseA = (x - half, panel.minY + sink)
            baseB = (x + half, panel.minY + sink)
        } else if panel.maxY <= target.minY + 1, let x = along(target.midX, panel.minX, panel.maxX) {
            let move = shift(target.minY - panel.maxY)
            presenter.translation = WindowsFoundation.Vector3(x: 0, y: -move, z: 0)
            panel.minY -= move
            panel.maxY -= move
            tip = (x, panel.maxY + depth)
            baseA = (x - half, panel.maxY - sink)
            baseB = (x + half, panel.maxY - sink)
        } else if panel.minX >= target.maxX - 1, let y = along(target.midY, panel.minY, panel.maxY) {
            let move = shift(panel.minX - target.maxX)
            presenter.translation = WindowsFoundation.Vector3(x: move, y: 0, z: 0)
            panel.minX += move
            panel.maxX += move
            tip = (panel.minX - depth, y)
            baseA = (panel.minX + sink, y - half)
            baseB = (panel.minX + sink, y + half)
        } else if panel.maxX <= target.minX + 1, let y = along(target.midY, panel.minY, panel.maxY) {
            let move = shift(target.minX - panel.maxX)
            presenter.translation = WindowsFoundation.Vector3(x: -move, y: 0, z: 0)
            panel.minX -= move
            panel.maxX -= move
            tip = (panel.maxX + depth, y)
            baseA = (panel.maxX - sink, y - half)
            baseB = (panel.maxX - sink, y + half)
        } else {
            hide()
            return
        }

        let originX = min(tip.0, baseA.0, baseB.0)
        let originY = min(tip.1, baseA.1, baseB.1)
        func local(_ point: (Float, Float)) -> WindowsFoundation.Point {
            WindowsFoundation.Point(x: point.0 - originX, y: point.1 - originY)
        }

        fill.data = Self.geometry([local(baseA), local(tip), local(baseB)], closed: true)
        fill.fill = presenter.background
        outline.data = Self.geometry([local(baseA), local(tip), local(baseB)], closed: false)
        outline.stroke = presenter.borderBrush
        outline.strokeThickness = Double(border)

        popup.xamlRoot = anchor.xamlRoot
        popup.shouldConstrainToRootBounds = flyout.shouldConstrainToRootBounds
        popup.horizontalOffset = Double(originX)
        popup.verticalOffset = Double(originY)
        popup.isOpen = true
    }

    private static func presenter(containing element: WinUI.DependencyObject) -> WinUI.FlyoutPresenter? {
        var current: WinUI.DependencyObject? = element
        while let node = current {
            if let presenter = node as? WinUI.FlyoutPresenter {
                return presenter
            }
            current = VisualTreeHelper.getParent(node)
        }
        return nil
    }

    private struct Box {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
        var midX: Float { (minX + maxX) / 2 }
        var midY: Float { (minY + maxY) / 2 }
    }

    private static func bounds(of element: WinUI.FrameworkElement, in root: WinUI.UIElement) -> Box? {
        guard
            element.actualWidth > 0, element.actualHeight > 0,
            let transform = try? element.transformToVisual(root),
            let rect = try? transform.transformBounds(
                WindowsFoundation.Rect(
                    x: 0, y: 0,
                    width: Float(element.actualWidth), height: Float(element.actualHeight)
                )
            )
        else { return nil }
        return Box(minX: rect.x, minY: rect.y, maxX: rect.x + rect.width, maxY: rect.y + rect.height)
    }

    private static func geometry(_ points: [WindowsFoundation.Point], closed: Bool) -> WinUI.PathGeometry {
        let geometry = WinUI.PathGeometry()
        let figure = WinUI.PathFigure()
        figure.startPoint = points[0]
        figure.isClosed = closed
        figure.isFilled = closed
        for point in points.dropFirst() {
            let segment = WinUI.LineSegment()
            segment.point = point
            figure.segments.append(segment)
        }
        geometry.figures.append(figure)
        return geometry
    }
}
