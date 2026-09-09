import CGtk
import DebugFeatures
import Gtk
@_spi(Backends) import SwiftCrossUI

/// `.popover` for GTK4, built on `GtkPopover`.
///
/// `GtkPopover` is the same primitive the backend's menus already use --
/// `GtkPopoverMenu` is a subclass of it -- but that is where the overlap ends.
/// `PopoverMenus` hands GTK a `GMenuModel`, and a menu model has no way to
/// express a `Slider`. This attaches an ordinary widget instead, via
/// `gtk_popover_set_child`, which is what `GtkPopover` was designed for and what
/// its own documentation recommends over `GtkPopoverMenu` for "dialog-like
/// behavior".
///
/// 為 GTK4 實作的 `.popover`，建構於 `GtkPopover` 之上。
///
/// `GtkPopover` 正是本 backend 的選單所使用的同一個基本元件——`GtkPopoverMenu` 是它的子類別
/// ——但兩者的共通點僅止於此。`PopoverMenus` 交給 GTK 的是 `GMenuModel`，而 menu model 無從表達
/// 一個 `Slider`。此處改為透過 `gtk_popover_set_child` 附上一個普通的 widget，那正是 `GtkPopover`
/// 被設計來承擔的用途，也正是它自己的文件在談到「dialog-like behavior」時所建議者。
extension GtkBackend {
    /// A `GtkPopover` plus the bookkeeping GTK does not do for us.
    ///
    /// Two things live here rather than on the `GtkPopover`:
    ///
    /// - **A strong reference to the content widget.** `setChild` says so in as
    ///   many words: GTK owns the GObject, but the Swift wrapper owns the
    ///   child's signal handlers, and those die with it. Without this field a
    ///   popover's buttons stop responding as soon as ARC gets to the wrapper.
    /// - **Whether the popover is still parented.** `removeFromAnchor` must run
    ///   exactly once, and there are two paths to a closed popover -- the user
    ///   clicking away, and `dismissPopover` -- which can both fire for a single
    ///   opening.
    ///
    /// A third field used to live here -- `isProgrammaticDismissal`, recording
    /// WHICH of those two paths a `closed` signal came from, so that
    /// `dismissPopover` could suppress the caller's `onDismiss:`. It is gone.
    /// SwiftUI runs `onDismiss:` when the presentation ends however it ended,
    /// AppKitBackend already did that (`NSPopover.performClose` runs
    /// `popoverDidClose`), and keeping the flag left three shipped backends
    /// disagreeing about one callback. Distinguishing the paths is no longer
    /// something this type needs to do.
    ///
    /// 一個 `GtkPopover`，外加 GTK 不會替我們做的記帳工作。
    ///
    /// 有兩樣東西放在此處而非放在 `GtkPopover` 上：
    ///
    /// - **對內容 widget 的強參考。** `setChild` 已經把話說得很清楚：GObject 歸 GTK 所有，但子元件
    ///   的 signal handler 歸 Swift wrapper 所有，而後者會隨 wrapper 一同消失。少了這個欄位，
    ///   popover 裡的按鈕會在 ARC 回收 wrapper 的那一刻起停止回應。
    /// - **popover 是否仍被 parent 著。** `removeFromAnchor` 必須恰好執行一次，而通往「已關閉的
    ///   popover」有兩條路——使用者點擊外部，以及 `dismissPopover`——兩者可能在同一次開啟中都觸發。
    ///
    /// 此處原本還有第三個欄位——`isProgrammaticDismissal`，用來記錄某次 `closed` 是從上述兩條路的
    /// 哪一條來的，好讓 `dismissPopover` 能壓住呼叫端的 `onDismiss:`。它已經被移除。SwiftUI 是
    /// 「無論 presentation 以何種方式結束，`onDismiss:` 都會執行」，AppKitBackend 本來就是這樣做的
    /// （`NSPopover.performClose` 會執行 `popoverDidClose`），而保留該旗標的結果，是三個已發布的
    /// backend 對同一個回呼各說各話。區分那兩條路已不再是本型別需要做的事。
    @MainActor
    public final class Popover {
        let popover: Gtk.Popover
        /// Held for its signal handlers. See the type's documentation.
        /// 為其 signal handler 而持有。見本型別的文件。
        let content: Gtk.Widget
        var onDismiss: (() -> Void)?
        var isAnchored = false
        /// The #111 input probes. Empty unless `DebugFeatures.isEnabled`.
        /// #111 的輸入探針。除非 `DebugFeatures.isEnabled`，否則為空。
        private var probes: [EventController] = []

