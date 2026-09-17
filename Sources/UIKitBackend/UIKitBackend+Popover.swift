@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    public typealias Popover = CustomPopover

    public func createPopover(content: Widget) -> CustomPopover {
        let popover = CustomPopover()

        // `.popover` on every idiom, deliberately. On iPad and Mac Catalyst it
        // is an anchored popover; on iPhone UIKit adapts it into a sheet by
        // itself, because a popover on a phone would cover the thing it points
        // at. That adaptation is the platform's own answer and it is the right
        // one there -- which is a different thing from this backend choosing a
        // sheet on a device that would have drawn a popover.
        //
        // 在每一種 idiom 上都使用 `.popover`,這是刻意的。在 iPad 與 Mac Catalyst 上它是一個有錨點的
        // popover;在 iPhone 上,UIKit 會自行把它調適為 sheet——因為手機上的 popover 會蓋住它所指向的
        // 東西。那項調適是平台自身的答案,而且在那裡是正確的——這與「本 backend 在一個原本會畫出
        // popover 的裝置上選擇了 sheet」是兩回事。
        popover.modalPresentationStyle = .popover

        let contentView = UIView()
        if let childController = content.controller {
            popover.addChild(childController)
        }
        contentView.addSubview(content.view)
        popover.view = contentView
        popover.customContent = content.view

        return popover
    }

    public func updatePopover(
        _ popover: CustomPopover,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        backgroundColor: Color.Resolved?,
        onDismiss: @escaping () -> Void
    ) {
        let contentSize = CGSize(width: size.x, height: size.y)
        popover.preferredContentSize = contentSize
        popover.customContent?.frame = CGRect(origin: .zero, size: contentSize)
        popover.onDismiss = onDismiss

        // WRITTEN ON WINDOWS 2026-09-09 AND NOT RUN -- the Mac side verifies it,
        // the same handover as #117 and as the AppKit half of this change.
        //
        // On the presented view controller's own view. UIKit's popover chrome is
        // drawn by `UIPopoverBackgroundView`, which is subclass-only and would
        // mean a new type for a colour; setting the content's background gets
        // what was asked without that.
        //
        // `nil` clears it back to the platform's own backdrop, matching the
        // protocol's contract, so a colour bound to state is removable.
        //
        // **本段於 2026-09-09 在 Windows 上寫成,未曾執行**——由 Mac 那側驗證,與 #117 以及本次改動
        // 的 AppKit 那一半是相同的交接方式。
        //
        // 設在被呈現的 view controller 自身的 view 上。UIKit 的 popover 外觀是由
        // `UIPopoverBackgroundView` 繪製,而那個類別只能以子類別化使用,為了一個顏色去建立一個新型別
        // 並不划算;設定內容的背景即可達成所要求的事。
        //
        // `nil` 會把它清回平台自己的底色,符合 protocol 的約定,因此綁定於 state 的顏色可被移除。
        popover.view.backgroundColor = backgroundColor.map { $0.uiColor }
    }

    public func presentPopover(
        _ popover: CustomPopover,
        relativeTo anchor: Widget,
        window: Window
    ) {
        // The anchor is a view in the window, and UIKit positions from a view
        // plus a rect within it. Setting both is what makes this a popover
        // rather than a centred modal.
        // 錨點是視窗中的一個 view,而 UIKit 是以「一個 view 加上其內部的一個矩形」來定位的。
        // 兩者都設定,才使這成為一個 popover,而不是一個置中的 modal。
        if let presentation = popover.popoverPresentationController {
            presentation.sourceView = anchor.view
            presentation.sourceRect = anchor.view.bounds
            // **An arrow direction names where the ARROW is, which is the
            // opposite side from where the panel is.** `.up` is an arrow on the
            // popover's top edge, so the panel hangs BELOW the anchor -- and
            // `Edge` in this protocol names the side of the ANCHOR the panel
            // should be on. Getting this the natural-looking way round would
            // produce a popover that obeys every request backwards, which is
            // the kind of wrong that looks like a working feature until someone
            // reads the pair of captures.
            //
            // The default stays `[.up, .down]` rather than `.any`: it is what
            // this backend has always done, and widening it here would change
            // the placement of every popover that asks for nothing.
            //
            // **一個 arrow direction 指的是那支「箭頭」在哪一側,而那與面板所在的是相反的一側。**
            // `.up` 代表箭頭在 popover 的上緣,因此面板掛在錨點**下方**——而本協定裡的 `Edge` 指的是
            // 「面板該位於錨點的哪一側」。若照直覺對應,會得到一個把每個要求都做反的 popover,
            // 而那種錯誤在有人去讀那一對擷圖之前,看起來都像是功能正常。
            //
            // 沒有偏好時維持 `[.up, .down]` 而不是 `.any`:那是本 backend 一直以來的行為,
            // 在此放寬它會改變每一個「什麼都沒要求」的 popover 的位置。
            presentation.permittedArrowDirections =
                popover.preferredArrowEdge.map { edge in
                    Self.arrowDirection(
                        for: Self.edgeThatFits(edge, for: popover, anchoredTo: anchor.view)
                    )
                } ?? [.up, .down]
            presentation.delegate = popover
        }

        window.rootViewController?.present(popover, animated: true)
    }

    /// The requested side, or the opposite one when the panel does not fit.
    ///
    /// **This is UIKit made to answer the way Android does, deliberately.**
    /// Both platforms are given the same arithmetic when a side is asked for
    /// and the panel is taller than the room on it, and until 2026-09-17 they
    /// answered differently: `PopupWindow.showAsDropDown` MOVES a popup that
    /// does not fit to the other side of the anchor, keeping it whole, while
    /// UIKit SHRINKS the popover into whatever room the permitted direction
    /// has. P50 showed what that costs -- the panel came up below its button
    /// with `press me` and `close this panel` cut off the bottom edge, so the
    /// popover was present, anchored, obedient, and unusable.
    ///
    /// So the fit is computed here and the opposite side is asked for instead,
    /// which is Android's rule. UIKit's own behaviour is still the floor: when
    /// neither side has room it shrinks, and that is better than nothing on
    /// screen.
    ///
    /// The comparison is done in the window's coordinate space, against the
    /// safe area, because a phone's rounded corners and home indicator are not
    /// room the popover can use.
    ///
    /// 被要求的那一側;若面板放不下,則改為相反的那一側。
    ///
    /// **這是刻意讓 UIKit 用 Android 的方式作答。** 當「某一側被要求、而面板比那一側的空間更高」時,
    /// 兩個平台面對的是同一道算術,而在 2026-09-17 之前它們的答案不同:
    /// `PopupWindow.showAsDropDown` 會把放不下的 popup **移到**錨點的另一側、保持它完整,
    /// 而 UIKit 會把 popover **縮**進被允許方向所擁有的空間裡。P50 顯示了那要付出什麼代價
    /// ——面板出現在按鈕下方,而 `press me` 與 `close this panel` 被下緣切掉了:那個 popover 存在、
    /// 有錨定、也服從了要求,而且不能用。
    ///
    /// 因此此處自行算出是否放得下,放不下就改要求相反的那一側,那正是 Android 的規則。UIKit 自己的行為
    /// 仍是底線:兩側都沒有空間時它會縮小,而那總比畫面上什麼都沒有好。
    ///
    /// 比較是在視窗座標空間裡、對著 safe area 做的,因為手機的圓角與 home indicator 並不是這個 popover
    /// 用得上的空間。
    private static func edgeThatFits(
        _ edge: SwiftCrossUI.Edge,
        for popover: CustomPopover,
        anchoredTo anchor: UIView
    ) -> SwiftCrossUI.Edge {
        guard let window = anchor.window else { return edge }

        let frame = anchor.convert(anchor.bounds, to: window)
        let safe = window.safeAreaInsets
        let size = popover.preferredContentSize
        // The arrow itself, which UIKit draws outside the content.
        // 箭頭本身,UIKit 會把它畫在內容之外。
        let arrow: CGFloat = 13

        let roomAbove = frame.minY - safe.top
        let roomBelow = window.bounds.maxY - safe.bottom - frame.maxY
        let roomLeading = frame.minX - safe.left
        let roomTrailing = window.bounds.maxX - safe.right - frame.maxX

        switch edge {
            case .top:
                return roomAbove < size.height + arrow && roomBelow >= size.height + arrow
                    ? .bottom : .top
            case .bottom:
                return roomBelow < size.height + arrow && roomAbove >= size.height + arrow
                    ? .top : .bottom
            case .leading:
                return roomLeading < size.width + arrow && roomTrailing >= size.width + arrow
                    ? .trailing : .leading
            case .trailing:
                return roomTrailing < size.width + arrow && roomLeading >= size.width + arrow
                    ? .leading : .trailing
        }
    }

    /// The arrow direction that puts the panel on `edge` of its anchor.
    /// 使面板位於錨點 `edge` 側的那個 arrow direction。
    private static func arrowDirection(
        for edge: SwiftCrossUI.Edge
    ) -> UIPopoverArrowDirection {
        switch edge {
            case .top: return .down
            case .bottom: return .up
            case .leading: return .right
            case .trailing: return .left
        }
    }

    public func dismissPopover(_ popover: CustomPopover, window: Window) {
        popover.dismissProgrammatically()
    }

    public func size(ofPopover popover: CustomPopover) -> SIMD2<Int> {
        SIMD2(
            Int(popover.preferredContentSize.width),
            Int(popover.preferredContentSize.height)
        )
    }
}