        /// A CSS class carried by THIS popover and no other, so
        /// `presentationBackground` can be written as a descendant rule
        /// (`.class > contents`) without colouring every popover in the app.
        ///
        /// Its own rather than `Widget.customCSSClass`, which is private to the
        /// Gtk module.
        ///
        /// 一個**只有本 popover 持有**的 CSS class，好讓 `presentationBackground` 能以後代規則
        /// （`.class > contents`）寫出，而不會把 app 中每一個 popover 都上色。
        ///
        /// 自備而不沿用 `Widget.customCSSClass`，因為後者對 Gtk module 而言是 private 的。
        let popoverClass: String

        init(content: Gtk.Widget) {
            self.popover = Gtk.Popover()
            self.content = content
            self.popoverClass =
                "scui-popover-"
                + ObjectIdentifier(popover).debugDescription
                    .replacingOccurrences(of: "ObjectIdentifier(0x", with: "")
                    .replacingOccurrences(of: ")", with: "")
            gtk_widget_add_css_class(popover.widgetPointer, popoverClass)
            popover.setChild(content)
            // Light dismiss. A popover is not modal; clicking elsewhere closes
            // it, and that click is the `onDismiss` the modifier is waiting for.
            // 點擊外部即關閉。popover 並非模態；在別處點擊會關閉它，而那一次點擊正是該 modifier
            // 所等待的 `onDismiss`。
            popover.autohide = true
            popover.hasArrow = true
            // `onDismiss` fires on BOTH paths to a closed popover -- the user
            // clicking away, and `dismissPopover`. That matches SwiftUI, where
            // `onDismiss:` runs when the presentation ends however it ended,
            // and it is what AppKitBackend already did, since `NSPopover`'s
            // `performClose` runs `popoverDidClose`. This backend used to
            // suppress the programmatic case behind an `isProgrammaticDismissal`
            // flag, which made three shipped backends disagree about the same
            // callback.
            //
            // Firing on both paths does not loop, and the reason is in
            // `PopoverModifier`: the programmatic branch (`:164`) nils
            // `children.popover` immediately after calling `dismissPopover`, and
            // it is only entered when `isPresented` is ALREADY false. So the
            // `handleDismiss` this closure reaches runs the caller's closure
            // once, clears three fields that are already nil, and writes `false`
            // over a `false` -- no state change, so no further update.
            //
            // `onDismiss` 在通往「已關閉的 popover」的**兩條**路上都會觸發——使用者點擊外部，以及
            // `dismissPopover`。這與 SwiftUI 一致：無論presentation 以何種方式結束，`onDismiss:`
            // 都會執行；這也正是 AppKitBackend 原本的行為，因為 `NSPopover` 的 `performClose`
            // 會執行 `popoverDidClose`。本 backend 過去以 `isProgrammaticDismissal` 旗標壓住
            // 程式化的那一條路，導致三個已發布的 backend 對同一個回呼各說各話。
            //
            // 兩條路都觸發不會造成迴圈，理由在 `PopoverModifier` 裡：程式化分支（`:164`）在呼叫
            // `dismissPopover` 之後立刻把 `children.popover` 設為 nil，而且該分支只有在
            // `isPresented` **已經**為 false 時才會進入。因此本 closure 所抵達的 `handleDismiss`
            // 會執行呼叫端的 closure 一次、把三個已是 nil 的欄位再清一次，並在一個 `false` 上寫入
            // `false`——沒有狀態改變，也就不會再引發下一輪 update。
            popover.closed = { [weak self] _ in
                guard let self else { return }
                self.detach()
                self.onDismiss?()
            }

            installInputProbe()
        }

        /// Records what GTK actually receives on an open popover, so that "the
        /// click did nothing" can be split into the three things it might be.
        ///
        /// Task #111. A synthesised click measured as landing ON the popover
        /// (`WindowFromPoint` returned the popover's own toplevel) produces no
        /// action, and the two mechanisms first proposed for it were both
        /// refuted: the synthesiser posts nothing to a chosen window -- it uses
        /// `SetCursorPos` + `SendInput`, which the system routes from the cursor
        /// position -- and the foreground window was ruled out in the surprising
        /// direction, since the click that DID work was made while another
        /// application held the foreground.
        ///
        /// What is left is a question about delivery, and it cannot be answered
        /// from outside the process. These two controllers answer it:
        ///
        /// - motion fires, press does not -> the surface is receiving input and
        ///   button events specifically are not arriving. That points at the
        ///   Win32/GDK boundary and at injected input.
        /// - neither fires -> nothing reaches the popover surface at all,
        ///   whatever `WindowFromPoint` says about which window is under the
        ///   cursor.
        /// - both fire -> GTK has the event and it is being lost between the
        ///   popover and the button inside it, which is a propagation problem
        ///   and entirely ours.
        ///
        /// Both are in the CAPTURE phase deliberately. Capture runs from the
        /// toplevel down BEFORE the target widget's own handlers, so a probe
        /// there sees an event even when whatever is below would have consumed
        /// it -- a bubble-phase probe on a swallowed event reports the same
        /// silence as an event that never arrived, which is the distinction this
        /// exists to make. Neither controller returns a value, so neither can
        /// change what the popover does.
        ///
        /// 記錄 GTK 在一個已開啟的 popover 上究竟收到了什麼，好把「按了沒有反應」拆成它可能
        /// 是的那三件事。
        ///
        /// 任務 #111。一次被實測為**落在 popover 上**的合成點擊（`WindowFromPoint` 回傳的
        /// 正是 popover 自己的 toplevel）沒有產生任何動作，而最初為它提出的兩種機制都已被
        /// 推翻：合成器並不會把事件 post 給某個選定的視窗——它用的是 `SetCursorPos` 與
        /// `SendInput`，由系統依游標位置路由——而前景視窗則是以令人意外的方向被排除的，因為
        /// **成功**的那一次點擊，是在另一個應用程式持有前景時發出的。
        ///
        /// 剩下的是一個關於「事件送達」的問題，而它無法從行程外部回答。這兩個 controller
        /// 回答它：
        ///
        /// - motion 有、press 沒有 → 該 surface 確實收得到輸入，而**按鍵事件**特別地沒有
        ///   抵達。那指向 Win32/GDK 的邊界與注入式輸入。
        /// - 兩者皆無 → 無論 `WindowFromPoint` 怎麼說游標底下是哪個視窗，都沒有任何東西
        ///   抵達 popover 的 surface。
        /// - 兩者皆有 → GTK 拿到了事件，而它是在 popover 與其中的按鈕之間遺失的；那是一個
        ///   傳播問題，並且完全屬於我們自己。
        ///
        /// 兩者都刻意置於 CAPTURE 階段。capture 由 toplevel 向下執行，**早於**目標 widget
        /// 自己的處理常式，因此位於該階段的探針即使在下方的東西會吃掉事件時也看得到它——而
        /// 一個置於 bubble 階段的探針，對「被吃掉的事件」所回報的沉默，與「事件從未抵達」
        /// 完全相同，而那正是本探針存在所要區分的事。兩個 controller 都不回傳值，因此都
        /// 不會改變 popover 的行為。
        private func installInputProbe() {
            guard DebugFeatures.isEnabled else { return }

            // CAPTURE, and the control that says this probe is not itself the
            // bug was run on 2026-09-09 before any of it was reported.
            //
            // The worry is real: a capture-phase GtkGestureClick can CLAIM the
            // event sequence, and a claimed sequence never reaches the child
            // button. If that happened, this probe would be the cause of the
            // silence it exists to measure. So the whole sweep was re-run with
            // the phase set to `.bubble`, where an ancestor gesture cannot
            // pre-empt the target -- and the result was IDENTICAL: four presses
            // reported, no button action, counter still 0.
            //
            // So the probe is exonerated and capture is kept, because capture is
            // the phase that can see an event the target would have swallowed,
            // which is the distinction this whole thing exists to make.
            //
            // 用 CAPTURE;而「這個探針本身不是那個 bug」的對照,已於 2026-09-09 在任何回報之前執行過。
            //
            // 那份疑慮是真的:capture 階段的 `GtkGestureClick` 可能**認領**事件序列,而被認領的序列
            // 永遠到不了子按鈕。若真如此,這個探針就會是「它自己被建來量測的那份沉默」的成因。因此
            // 整個掃描以 `.bubble` 重跑了一次——在該階段,祖先的 gesture 無法搶在目標之前——而結果
            // **完全相同**:四次按壓皆有回報、按鈕無動作、計數器仍為 0。
            //
            // 探針因此洗清嫌疑,並保留 capture,因為 capture 才是「看得見目標本會吞掉之事件」的那個
            // 階段,而那正是這整套東西所要區分的事。
            let press = GestureClick()
            press.propagationPhase = .capture
            press.pressed = { _, nPress, x, y in
                DebugFeatures.log(
                    "GtkPopover probe: press n=\(nPress) at (\(x), \(y)) -- "
                        + "GTK received a button press on the popover"
                )
            }
            popover.addEventController(press)

            let motion = EventControllerMotion()
            motion.propagationPhase = .capture
            motion.enter = { _, x, y in
                DebugFeatures.log("GtkPopover probe: pointer entered at (\(x), \(y))")
            }
            motion.leave = { _ in
                DebugFeatures.log("GtkPopover probe: pointer left")
            }
            popover.addEventController(motion)

            // Held for the same reason `content` is: a controller's Swift
            // wrapper owns its signal handlers, and ARC collecting the wrapper
            // takes the probe with it -- silently, so the probe would report
            // the same nothing as the bug it is measuring.
            // 持有的理由與 `content` 相同：controller 的 Swift wrapper 擁有它自己的 signal
            // handler，而 ARC 回收該 wrapper 時會一併帶走這個探針——且是靜默地，於是探針會
            // 回報出與它所要量測的 bug 一模一樣的「什麼都沒有」。
            probes = [press, motion]

            // Announced, and this line is not decoration. Without it the probe
            // has the exact defect it exists to remove: "no probe output" and
            // "no probe" print the same nothing. Measured 2026-09-09 -- the
            // first run produced no probe lines at all, and the only reason
            // that was not read as "GTK receives nothing" is that the same log
            // showed the click had missed the popover by 120 points.
            //
            // 明確宣告，而且這一行不是裝飾。少了它，這個探針就帶有它自己所要消除的那個缺陷：
            // 「探針沒有輸出」與「根本沒有探針」印出來是同一片空白。2026-09-09 實測——第一次
            // 執行完全沒有任何探針行，而那之所以沒有被讀成「GTK 什麼都沒收到」，只是因為同一份
            // log 顯示那一下點擊離 popover 差了 120 點。
            DebugFeatures.log(
                "GtkPopover probe: installed (press + motion, capture phase)"
            )
        }