/// A popover that reports its own dismissal.
///
/// A popover is dismissed by tapping outside it, and nothing in the view tree
/// hears that. Without the callback the modifier's `isPresented` stays true,
/// the next press is a no-op because it is already "presented", and the popover
/// never returns. `CustomSheet` carries the same machinery for the same reason.
///
/// 一個會回報自身關閉的 popover。
///
/// popover 是靠點擊它以外的地方來關閉的,而 view 樹中沒有任何東西會聽到。少了這個回呼,modifier 的
/// `isPresented` 會維持為真,下一次按下不會有任何作用——因為它「已經呈現了」——而該 popover 再也不會
/// 回來。`CustomSheet` 基於同樣的理由帶有同樣的機制。
public final class CustomPopover: UIViewController, UIPopoverPresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    var customContent: UIView?

    /// Which side of the anchor this popover has been asked to appear on
    /// (#109), or `nil` for the platform's own choice.
    ///
    /// Kept here because the presentation controller only exists while the
    /// popover is being presented, and the protocol sets the preference before
    /// that -- see `BackendFeatures.PopoverArrowEdges`.
    ///
    /// 這個 popover 被要求出現在錨點的哪一側(#109);`nil` 代表交由平台自行決定。
    ///
    /// 存放於此,是因為 presentation controller 只在呈現期間存在,而協定設定這個偏好的時機在那之前
    /// ——見 `BackendFeatures.PopoverArrowEdges`。
    var preferredArrowEdge: SwiftCrossUI.Edge?

    func dismissProgrammatically() {
        dismiss(animated: true)
    }

    /// **Stays a popover on a phone, and until 2026-09-17 it did not.**
    ///
    /// UIKit adapts a popover to a sheet in a horizontally compact size class
    /// unless the delegate says otherwise, and on an iPhone that is every
    /// popover. Measured with P50 that day: the panel filled the screen from
    /// the top, anchored to nothing --
    /// `p50-ios-final-20260917-161038.png`. Both of P50's panels looked
    /// identical, so its own assertion -- "each panel must land NEXT TO THE
    /// BUTTON THAT OPENED IT" -- had nothing to land on, and #109's edge
    /// preference had no side to take.
    ///
    /// `.none` is the documented way to refuse the adaptation, and it is what
    /// this backend's contract already promised: ``BackendFeatures/Popovers``
    /// says an anchored panel is the whole difference between a popover and a
    /// sheet, and a backend that quietly hands back a sheet is not implementing
    /// the protocol it conforms to.
    ///
    /// **在手機上維持為 popover,而在 2026-09-17 之前它並沒有。**
    ///
    /// 在水平方向為 compact 的 size class 下,UIKit 會把 popover 調整成 sheet——除非 delegate 另有
    /// 交代——而在 iPhone 上那就是每一個 popover。當天以 P50 實測:那塊面板從畫面頂端整片蓋下來、
    /// 沒有錨定在任何東西上(`p50-ios-final-20260917-161038.png`)。P50 的兩塊面板看起來一模一樣,
    /// 於是它自己的斷言——「每塊面板都必須落在**開啟它的那顆按鈕旁邊**」——沒有東西可落;而 #109 的
    /// 邊偏好也沒有側邊可選。
    ///
    /// `.none` 是文件所載「拒絕該調整」的方式,而那也正是本 backend 的約定原本就承諾的:
    /// ``BackendFeatures/Popovers`` 說「錨定」就是 popover 與 sheet 的全部差別,而一個悄悄交回一張
    /// sheet 的 backend,並沒有實作它所 conform 的那個協定。
    public func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    // Both paths report, and the programmatic one is NOT suppressed.
    //
    // It was, until 2026-09-08. The reasoning was that a caller who set
    // `isPresented = false` already knows the popover is going away, so telling
    // it again is noise -- which is wrong for the same reason SwiftUI's
    // `onDismiss` fires either way: the closure is where the caller cleans up
    // after the presentation, and whether the user tapped outside or the code
    // asked has nothing to do with whether that cleanup is needed.
    //
    // Suppressing it also made this backend the odd one out. AppKit never
    // suppressed, and the Windows side removed the equivalent flags from GTK
    // and WinUI in the same decision; this was the last of the five still
    // holding one, and it was mine.
    //
    // 兩條路徑都會回報,而程式化關閉的那一條**不再被抑制**。
    //
    // 它原本是被抑制的,直到 2026-09-08。當時的理由是:設定 `isPresented = false` 的呼叫端已經知道
    // popover 要消失了,再告訴它一次只是雜訊——而那是錯的,理由與 SwiftUI 的 `onDismiss` 兩種情況
    // 都會觸發相同:那個 closure 是呼叫端在呈現結束後做清理的地方,而「是使用者點了外面」還是
    // 「程式碼要求的」,與那份清理需不需要做完全無關。
    //
    // 抑制它也讓本 backend 成為五個之中的異類。AppKit 從來沒有抑制過,而 Windows 端在同一項決定中
    // 移除了 GTK 與 WinUI 的對應旗標;這是五個裡最後一個還壓著的,而它是我寫的。
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss?()
    }
}

extension UIKitBackend: BackendFeatures.PopoverArrowEdges {
    /// Stores the preference; ``presentPopover(_:relativeTo:window:)`` spends it
    /// on `permittedArrowDirections`.
    ///
    /// **A permitted direction is a constraint, not a position**, and that is
    /// exactly the shape this protocol asks for: UIKit picks a direction from
    /// the set that fits, so naming one asks for that side and still lets the
    /// platform move the panel when there is no room -- it falls back to what
    /// fits rather than drawing off screen.
    ///
    /// 存下這個偏好;由 ``presentPopover(_:relativeTo:window:)`` 用在 `permittedArrowDirections` 上。
    ///
    /// **「被允許的方向」是一個限制,而不是一個位置**,而那正是本協定所要的形狀:UIKit 會從集合中挑一個
    /// 放得下的方向,因此指名其中一個等於要求那一側,同時仍讓平台在空間不足時移動面板
    /// ——它會退回到放得下的位置,而不是畫到螢幕外。
    public func setPreferredArrowEdge(ofPopover popover: CustomPopover, to edge: Edge?) {
        popover.preferredArrowEdge = edge
    }
}