        func detach() {
            guard isAnchored else { return }
            isAnchored = false
            popover.removeFromAnchor()
        }
    }

    public func createPopover(content: Widget) -> Popover {
        Popover(content: content)
    }

    public func updatePopover(
        _ popover: Popover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        // Qualified, because `Gtk.Color` and `SwiftCrossUI.Color` are both in
        // scope in this module and the bare name is ambiguous. `updateSheet`
        // already spells it out for the same reason (GtkBackend.swift:5236).
        // 需要限定名稱,因為本 module 中 `Gtk.Color` 與 `SwiftCrossUI.Color` 同時在 scope,裸名有歧義。
        // `updateSheet` 早已基於相同理由寫全(GtkBackend.swift:5236)。
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        popover.onDismiss = onDismiss

        popover.content.setSizeRequest(width: size.x, height: size.y)

        // Set on every update, including back to nothing, because a colour
        // bound to state has to be removable as well as settable. Writing an
        // empty block is what removes it -- `loadCss` clears whatever the
        // provider held.
        //
        // SCOPED BY CLASS, and this is not a detail. `Widget.css` is a
        // `CSSBlock` keyed on the widget's own `customCSSClass`, whereas
        // `Widget.cssProvider` installs itself for the WHOLE DISPLAY
        // (`gtk_style_context_add_provider_for_display`, CSSProvider.swift:14).
        // A bare `popover { ... }` rule through the provider would colour every
        // popover in the application, menus and pickers included -- so the one
        // thing this feature promises, that only the popover asked for is
        // coloured, would be exactly what it failed to do. Measured while
        // experimenting on 2026-09-09.
        //
        // Only the fill is set. The theme keeps its border, shadow, corners and
        // arrow, so a coloured popover still looks like a popover on this
        // platform rather than a rectangle.
        //
        // 每次更新都設定,包括設回「沒有」,因為一個綁定於 state 的顏色不只要能被設定,也要能被移除。
        // 寫入一個空區塊就是移除它——`loadCss` 會清掉該 provider 原本持有的內容。
        //
        // **以 class 限定,而這不是細節。** `Widget.css` 是一個以該 widget 自身 `customCSSClass`
        // 為鍵的 `CSSBlock`;而 `Widget.cssProvider` 是把自己安裝到**整個 display**
        // (`gtk_style_context_add_provider_for_display`,CSSProvider.swift:14)。透過該 provider
        // 寫一條光禿禿的 `popover { ... }`,會把 app 中**每一個** popover 都上色,包含選單與 picker
        // ——於是本功能所承諾的唯一一件事「只有被要求的那個 popover 會上色」,恰好就是它做不到的事。
        // 此事於 2026-09-09 實驗時實測。
        //
        // 只設定填色。邊框、陰影、圓角與箭頭都留給主題,因此一個上了色的 popover 在這個平台上
        // 看起來仍然像個 popover,而不是一個矩形。
        // Written straight into the provider rather than through `Widget.css`,
        // and the reason is the node tree. `CSSBlock` emits exactly one
        // selector, `.class{...}` (CSSBlock.swift:18) -- it cannot express a
        // descendant. But GTK 4 does not paint a popover's fill on the
        // `popover` node: it paints it on the `contents` child. So a rule that
        // can only reach `.class` colours the RIM and leaves the interior at the
        // theme's own dark grey.
        //
        // MEASURED, and this is the run that caught it. `.presentationBackground(.green)`
        // through `Widget.css` produced a green BORDER around a still-dark
        // panel. The wiring was correct and the target was wrong -- and without
        // a positive control in a colour no theme here draws, "the app asked for
        // nothing" and "the colour landed on the wrong node" would both have
        // looked like an ordinary popover.
        //
        // Scoped by `popoverClass`, which is added to this popover and no other,
        // so the display-wide provider registration
        // (`gtk_style_context_add_provider_for_display`, CSSProvider.swift:14)
        // cannot leak this colour onto menus or pickers.
        //
        // 直接寫進 provider 而不經由 `Widget.css`,理由在節點樹。`CSSBlock` 只會產出**一個** selector
        // ——`.class{...}`(CSSBlock.swift:18)——它無法表達後代選擇器。但 GTK 4 並不是在 `popover`
        // 節點上繪製 popover 的填色,而是畫在 `contents` 子節點上。因此一條只到得了 `.class` 的規則,
        // 只會為**邊緣**上色,內部仍是主題自己的深灰。
        //
        // **實測,而這正是抓到它的那一次執行。** 透過 `Widget.css` 送出的
        // `.presentationBackground(.green)`,產出的是「一圈綠色邊框 + 依然深色的面板」。線路是對的,
        // 目標是錯的——而若沒有一個「此處任何主題都不會畫出的顏色」作為陽性對照,
        // 「app 什麼都沒要求」與「顏色落在錯的節點上」看起來都只是一個普通的 popover。
        //
        // 以 `popoverClass` 限定,該 class 只加在這一個 popover 上,因此 provider 的 display-wide
        // 註冊(`gtk_style_context_add_provider_for_display`,CSSProvider.swift:14)不會把這個顏色
        // 漏到選單或 picker 上。
        if let backgroundColor {
            let colour = CSSProperty.rgba(backgroundColor.gtkColor)
            popover.popover.cssProvider.loadCss(
                from: """
                    .\(popover.popoverClass),
                    .\(popover.popoverClass) > contents {
                        background-color: \(colour);
                    }
                    """
            )
        } else {
            // An empty sheet, not a rule setting some "default" colour: only
            // GTK knows what the theme would have drawn, and naming a colour
            // here would be this backend overruling the theme -- the mistake
            // `GtkBackend.swift:5129` documents at length.
            // 載入一份**空的** stylesheet,而不是寫一條「預設顏色」的規則:只有 GTK 知道主題原本會
            // 畫什麼,在此指名一個顏色等於由本 backend 蓋過主題——那正是 `GtkBackend.swift:5129`
            // 用很長篇幅記載的那個錯誤。
            popover.popover.cssProvider.loadCss(from: "")
        }

        // The background is left to the theme, and nothing here overrides it. A
        // GTK popover draws its own background, border, shadow and arrow, all of
        // them themed, and a flat colour painted over the top replaces every one
        // of them with a rectangle. That is the mistake `updatePopoverMenu` was
        // measured making on P20 (see GtkBackend.swift), where the backend's own
        // rgb(44,44,44) stood in for whatever the user's theme had chosen.
        // 背景交給主題，此處不覆寫它。GTK 的 popover 會自行繪製背景、邊框、陰影與尖角，而且全部
        // 都是有主題的；在上頭塗一塊扁平顏色，會把這其中的每一項都換成一個矩形。那正是
        // `updatePopoverMenu` 曾在 P20 上被實測到犯下的錯誤（見 GtkBackend.swift），當時
        // backend 自己的 rgb(44,44,44) 取代了使用者主題所選定的顏色。
    }

    public func presentPopover(_ popover: Popover, relativeTo anchor: Widget, window: Window) {
        popover.isAnchored = true
        // `position` is deliberately not set, so GTK keeps its own default of
        // `.bottom` -- below the anchor, where a popover opened from a button
        // belongs, and the side AppKit asks for with `.maxY`. GTK flips to
        // another side when the requested one would leave the monitor, and that
        // flip is precisely why the side is left to GTK: an edge pinned by this
        // backend would be honoured off the edge of the screen, and a popover
        // nobody can see has shown nothing.
        // 此處刻意不設定 `position`，讓 GTK 保有它自己的預設值 `.bottom`——位於錨點下方，也就是由
        // 按鈕開啟的 popover 該在的位置，與 AppKit 以 `.maxY` 所請求的那一側相同。當所請求的一側
        // 會超出螢幕時，GTK 會把它翻到另一側，而那個翻轉正是「把該選哪一側交給 GTK」的理由：由本
        // backend 釘死的一側會被忠實地遵守到螢幕之外，而一個沒人看得見的 popover 等於什麼都沒顯示。
        popover.popover.popUp(anchoredTo: anchor)
    }

    public func dismissPopover(_ popover: Popover, window: Window) {
        popover.popover.popDown()
        // `popDown` animates, and `closed` arrives at the end of it, so the
        // detach happens in the handler rather than here.
        // `popDown` 有動畫，而 `closed` 在動畫結束時才送達，因此卸下的動作在 handler 中進行，
        // 不在此處。
    }

    public func size(ofPopover popover: Popover) -> SIMD2<Int> {
        // The size request `updatePopover` set, read back with
        // `gtk_widget_get_size_request`. That call returns what was *requested*,
        // not what was allocated, so it answers for a popover that has never
        // been shown -- which an allocation (`gtk_widget_get_allocated_width`)
        // could not, since an unmapped GTK widget has no allocation.
        //
        // GTK returns `-1` on an axis nothing has requested yet, which is the
        // state between `createPopover` and the first `updatePopover`. GTK's own
        // preferred size answers there, rather than letting a negative number
        // reach the caller as if it were a measurement.
        //
        // 由 `updatePopover` 設定的 size request，以 `gtk_widget_get_size_request` 讀回。該呼叫
        // 回傳的是被**請求**的值，而非被配置的值，因此對一個從未顯示過的 popover 它仍答得出來
        // ——而配置（`gtk_widget_get_allocated_width`）做不到，因為尚未 map 的 GTK widget 根本
        // 沒有配置。
        //
        // 在尚無任何請求的軸上，GTK 會回傳 `-1`，那正是 `createPopover` 與第一次 `updatePopover`
        // 之間的狀態。此時改由 GTK 自己的偏好尺寸作答，而不是讓一個負數以「量測結果」的身分傳到
        // 呼叫端手上。
        let requested = popover.content.getSizeRequest()
        guard requested.width >= 0, requested.height >= 0 else {
            let natural = popover.content.getNaturalSize()
            return SIMD2(natural.width, natural.height)
        }
        return SIMD2(requested.width, requested.height)
    }
}
